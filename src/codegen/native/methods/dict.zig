/// Dict methods - .get(), .keys(), .values(), .items()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const NativeType = @import("../../../analysis/native_types.zig").NativeType;

/// Check if an expression produces a Zig block/struct expression that can't have methods called directly
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true,
        .list => true,
        .dict => true,
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true, // dict() or other constructor calls
        else => false,
    };
}

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
        const label_id = self.block_label_counter;
        self.block_label_counter += 1;
        try self.output.writer(self.allocator).print("dget_{d}: {{\n", .{label_id});
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
        try self.emit("}");
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
    try self.output.writer(self.allocator).print("dkeys_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _keys_list = std.ArrayList([]const u8){};\n");

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
    try self.emit("}");
}

/// Generate code for dict.values()
/// Returns list of values
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Infer dict type to get value type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that builds list of values
    try self.output.writer(self.allocator).print("dvals_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _values_list = std.ArrayList(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    try self.emitIndent();
    try self.emit("var _iter = ");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".valueIterator();\n");

    try self.emitIndent();
    try self.emit("while (_iter.next()) |val_ptr| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("try _values_list.append(__global_allocator, val_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dvals_{d} _values_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Infer dict type to get value type (keys are always []const u8)
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate block that builds list of tuples
    try self.output.writer(self.allocator).print("ditems_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _items_list = std.ArrayList(std.meta.Tuple(&[_]type{[]const u8, ");
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
    try self.emit("}");
}
