/// Set methods - .add(), .remove(), .discard(), .clear(), .copy(), .update(), etc.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;

/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try self.emit("(");
        try self.genExpr(obj);
        try self.emit(")");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for set.add(elem)
/// Adds element to set (no-op if already present)
pub fn genAdd(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: try set.put(elem, {})
    // Zig HashMap uses put(key, value) - for sets, value is void ({})
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".put(");
    try self.genExpr(args[0]);
    try self.emit(", {})");
}

/// Generate code for set.remove(elem)
/// Removes element, raises KeyError if not present
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: if (!(if (@hasDecl(@TypeOf(set), "swapRemove")) set.swapRemove(elem) else set.remove(elem))) return error.KeyError;
    // AutoHashMap uses .remove(), ArrayHashMap uses .swapRemove()
    // Both return bool (true if removed, false if not present)
    try self.emit("if (!(if (@hasDecl(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit("), \"swapRemove\")) ");
    try emitObjExpr(self, obj);
    try self.emit(".swapRemove(");
    try self.genExpr(args[0]);
    try self.emit(") else ");
    try emitObjExpr(self, obj);
    try self.emit(".remove(");
    try self.genExpr(args[0]);
    try self.emit("))) return error.KeyError");
}

/// Generate code for set.discard(elem)
/// Removes element if present (no error if missing)
pub fn genDiscard(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: { _ = (if (@hasDecl(@TypeOf(set), "swapRemove")) set.swapRemove(elem) else set.remove(elem)); }
    // AutoHashMap uses .remove(), ArrayHashMap uses .swapRemove()
    // Both return bool (true if removed, false if not present) - discard ignores result
    // Wrapping in a block makes this a statement that evaluates to void
    try self.emit("{ _ = (if (@hasDecl(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit("), \"swapRemove\")) ");
    try emitObjExpr(self, obj);
    try self.emit(".swapRemove(");
    try self.genExpr(args[0]);
    try self.emit(") else ");
    try emitObjExpr(self, obj);
    try self.emit(".remove(");
    try self.genExpr(args[0]);
    try self.emit(")); }");
}

/// Generate code for set.clear()
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitObjExpr(self, obj);
    // std.AutoHashMap uses clearRetainingCapacity() or clearAndFree()
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for set.pop()
/// Remove and return arbitrary element, raises KeyError if empty
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate: blk: { var iter = set.iterator(); const entry = iter.next() orelse return error.KeyError;
    //           const key = entry.key_ptr.*; _ = (if hasDecl then swapRemove else remove)(key); break :blk key; }
    // AutoHashMap uses .remove(), ArrayHashMap uses .swapRemove()
    try self.emit("blk: { var __set_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator(); const __entry = __set_iter.next() orelse return error.KeyError; const __key = __entry.key_ptr.*; _ = (if (@hasDecl(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit("), \"swapRemove\")) ");
    try emitObjExpr(self, obj);
    try self.emit(".swapRemove(__key) else ");
    try emitObjExpr(self, obj);
    try self.emit(".remove(__key)); break :blk __key; }");
}

