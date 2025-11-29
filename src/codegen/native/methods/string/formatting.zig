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

/// Generate code for text.index(sub[, start[, end]])
/// Like find() but raises ValueError if not found (we return -1 for now)
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        try self.emit("if (std.mem.indexOf(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        try self.emit("blk: {\n");
        try self.emit("    const __idx_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __idx_sub = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __idx_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");
        if (args.len >= 3) {
            try self.emit("    const __idx_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __idx_text.len);\n");
        } else {
            try self.emit("    const __idx_end = __idx_text.len;\n");
        }
        try self.emit("    if (__idx_start >= __idx_end) break :blk @as(i64, -1);\n");
        try self.emit("    const __idx_slice = __idx_text[__idx_start..__idx_end];\n");
        try self.emit("    break :blk if (std.mem.indexOf(u8, __idx_slice, __idx_sub)) |idx| @as(i64, @intCast(idx + __idx_start)) else -1;\n");
        try self.emit("}");
    }
}

/// Generate code for text.rfind(sub[, start[, end]])
/// Find from right
pub fn genRfind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        try self.emit("if (std.mem.lastIndexOf(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        try self.emit("blk: {\n");
        try self.emit("    const __rfind_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __rfind_sub = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __rfind_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");
        if (args.len >= 3) {
            try self.emit("    const __rfind_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __rfind_text.len);\n");
        } else {
            try self.emit("    const __rfind_end = __rfind_text.len;\n");
        }
        try self.emit("    if (__rfind_start >= __rfind_end) break :blk @as(i64, -1);\n");
        try self.emit("    const __rfind_slice = __rfind_text[__rfind_start..__rfind_end];\n");
        try self.emit("    break :blk if (std.mem.lastIndexOf(u8, __rfind_slice, __rfind_sub)) |idx| @as(i64, @intCast(idx + __rfind_start)) else -1;\n");
        try self.emit("}");
    }
}

/// Generate code for text.rindex(sub[, start[, end]])
/// Like rfind() but raises ValueError if not found (we return -1 for now)
pub fn genRindex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        try self.emit("if (std.mem.lastIndexOf(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        try self.emit("blk: {\n");
        try self.emit("    const __ridx_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __ridx_sub = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __ridx_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");
        if (args.len >= 3) {
            try self.emit("    const __ridx_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __ridx_text.len);\n");
        } else {
            try self.emit("    const __ridx_end = __ridx_text.len;\n");
        }
        try self.emit("    if (__ridx_start >= __ridx_end) break :blk @as(i64, -1);\n");
        try self.emit("    const __ridx_slice = __ridx_text[__ridx_start..__ridx_end];\n");
        try self.emit("    break :blk if (std.mem.lastIndexOf(u8, __ridx_slice, __ridx_sub)) |idx| @as(i64, @intCast(idx + __ridx_start)) else -1;\n");
        try self.emit("}");
    }
}

/// Generate code for text.ljust(width[, fillchar])
/// Left justify with spaces or fillchar
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("));\n");

    if (args.len >= 2) {
        try self.emit("    const _fill = ");
        try self.genExpr(args[1]);
        try self.emit("[0];\n");
    } else {
        try self.emit("    const _fill: u8 = ' ';\n");
    }

    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    @memcpy(_result[0.._text.len], _text);\n");
    try self.emit("    @memset(_result[_text.len..], _fill);\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.rjust(width[, fillchar])
/// Right justify with spaces or fillchar
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("));\n");

    if (args.len >= 2) {
        try self.emit("    const _fill = ");
        try self.genExpr(args[1]);
        try self.emit("[0];\n");
    } else {
        try self.emit("    const _fill: u8 = ' ';\n");
    }

    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    const _pad = _width - _text.len;\n");
    try self.emit("    @memset(_result[0.._pad], _fill);\n");
    try self.emit("    @memcpy(_result[_pad..], _text);\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.center(width[, fillchar])
/// Center with spaces or fillchar
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("));\n");

    if (args.len >= 2) {
        try self.emit("    const _fill = ");
        try self.genExpr(args[1]);
        try self.emit("[0];\n");
    } else {
        try self.emit("    const _fill: u8 = ' ';\n");
    }

    try self.emit("    if (_text.len >= _width) break :blk _text;\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    const _total_pad = _width - _text.len;\n");
    try self.emit("    const _left_pad = _total_pad / 2;\n");
    try self.emit("    @memset(_result[0.._left_pad], _fill);\n");
    try self.emit("    @memcpy(_result[_left_pad.._left_pad + _text.len], _text);\n");
    try self.emit("    @memset(_result[_left_pad + _text.len..], _fill);\n");
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
