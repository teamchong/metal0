/// Dict methods - .get(), .keys(), .values(), .items()
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const NativeType = @import("../../../analysis/native_types.zig").NativeType;

/// Generate code for dict.get(key, default)
/// Returns value if key exists, otherwise returns default (or null if no default)
/// If no args, generates generic method call (for custom class methods)
pub fn genGet(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // Not a dict.get() - must be custom class method with no args
        // Generate generic method call: obj.get()
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get()");
        return;
    }

    const default_val = if (args.len >= 2) args[1] else null;

    if (default_val) |def| {
        // Generate: dict.get(key) orelse default
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ") orelse ");
        try self.genExpr(def);
    } else {
        // Generate: dict.get(key)
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")");
    }
}

/// Generate code for dict.keys()
/// Returns list of keys (always []const u8 for StringHashMap)
pub fn genKeys(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // keys() takes no arguments

    // Generate block that builds list of keys
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _keys_list = std.ArrayList([]const u8){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".keyIterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |key_ptr| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _keys_list.append(allocator, key_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _keys_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for dict.values()
/// Returns list of values
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Infer dict type to get value type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    // Generate block that builds list of values
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _values_list = std.ArrayList(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".valueIterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |val_ptr| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _values_list.append(allocator, val_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _values_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Infer dict type to get value type (keys are always []const u8)
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    // Generate block that builds list of tuples
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _items_list = std.ArrayList(std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "})){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".iterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _tuple = std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "}){entry.key_ptr.*, entry.value_ptr.*};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _items_list.append(allocator, _tuple);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _items_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}
