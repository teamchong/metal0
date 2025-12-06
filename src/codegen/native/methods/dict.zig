/// Dict methods - .get(), .keys(), .values(), .items(), .pop(), .update(), .clear(), .copy(),
/// .setdefault(), .popitem(), .fromkeys()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const NativeType = @import("../../../analysis/native_types.zig").NativeType;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;

/// Generate code for dict.get(key, default)
/// Returns value if key exists, otherwise returns default (or null if no default)
/// If no args, generates generic method call (for custom class methods)
pub fn genGet(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // Not a dict.get() - must be custom class method with no args
        // Generate generic method call: obj.get()
        try self.genExpr(obj);
        try self.emit(".get()");
        return;
    }

    const default_val = if (args.len >= 2) args[1] else null;

    // Check if obj produces a block/struct expression that can't have
    // methods called on them directly in Zig. Need to assign to intermediate variable.
    const is_dict_literal = producesBlockExpression(obj);

    if (is_dict_literal) {
        // Wrap in block with intermediate variable
        // Use parentheses to prevent "label:" from being parsed as named argument
        const label_id = self.block_label_counter;
        self.block_label_counter += 1;
        try self.output.writer(self.allocator).print("(dget_{d}: {{\n", .{label_id});
        self.indent();
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("break :dget_{d} ", .{label_id});

        if (default_val) |def| {
            try self.emit("__dict_temp.get(");
            try self.genExpr(args[0]);
            try self.emit(") orelse ");
            try self.genExpr(def);
        } else {
            try self.emit("__dict_temp.get(");
            try self.genExpr(args[0]);
            try self.emit(").?");
        }
        try self.emit(";\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("})");
    } else {
        if (default_val) |def| {
            // Generate: dict.get(key) orelse default
            try self.genExpr(obj);
            try self.emit(".get(");
            try self.genExpr(args[0]);
            try self.emit(") orelse ");
            try self.genExpr(def);
        } else {
            // Generate: dict.get(key).? (force unwrap - assumes key exists, like Python does)
            // Python's dict.get(key) without default returns None if key not found,
            // but in AOT context, we assume keys exist for typed access
            try self.genExpr(obj);
            try self.emit(".get(");
            try self.genExpr(args[0]);
            try self.emit(").?");
        }
    }
}

/// Generate code for dict.keys()
/// Returns list of keys (always []const u8 for StringHashMap)
pub fn genKeys(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // keys() takes no arguments

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that builds list of keys using .keys() slice
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(dkeys_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _keys_list = std.ArrayListUnmanaged([]const u8){};\n");

    try self.emitIndent();
    try self.emit("for (");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".keys()) |key| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("try _keys_list.append(__global_allocator, key);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dkeys_{d} _keys_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.values()
/// Returns list of values
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Infer dict type to get value type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType{ .int = .bounded };

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that builds list of values
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(dvals_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _values_list = std.ArrayListUnmanaged(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    try self.emitIndent();
    try self.emit("for (");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".values()) |val| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("try _values_list.append(__global_allocator, val);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dvals_{d} _values_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Infer dict type to get value type (keys are always []const u8)
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType{ .int = .bounded };

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that builds list of tuples
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(ditems_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _items_list = std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("})){};\n");

    try self.emitIndent();
    try self.emit("var _iter = ");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const _tuple = std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("}){entry.key_ptr.*, entry.value_ptr.*};\n");

    try self.emitIndent();
    try self.emit("try _items_list.append(__global_allocator, _tuple);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ditems_{d} _items_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

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

/// Generate code for dict.pop(key, default?)
/// Removes key and returns value, or returns default if key not present
/// Raises KeyError if key not present and no default given
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const default_val = if (args.len >= 2) args[1] else null;

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block: { const val = dict.fetchSwapRemove(key); if (val) |v| v.value else default/error }
    try self.output.writer(self.allocator).print("(dpop_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const __kv = ");
    try emitObjExpr(self, obj);
    try self.emit(".fetchSwapRemove(");
    try self.genExpr(args[0]);
    try self.emit(");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpop_{d} if (__kv) |kv| kv.value else ", .{label_id});
    if (default_val) |def| {
        try self.genExpr(def);
    } else {
        try self.emit("return error.KeyError");
    }
    try self.emit(";\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.update(other)
/// Updates dict with key/value pairs from other dict or iterable of pairs
pub fn genUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that iterates and updates
    try self.output.writer(self.allocator).print("(dupdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store target dict as mutable pointer to enable put()
    try self.emitIndent();
    try self.emit("var __target_dict = &");
    try self.genExpr(obj);
    try self.emit(";\n");

    // Assign to temp variable first to avoid block expression syntax issues
    try self.emitIndent();
    try self.emit("const __other_dict = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("var __other_iter = __other_dict.iterator();\n");

    try self.emitIndent();
    try self.emit("while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    // Use the mutable pointer we stored above
    try self.emit("try __target_dict.put(entry.key_ptr.*, entry.value_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dupdate_{d} {{}};\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.clear()
/// Removes all items from dict
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitObjExpr(self, obj);
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for dict.copy()
/// Returns shallow copy of dict
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that clones the dict
    try self.output.writer(self.allocator).print("(dcopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store source dict in temp var to avoid block expression issues
    try self.emitIndent();
    try self.emit("const __src_dict = ");
    try self.genExpr(obj);
    try self.emit(";\n");

    // ArrayHashMap needs .init(allocator), not {}
    try self.emitIndent();
    try self.emit("var __copy = @TypeOf(__src_dict).init(__global_allocator);\n");

    try self.emitIndent();
    try self.emit("var __iter = __src_dict.iterator();\n");

    try self.emitIndent();
    try self.emit("while (__iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    // ArrayHashMap.put() doesn't take allocator - it uses the one stored internally
    try self.emit("try __copy.put(entry.key_ptr.*, entry.value_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dcopy_{d} __copy;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.setdefault(key, default?)
/// Returns value for key if present, otherwise sets key to default and returns it
pub fn genSetdefault(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block: if dict.get(key) return it, else put default and return
    try self.output.writer(self.allocator).print("(dsetdef_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const __existing = ");
    try emitObjExpr(self, obj);
    try self.emit(".get(");
    try self.genExpr(args[0]);
    try self.emit(");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (__existing) |v| break :dsetdef_{d} v;\n", .{label_id});

    try self.emitIndent();
    try self.emit("const __default = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("null");
    }
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("try ");
    try emitObjExpr(self, obj);
    // ArrayHashMap.put() doesn't take allocator
    try self.emit(".put(");
    try self.genExpr(args[0]);
    try self.emit(", __default);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dsetdef_{d} __default;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.popitem()
/// Removes and returns arbitrary (key, value) pair. Raises KeyError if empty.
pub fn genPopitem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that pops arbitrary item
    try self.output.writer(self.allocator).print("(dpopitem_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store dict in temp var to avoid block expression issues
    try self.emitIndent();
    try self.emit("const __dict_ptr = &");
    try self.genExpr(obj);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("var __iter = __dict_ptr.iterator();\n");

    try self.emitIndent();
    try self.emit("const __entry = __iter.next() orelse return error.KeyError;\n");

    try self.emitIndent();
    try self.emit("const __key = __entry.key_ptr.*;\n");

    try self.emitIndent();
    try self.emit("const __val = __entry.value_ptr.*;\n");

    try self.emitIndent();
    try self.emit("_ = __dict_ptr.fetchSwapRemove(__key);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpopitem_{d} .{{ __key, __val }};\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}
