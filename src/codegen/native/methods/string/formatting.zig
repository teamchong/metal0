/// String formatting methods - lstrip(), rstrip(), capitalize(), title(), etc.
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Check if a string expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain strings to PyValue extraction via .asString()
fn isStringUncertain(self: *NativeCodegen, obj: ast.Node) bool {
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
        return false;
    }
    return false;
}

/// Helper to emit string expression, extracting from PyValue if uncertain
fn emitStringExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (isStringUncertain(self, obj)) {
        // Extract string from PyValue using .asString()
        try self.genExpr(obj);
        try self.emit(".asString()");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for text.lstrip()
/// Removes leading whitespace
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genLstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_lstrip: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emit("    const _trimmed = std.mem.trimLeft(u8, _text, \" \\t\\n\\r\");\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _trimmed.len);\n");
    try self.emit("    @memcpy(_result, _trimmed);\n");
    try self.emitFmt("    break :__m{d}_lstrip _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.rstrip()
/// Removes trailing whitespace
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_rstrip: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emit("    const _trimmed = std.mem.trimRight(u8, _text, \" \\t\\n\\r\");\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _trimmed.len);\n");
    try self.emit("    @memcpy(_result, _trimmed);\n");
    try self.emitFmt("    break :__m{d}_rstrip _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.capitalize()
/// First char upper, rest lower
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genCapitalize(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_capitalize: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emitFmt("    if (_text.len == 0) break :__m{d}_capitalize _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    _result[0] = std.ascii.toUpper(_text[0]);\n");
    try self.emit("    for (_text[1..], 0..) |_c, _idx| {\n");
    try self.emit("        _result[_idx + 1] = std.ascii.toLower(_c);\n");
    try self.emit("    }\n");
    try self.emitFmt("    break :__m{d}_capitalize _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.title()
/// Titlecase each word
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genTitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_title: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emitFmt("    if (_text.len == 0) break :__m{d}_title _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    var _prev_space = true;\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        if (_prev_space and std.ascii.isAlphabetic(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toUpper(_c);\n");
    try self.emit("        } else {\n");
    try self.emit("            _result[_idx] = std.ascii.toLower(_c);\n");
    try self.emit("        }\n");
    try self.emit("        _prev_space = !std.ascii.isAlphanumeric(_c);\n");
    try self.emit("    }\n");
    try self.emitFmt("    break :__m{d}_title _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.swapcase()
/// Swap upper/lower
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genSwapcase(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_swapcase: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        if (std.ascii.isUpper(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toLower(_c);\n");
    try self.emit("        } else if (std.ascii.isLower(_c)) {\n");
    try self.emit("            _result[_idx] = std.ascii.toUpper(_c);\n");
    try self.emit("        } else {\n");
    try self.emit("            _result[_idx] = _c;\n");
    try self.emit("        }\n");
    try self.emit("    }\n");
    try self.emitFmt("    break :__m{d}_swapcase _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.index(sub[, start[, end]])
/// Like find() but raises ValueError if not found (we return -1 for now)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.index() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        try self.emit("if (std.mem.indexOf(u8, ");
        try emitStringExpr(self, obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_index: {{\n", .{id});
        try self.emit("    const __idx_text = ");
        try emitStringExpr(self, obj);
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
        try self.emitFmt("    if (__idx_start >= __idx_end) break :__m{d}_index @as(i64, -1);\n", .{id});
        try self.emit("    const __idx_slice = __idx_text[__idx_start..__idx_end];\n");
        try self.emitFmt("    break :__m{d}_index if (std.mem.indexOf(u8, __idx_slice, __idx_sub)) |idx| @as(i64, @intCast(idx + __idx_start)) else -1;\n", .{id});
        try self.emit("}");
    }
}

/// Generate code for text.rfind(sub[, start[, end]])
/// Find from right
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRfind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.rfind() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        // Wrap in parens so it's a valid expression in any context
        try self.emit("(if (std.mem.lastIndexOf(u8, ");
        try emitStringExpr(self, obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1)");
    } else {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_rfind: {{\n", .{id});
        try self.emit("    const __rfind_text = ");
        try emitStringExpr(self, obj);
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
        try self.emitFmt("    if (__rfind_start >= __rfind_end) break :__m{d}_rfind @as(i64, -1);\n", .{id});
        try self.emit("    const __rfind_slice = __rfind_text[__rfind_start..__rfind_end];\n");
        try self.emitFmt("    break :__m{d}_rfind if (std.mem.lastIndexOf(u8, __rfind_slice, __rfind_sub)) |idx| @as(i64, @intCast(idx + __rfind_start)) else -1;\n", .{id});
        try self.emit("}");
    }
}

/// Generate code for text.rindex(sub[, start[, end]])
/// Like rfind() but raises ValueError if not found (we return -1 for now)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRindex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.rindex() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        // Wrap in parens so it's a valid expression in any context
        try self.emit("(if (std.mem.lastIndexOf(u8, ");
        try emitStringExpr(self, obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1)");
    } else {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_rindex: {{\n", .{id});
        try self.emit("    const __ridx_text = ");
        try emitStringExpr(self, obj);
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
        try self.emitFmt("    if (__ridx_start >= __ridx_end) break :__m{d}_rindex @as(i64, -1);\n", .{id});
        try self.emit("    const __ridx_slice = __ridx_text[__ridx_start..__ridx_end];\n");
        try self.emitFmt("    break :__m{d}_rindex if (std.mem.lastIndexOf(u8, __ridx_slice, __ridx_sub)) |idx| @as(i64, @intCast(idx + __ridx_start)) else -1;\n", .{id});
        try self.emit("}");
    }
}

/// Generate code for text.ljust(width[, fillchar])
/// Left justify with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.ljust() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_ljust: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
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

    try self.emitFmt("    if (_text.len >= _width) break :__m{d}_ljust _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    @memcpy(_result[0.._text.len], _text);\n");
    try self.emit("    @memset(_result[_text.len..], _fill);\n");
    try self.emitFmt("    break :__m{d}_ljust _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.rjust(width[, fillchar])
/// Right justify with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.rjust() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_rjust: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
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

    try self.emitFmt("    if (_text.len >= _width) break :__m{d}_rjust _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    const _pad = _width - _text.len;\n");
    try self.emit("    @memset(_result[0.._pad], _fill);\n");
    try self.emit("    @memcpy(_result[_pad..], _text);\n");
    try self.emitFmt("    break :__m{d}_rjust _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.center(width[, fillchar])
/// Center with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.center() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_center: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
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

    try self.emitFmt("    if (_text.len >= _width) break :__m{d}_center _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, _width);\n");
    try self.emit("    const _total_pad = _width - _text.len;\n");
    try self.emit("    const _left_pad = _total_pad / 2;\n");
    try self.emit("    @memset(_result[0.._left_pad], _fill);\n");
    try self.emit("    @memcpy(_result[_left_pad.._left_pad + _text.len], _text);\n");
    try self.emit("    @memset(_result[_left_pad + _text.len..], _fill);\n");
    try self.emitFmt("    break :__m{d}_center _result;\n", .{id});
    try self.emit("}");
}

/// Generate code for text.zfill(width)
/// Pad with zeros on left
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genZfill(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.zfill() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    const id = self.nextNameId();
    try self.emitFmt("__m{d}_zfill: {{\n", .{id});
    try self.emit("    const _text = ");
    try emitStringExpr(self, obj);
    try self.emit(";\n");
    try self.emit("    const _width = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitFmt("    if (_text.len >= _width) break :__m{d}_zfill _text;\n", .{id});
    try self.emit("    const _result = try __global_allocator.alloc(u8, @intCast(_width));\n");
    try self.emit("    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.emit("    @memset(_result[0.._pad], '0');\n");
    try self.emit("    @memcpy(_result[_pad..], _text);\n");
    try self.emitFmt("    break :__m{d}_zfill _result;\n", .{id});
    try self.emit("}");
}
