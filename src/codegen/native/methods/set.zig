/// Set methods - .add(), .remove(), .discard(), .clear(), .copy(), .update(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const expr_emitter = @import("../expr_emitter.zig");
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;

/// Check if a set expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain sets to runtime helpers
fn isSetUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try self.emitParens(obj);
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for set.add(elem)
/// Adds element to set (no-op if already present)
/// Two-Flow: Certain sets use HashMap.put, uncertain use runtime.pySetAdd
pub fn genAdd(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.add() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (isSetUncertain(self, obj)) {
        // Route to runtime helper for PyValue sets
        try self.emit("try runtime.pySetAddPV(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

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
/// Two-Flow: Certain sets use runtime.set_ops, uncertain use runtime.pySetRemove
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.remove() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (isSetUncertain(self, obj)) {
        // Route to runtime helper for PyValue sets
        try self.emit("try runtime.pySetRemovePV(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Use runtime helper to avoid comptime explosion from @hasDecl/@TypeOf inline checks
    // runtime.set_ops.SetOps(KeyType).remove(&set, key) handles AutoHashMap vs ArrayHashMap
    try self.emit("try runtime.set_ops.SetOps(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit(")).remove(&");
    try emitObjExpr(self, obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for set.discard(elem)
/// Removes element if present (no error if missing)
/// Two-Flow: Certain sets use runtime.set_ops, uncertain use runtime.pySetDiscard
pub fn genDiscard(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.discard() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (isSetUncertain(self, obj)) {
        // Route to runtime helper for PyValue sets
        try self.emit("runtime.pySetDiscardPV(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Use runtime helper to avoid comptime explosion from @hasDecl/@TypeOf inline checks
    try self.emit("runtime.set_ops.SetOps(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit(")).discard(&");
    try emitObjExpr(self, obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for set.clear()
/// Two-Flow: Certain sets use clearRetainingCapacity, uncertain use runtime.pySetClear
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (isSetUncertain(self, obj)) {
        // Route to runtime helper for PyValue sets
        try self.emit("runtime.pySetClearPV(&");
        try self.genExpr(obj);
        try self.emit(")");
        return;
    }

    try emitObjExpr(self, obj);
    // std.AutoHashMap uses clearRetainingCapacity() or clearAndFree()
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for set.pop()
/// Remove and return arbitrary element, raises KeyError if empty
/// Two-Flow: Certain sets use runtime.set_ops.pop, uncertain use runtime.pySetPop
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (isSetUncertain(self, obj)) {
        // Route to runtime helper for PyValue sets
        try self.emit("try runtime.pySetPopPVFunc(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(")");
        return;
    }

    // Use runtime helper to avoid comptime explosion
    // Get key type from set's KV struct
    try self.emit("try runtime.set_ops.SetOps(std.meta.fieldInfo(@TypeOf(");
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type).pop(&");
    try emitObjExpr(self, obj);
    try self.emit(")");
}

/// Generate code for set.copy()
/// Returns shallow copy of set
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const copy = try self.name_gen.temp();
    const iter = try self.name_gen.temp();

    // Generate a block that creates new set and copies elements
    try self.output.writer(self.allocator).print("(scopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{copy});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{copy});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :scopy_{d} {s};\n", .{ label_id, copy });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try self.output.writer(self.allocator).print("(supdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each arg, iterate and add elements
    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sunion_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set and copy self into it
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from each arg
    for (args, 0..) |arg, i| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
        self.indent_level += 1;
        try self.emitIndent();
        try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
        _ = i;
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sunion_{d} {s};\n", .{ label_id, result });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_all = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sinter_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that exist in all others
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    // Check if element exists in all other sets
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{in_all});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {s} = false;\n", .{ other_set, in_all });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}) try {s}.put(entry.key_ptr.*, {{}});\n", .{ in_all, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sinter_{d} {s};\n", .{ label_id, result });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_any = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that don't exist in any other
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    // Check if element exists in any other set
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = false;\n", .{in_any});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) {s} = true;\n", .{ other_set, in_any });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}) try {s}.put(entry.key_ptr.*, {{}});\n", .{ in_any, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sdiff_{d} {s};\n", .{ label_id, result });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(ssymdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    // Store other set in a variable first
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Add elements from self that are NOT in other
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) try {s}.put(entry.key_ptr.*, {{}});\n", .{ other_set, result });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from other that are NOT in self
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiff_{d} {s};\n", .{ label_id, result });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_subset = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sissubset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_subset});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{ other_set, is_subset });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissubset_{d} {s};\n", .{ label_id, is_subset });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_superset = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sissuperset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_superset});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{is_superset});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissuperset_{d} {s};\n", .{ label_id, is_superset });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_disjoint = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sisdisjoint_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_disjoint});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{ other_set, is_disjoint });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sisdisjoint_{d} {s};\n", .{ label_id, is_disjoint });

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const to_remove = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_all = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sinterupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Collect keys to remove (can't modify while iterating)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{in_all});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {s} = false;\n", .{ other_set, in_all });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{ in_all, to_remove });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Remove collected keys - use runtime helper to avoid comptime explosion
    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ runtime.set_ops.SetOps(@TypeOf(key)).discard(&", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(", key); }\n");

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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try self.output.writer(self.allocator).print("(sdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each other set, remove its elements from self
    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
        self.indent_level += 1;
        try self.emitIndent();
        // Use runtime helper to avoid comptime explosion
        try self.emit("runtime.set_ops.SetOps(@TypeOf(entry.key_ptr.*)).discard(&");
        try emitObjExpr(self, obj);
        try self.emit(", entry.key_ptr.*);\n");
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

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const other_set = try self.name_gen.temp();
    const to_remove = try self.name_gen.temp();
    const to_add = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(ssymdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store other set first
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Collect keys to remove (in both sets)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_add});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    // Find elements in self that are in other (to remove)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{ other_set, to_remove });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Find elements in other that are not in self (to add)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{to_add});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Apply changes - use runtime helper to avoid comptime explosion
    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ runtime.set_ops.SetOps(@TypeOf(key)).discard(&", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(", key); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ try ", .{to_add});
    try emitObjExpr(self, obj);
    try self.emit(".put(key, {}); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiffupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}
