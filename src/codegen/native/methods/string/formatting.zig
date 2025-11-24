/// String formatting methods - lstrip(), rstrip(), capitalize(), title(), etc.
const std = @import("std");
const ast = @import("../../../../ast.zig");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for text.lstrip()
/// Removes leading whitespace
pub fn genLstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.output.writer(self.allocator).print("lstrip_{d}: {{\n", .{label_id});
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _trimmed = std.mem.trimLeft(u8, _text, \" \\t\\n\\r\");\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _trimmed.len);\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result, _trimmed);\n");
    try self.output.writer(self.allocator).print("    break :lstrip_{d} _result;\n", .{label_id});
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.rstrip()
/// Removes trailing whitespace
pub fn genRstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.output.writer(self.allocator).print("rstrip_{d}: {{\n", .{label_id});
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _trimmed = std.mem.trimRight(u8, _text, \" \\t\\n\\r\");\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _trimmed.len);\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result, _trimmed);\n");
    try self.output.writer(self.allocator).print("    break :rstrip_{d} _result;\n", .{label_id});
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.capitalize()
/// First char upper, rest lower
pub fn genCapitalize(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    _result[0] = std.ascii.toUpper(_text[0]);\n");
    try self.output.appendSlice(self.allocator, "    for (_text[1..], 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i + 1] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.title()
/// Titlecase each word
pub fn genTitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    var _prev_space = true;\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        if (_prev_space and std.ascii.isAlphabetic(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "        _prev_space = !std.ascii.isAlphanumeric(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.swapcase()
/// Swap upper/lower
pub fn genSwapcase(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isUpper(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "        } else if (std.ascii.isLower(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = c;\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.index(sub)
/// Like find() but returns -1 if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rfind(sub)
/// Find from right
pub fn genRfind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rindex(sub)
/// Like rfind() but returns -1 if not found
pub fn genRindex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.ljust(width)
/// Left justify with spaces
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[0.._text.len], _text);\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[_text.len..], ' ');\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.rjust(width)
/// Right justify with spaces
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._pad], ' ');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_pad..], _text);\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.center(width)
/// Center with spaces
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _total_pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    const _left_pad = _total_pad / 2;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._left_pad], ' ');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_left_pad.._left_pad + _text.len], _text);\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[_left_pad + _text.len..], ' ');\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.zfill(width)
/// Pad with zeros on left
pub fn genZfill(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._pad], '0');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_pad..], _text);\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}