/// Generate code for set.copy()
/// Returns shallow copy of set
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    // Generate a block that creates new set and copies elements
    try self.output.writer(self.allocator).print("(scopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __copy = @TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.emit("var __iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("try __copy.put(entry.key_ptr.*, {});\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :scopy_{d} __copy;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.update(*others)
/// Adds all elements from all other iterables (in-place)
/// Returns None in Python
/// - No args: no-op (but valid Python)
/// - One or more args: add elements from each
pub fn genUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: no-op, return null
        try self.emit("null");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(supdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each arg, iterate and add elements
    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var __other_{d} = __other_set_{d}.iterator();\n", .{ i, i });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while (__other_{d}.next()) |entry| {{\n", .{i});
        self.indent_level += 1;
        try self.emitIndent();
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".put(entry.key_ptr.*, {});\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :supdate_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.union(*others)
/// Returns new set with elements from self and all others
/// - No args: returns copy of self
/// - One or more args: union with each
pub fn genUnion(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sunion_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set and copy self into it
    try self.emitIndent();
    try self.emit("var __result = @TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("try __result.put(entry.key_ptr.*, {});\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from each arg
    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var __other_{d} = __other_set_{d}.iterator();\n", .{ i, i });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while (__other_{d}.next()) |entry| {{\n", .{i});
        self.indent_level += 1;
        try self.emitIndent();
        try self.emit("try __result.put(entry.key_ptr.*, {});\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sunion_{d} __result;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.intersection(*others)
/// Returns new set with elements common to self and all others
/// - No args: returns copy of self
/// - One or more args: keep only elements that exist in all
pub fn genIntersection(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sinter_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that exist in all others
    try self.emitIndent();
    try self.emit("var __result = @TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;

    // Check if element exists in all other sets
    try self.emitIndent();
    try self.emit("var __in_all = true;\n");

    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!__other_set_{d}.contains(entry.key_ptr.*)) __in_all = false;\n", .{i});
    }

    try self.emitIndent();
    try self.emit("if (__in_all) try __result.put(entry.key_ptr.*, {});\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sinter_{d} __result;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.difference(*others)
/// Returns new set with elements in self but not in any other
/// - No args: returns copy of self
/// - One or more args: keep only elements not in any other
pub fn genDifference(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that don't exist in any other
    try self.emitIndent();
    try self.emit("var __result = @TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;

    // Check if element exists in any other set
    try self.emitIndent();
    try self.emit("var __in_any = false;\n");

    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (__other_set_{d}.contains(entry.key_ptr.*)) __in_any = true;\n", .{i});
    }

    try self.emitIndent();
    try self.emit("if (!__in_any) try __result.put(entry.key_ptr.*, {});\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sdiff_{d} __result;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.symmetric_difference(other)
/// Returns new set with elements in either set but not both
/// Requires exactly one argument
pub fn genSymmetricDifference(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"symmetric_difference requires exactly one argument\")");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(ssymdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set
    try self.emitIndent();
    try self.emit("var __result = @TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    // Store other set in a variable first
    try self.emitIndent();
    try self.emit("const __other_set = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Add elements from self that are NOT in other
    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");
    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!__other_set.contains(entry.key_ptr.*)) try __result.put(entry.key_ptr.*, {});\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from other that are NOT in self
    try self.emitIndent();
    try self.emit("var __other_iter = __other_set.iterator();\n");
    try self.emitIndent();
    try self.emit("while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.emit(".contains(entry.key_ptr.*)) try __result.put(entry.key_ptr.*, {});\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiff_{d} __result;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.issubset(other)
pub fn genIssubset(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"issubset requires exactly one argument\")");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sissubset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __is_subset = true;\n");

    try self.emitIndent();
    try self.emit("const __other_set = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!__other_set.contains(entry.key_ptr.*)) { __is_subset = false; break; }\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissubset_{d} __is_subset;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.issuperset(other)
pub fn genIssuperset(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"issuperset requires exactly one argument\")");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sissuperset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __is_superset = true;\n");

    try self.emitIndent();
    try self.emit("const __other_set = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var __other_iter = __other_set.iterator();\n");

    try self.emitIndent();
    try self.emit("while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.emit(".contains(entry.key_ptr.*)) { __is_superset = false; break; }\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissuperset_{d} __is_superset;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.isdisjoint(other)
pub fn genIsdisjoint(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"isdisjoint requires exactly one argument\")");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sisdisjoint_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __is_disjoint = true;\n");

    try self.emitIndent();
    try self.emit("const __other_set = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (__other_set.contains(entry.key_ptr.*)) { __is_disjoint = false; break; }\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sisdisjoint_{d} __is_disjoint;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.intersection_update(*others)
/// Modifies set in-place, keeping only elements found in all others
/// Returns None in Python
pub fn genIntersectionUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("null");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sinterupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Collect keys to remove (can't modify while iterating)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.emit("var __to_remove = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __in_all = true;\n");

    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!__other_set_{d}.contains(entry.key_ptr.*)) __in_all = false;\n", .{i});
    }

    try self.emitIndent();
    try self.emit("if (!__in_all) try __to_remove.append(__global_allocator, entry.key_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Remove collected keys (handle both AutoHashMap and ArrayHashMap)
    try self.emitIndent();
    try self.emit("for (__to_remove.items) |key| { _ = (if (@hasDecl(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit("), \"swapRemove\")) ");
    try emitObjExpr(self, obj);
    try self.emit(".swapRemove(key) else ");
    try emitObjExpr(self, obj);
    try self.emit(".remove(key)); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sinterupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.difference_update(*others)
/// Modifies set in-place, removing elements found in any other
/// Returns None in Python
pub fn genDifferenceUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("null");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(sdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each other set, remove its elements from self
    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __other_set_{d} = ", .{i});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var __other_{d} = __other_set_{d}.iterator();\n", .{ i, i });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while (__other_{d}.next()) |entry| {{\n", .{i});
        self.indent_level += 1;
        try self.emitIndent();
        // Handle both AutoHashMap (.remove) and ArrayHashMap (.swapRemove)
        try self.emit("_ = (if (@hasDecl(@TypeOf(");
        try emitObjExpr(self, obj);
        try self.emit("), \"swapRemove\")) ");
        try emitObjExpr(self, obj);
        try self.emit(".swapRemove(entry.key_ptr.*) else ");
        try emitObjExpr(self, obj);
        try self.emit(".remove(entry.key_ptr.*));\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sdiffupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.symmetric_difference_update(other)
/// Modifies set in-place, keeping elements in either but not both
/// Returns None in Python
pub fn genSymmetricDifferenceUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"symmetric_difference_update requires exactly one argument\")");
        return;
    }

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("(ssymdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store other set first
    try self.emitIndent();
    try self.emit("const __other_set = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Collect keys to remove (in both sets)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.emit("var __to_remove = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.emit("var __to_add = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    // Find elements in self that are in other (to remove)
    try self.emitIndent();
    try self.emit("var __self_iter = ");
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (__self_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (__other_set.contains(entry.key_ptr.*)) try __to_remove.append(__global_allocator, entry.key_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Find elements in other that are not in self (to add)
    try self.emitIndent();
    try self.emit("var __other_iter = __other_set.iterator();\n");

    try self.emitIndent();
    try self.emit("while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.emit(".contains(entry.key_ptr.*)) try __to_add.append(__global_allocator, entry.key_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Apply changes (handle both AutoHashMap and ArrayHashMap)
    try self.emitIndent();
    try self.emit("for (__to_remove.items) |key| { _ = (if (@hasDecl(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit("), \"swapRemove\")) ");
    try emitObjExpr(self, obj);
    try self.emit(".swapRemove(key) else ");
    try emitObjExpr(self, obj);
    try self.emit(".remove(key)); }\n");

    try self.emitIndent();
    try self.emit("for (__to_add.items) |key| { try ");
    try emitObjExpr(self, obj);
    try self.emit(".put(key, {}); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiffupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}
