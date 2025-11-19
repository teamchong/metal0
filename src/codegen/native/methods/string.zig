/// String methods - .split(), .upper(), .lower(), .strip(), etc.
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for text.split(separator)
/// Example: "a b c".split(" ") -> ArrayList([]const u8)
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate block expression that returns ArrayList([]const u8)
    // Keep as ArrayList to match type inference (.list type)
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    var _split_result = std.ArrayList([]const u8){};\n");
    try self.output.appendSlice(self.allocator, "    var _split_iter = std.mem.splitSequence(u8, ");
    try self.genExpr(obj); // The string to split
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The separator
    try self.output.appendSlice(self.allocator, ");\n");
    try self.output.appendSlice(self.allocator, "    while (_split_iter.next()) |part| {\n");
    try self.output.appendSlice(self.allocator, "        try _split_result.append(allocator, part);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _split_result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.upper()
/// Converts string to uppercase
pub fn genUpper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.lower()
/// Converts string to lowercase
pub fn genLower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.strip()
/// Removes leading/trailing whitespace
pub fn genStrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // strip() takes no arguments

    // Generate: std.mem.trim(u8, text, " \t\n\r")
    try self.output.appendSlice(self.allocator, "std.mem.trim(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", \" \\t\\n\\r\")");
}

/// Generate code for text.replace(old, new)
/// Replaces all occurrences of old with new
pub fn genReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        return;
    }

    // Generate: try std.mem.replaceOwned(u8, allocator, text, old, new)
    try self.output.appendSlice(self.allocator, "try std.mem.replaceOwned(u8, allocator, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // old
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]); // new
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for sep.join(list)
/// Joins list elements with separator
pub fn genJoin(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.join(allocator, separator, list)
    try self.output.appendSlice(self.allocator, "std.mem.join(allocator, ");
    try self.genExpr(obj); // The separator string
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The list
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.startswith(prefix)
/// Checks if string starts with prefix
pub fn genStartswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.startsWith(u8, text, prefix)
    try self.output.appendSlice(self.allocator, "std.mem.startsWith(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.endswith(suffix)
/// Checks if string ends with suffix
pub fn genEndswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.endsWith(u8, text, suffix)
    try self.output.appendSlice(self.allocator, "std.mem.endsWith(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.find(substring)
/// Returns index of first occurrence, or -1 if not found
pub fn genFind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: if (std.mem.indexOf(u8, text, substring)) |idx| @as(i64, @intCast(idx)) else -1
    try self.output.appendSlice(self.allocator, "if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.count(substring)
/// Counts non-overlapping occurrences
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // For now: compile error - needs loop implementation
    // TODO: Generate loop to count occurrences
    _ = obj;
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"text.count() requires loop codegen, not yet supported\")",
    );
}
