/// String formatting methods - lstrip(), rstrip(), capitalize(), title(), etc.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for text.lstrip()
/// Removes leading whitespace
pub fn genLstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.emitFmt("lstrip_{d}: {{\n", .{label_id});
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _trimmed = std.mem.trimLeft(u8, _text, \" \\t\\n\\r\");\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, _trimmed.len);\n");
    try self.emit("    @memcpy(_result, _trimmed);\n");
    try self.emitFmt("    break :lstrip_{d} _result;\n", .{label_id});
    try self.emit("}");
}

/// Generate code for text.rstrip()
/// Removes trailing whitespace
pub fn genRstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.emitFmt("rstrip_{d}: {{\n", .{label_id});
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _trimmed = std.mem.trimRight(u8, _text, \" \\t\\n\\r\");\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, _trimmed.len);\n");
    try self.emit("    @memcpy(_result, _trimmed);\n");
    try self.emitFmt("    break :rstrip_{d} _result;\n", .{label_id});
    try self.emit("}");
}

/// Generate code for text.capitalize()
/// First char upper, rest lower
pub fn genCapitalize(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    _result[0] = std.ascii.toUpper(_text[0]);\n");
    try self.emit("    for (_text[1..], 0..) |_c, _idx| {\n");
    try self.emit("        _result[_idx + 1] = std.ascii.toLower(_c);\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.title()
/// Titlecase each word
pub fn genTitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    var _prev_space = true;\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        if (_prev_space and std.ascii.isAlphabetic(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toUpper(_c);\n");
    try self.emit("        } else {\n");
    try self.emit("            _result[_idx] = std.ascii.toLower(_c);\n");
    try self.emit("        }\n");
    try self.emit("        _prev_space = !std.ascii.isAlphanumeric(_c);\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.swapcase()
/// Swap upper/lower
pub fn genSwapcase(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        if (std.ascii.isUpper(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toLower(_c);\n");
    try self.emit("        } else if (std.ascii.isLower(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toUpper(_c);\n");
    try self.emit("        } else {\n");
    try self.emit("            _result[_idx] = _c;\n");
    try self.emit("        }\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.index(sub)
/// Like find() but returns -1 if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rfind(sub)
/// Find from right
pub fn genRfind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rindex(sub)
/// Like rfind() but returns -1 if not found
pub fn genRindex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.ljust(width)
/// Left justify with spaces
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, @intCast(_width));\n");
    try self.emit("    @memcpy(_result[0.._text.len], _text);\n");
    try self.emit("    @memset(_result[_text.len..], ' ');\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.rjust(width)
/// Right justify with spaces
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, @intCast(_width));\n");
    try self.emit("    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.emit("    @memset(_result[0.._pad], ' ');\n");
    try self.emit("    @memcpy(_result[_pad..], _text);\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.center(width)
/// Center with spaces
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, @intCast(_width));\n");
    try self.emit("    const _total_pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.emit("    const _left_pad = _total_pad / 2;\n");
    try self.emit("    @memset(_result[0.._left_pad], ' ');\n");
    try self.emit("    @memcpy(_result[_left_pad.._left_pad + _text.len], _text);\n");
    try self.emit("    @memset(_result[_left_pad + _text.len..], ' ');\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.zfill(width)
/// Pad with zeros on left
pub fn genZfill(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = __global_allocator.alloc(u8, @intCast(_width));\n");
    try self.emit("    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.emit("    @memset(_result[0.._pad], '0');\n");
    try self.emit("    @memcpy(_result[_pad..], _text);\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}
