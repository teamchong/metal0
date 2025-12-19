/// String formatting methods - lstrip(), rstrip(), capitalize(), title(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


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
        try emitConst(self,".asString()");
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
    const label = try self.emitInlineBlockStart("lstrip");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _trimmed = std.mem.trimLeft(u8, _text, \" \\t\\n\\r\"); ");
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _trimmed.len); ");
    try emitConst(self,"@memcpy(_result, _trimmed); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.rstrip()
/// Removes trailing whitespace
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label = try self.emitInlineBlockStart("rstrip");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _trimmed = std.mem.trimRight(u8, _text, \" \\t\\n\\r\"); ");
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _trimmed.len); ");
    try emitConst(self,"@memcpy(_result, _trimmed); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.capitalize()
/// First char upper, rest lower
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genCapitalize(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = try self.emitInlineBlockStart("capitalize");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitFmtConst(self, "if (_text.len == 0) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _text.len); ");
    try emitConst(self,"_result[0] = std.ascii.toUpper(_text[0]); ");
    try emitConst(self,"for (_text[1..], 0..) |_c, _idx| { ");
    try emitConst(self,"_result[_idx + 1] = std.ascii.toLower(_c); ");
    try emitConst(self,"} ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.title()
/// Titlecase each word
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genTitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = try self.emitInlineBlockStart("title");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitFmtConst(self, "if (_text.len == 0) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _text.len); ");
    try emitConst(self,"var _prev_space = true; ");
    try emitConst(self,"for (_text, 0..) |_c, _idx| { ");
    try emitConst(self,"if (_prev_space and std.ascii.isAlphabetic(_c)) { ");
    try emitConst(self,"_result[_idx] = std.ascii.toUpper(_c); ");
    try emitConst(self,"} else { ");
    try emitConst(self,"_result[_idx] = std.ascii.toLower(_c); ");
    try emitConst(self,"} ");
    try emitConst(self,"_prev_space = !std.ascii.isAlphanumeric(_c); ");
    try emitConst(self,"} ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.swapcase()
/// Swap upper/lower
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genSwapcase(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = try self.emitInlineBlockStart("swapcase");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _text.len); ");
    try emitConst(self,"for (_text, 0..) |_c, _idx| { ");
    try emitConst(self,"if (std.ascii.isUpper(_c)) { ");
    try emitConst(self,"_result[_idx] = std.ascii.toLower(_c); ");
    try emitConst(self,"} else if (std.ascii.isLower(_c)) { ");
    try emitConst(self,"_result[_idx] = std.ascii.toUpper(_c); ");
    try emitConst(self,"} else { ");
    try emitConst(self,"_result[_idx] = _c; ");
    try emitConst(self,"} ");
    try emitConst(self,"} ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.index(sub[, start[, end]])
/// Like find() but raises ValueError if not found (we return -1 for now)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.index() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        try emitConst(self,"if (std.mem.indexOf(u8, ");
        try emitStringExpr(self, obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        const label = try self.emitInlineBlockStart("index");
        try emitConst(self,"const __idx_text = ");
        try emitStringExpr(self, obj);
        try emitConst(self,"; ");
        try emitConst(self,"const __idx_sub = ");
        try self.genExpr(args[0]);
        try emitConst(self,"; ");
        try emitConst(self,"const __idx_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,")); ");
        if (args.len >= 3) {
            try emitConst(self,"const __idx_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __idx_text.len); ");
        } else {
            try emitConst(self,"const __idx_end = __idx_text.len; ");
        }
        try emitFmtConst(self, "if (__idx_start >= __idx_end) break :{s} @as(i64, -1); ", .{label});
        try emitConst(self,"const __idx_slice = __idx_text[__idx_start..__idx_end]; ");
        try emitFmtConst(self, "break :{s} if (std.mem.indexOf(u8, __idx_slice, __idx_sub)) |idx| @as(i64, @intCast(idx + __idx_start)) else -1; ", .{label});
        try self.emitInlineBlockEnd();
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
        try emitConst(self,"(if (std.mem.lastIndexOf(u8, ");
        try emitStringExpr(self, obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")) |idx| @as(i64, @intCast(idx)) else -1)");
    } else {
        const label = try self.emitInlineBlockStart("rfind");
        try emitConst(self,"const __rfind_text = ");
        try emitStringExpr(self, obj);
        try emitConst(self,"; ");
        try emitConst(self,"const __rfind_sub = ");
        try self.genExpr(args[0]);
        try emitConst(self,"; ");
        try emitConst(self,"const __rfind_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,")); ");
        if (args.len >= 3) {
            try emitConst(self,"const __rfind_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __rfind_text.len); ");
        } else {
            try emitConst(self,"const __rfind_end = __rfind_text.len; ");
        }
        try emitFmtConst(self, "if (__rfind_start >= __rfind_end) break :{s} @as(i64, -1); ", .{label});
        try emitConst(self,"const __rfind_slice = __rfind_text[__rfind_start..__rfind_end]; ");
        try emitFmtConst(self, "break :{s} if (std.mem.lastIndexOf(u8, __rfind_slice, __rfind_sub)) |idx| @as(i64, @intCast(idx + __rfind_start)) else -1; ", .{label});
        try self.emitInlineBlockEnd();
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
        try emitConst(self,"(if (std.mem.lastIndexOf(u8, ");
        try emitStringExpr(self, obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")) |idx| @as(i64, @intCast(idx)) else -1)");
    } else {
        const label = try self.emitInlineBlockStart("rindex");
        try emitConst(self,"const __ridx_text = ");
        try emitStringExpr(self, obj);
        try emitConst(self,"; ");
        try emitConst(self,"const __ridx_sub = ");
        try self.genExpr(args[0]);
        try emitConst(self,"; ");
        try emitConst(self,"const __ridx_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,")); ");
        if (args.len >= 3) {
            try emitConst(self,"const __ridx_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __ridx_text.len); ");
        } else {
            try emitConst(self,"const __ridx_end = __ridx_text.len; ");
        }
        try emitFmtConst(self, "if (__ridx_start >= __ridx_end) break :{s} @as(i64, -1); ", .{label});
        try emitConst(self,"const __ridx_slice = __ridx_text[__ridx_start..__ridx_end]; ");
        try emitFmtConst(self, "break :{s} if (std.mem.lastIndexOf(u8, __ridx_slice, __ridx_sub)) |idx| @as(i64, @intCast(idx + __ridx_start)) else -1; ", .{label});
        try self.emitInlineBlockEnd();
    }
}

/// Generate code for text.ljust(width[, fillchar])
/// Left justify with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.ljust() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const label = try self.emitInlineBlockStart("ljust");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try emitConst(self,")); ");

    if (args.len >= 2) {
        try emitConst(self,"const _fill = ");
        try self.genExpr(args[1]);
        try emitConst(self,"[0]; ");
    } else {
        try emitConst(self,"const _fill: u8 = ' '; ");
    }

    try emitFmtConst(self, "if (_text.len >= _width) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _width); ");
    try emitConst(self,"@memcpy(_result[0.._text.len], _text); ");
    try emitConst(self,"@memset(_result[_text.len..], _fill); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.rjust(width[, fillchar])
/// Right justify with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.rjust() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const label = try self.emitInlineBlockStart("rjust");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try emitConst(self,")); ");

    if (args.len >= 2) {
        try emitConst(self,"const _fill = ");
        try self.genExpr(args[1]);
        try emitConst(self,"[0]; ");
    } else {
        try emitConst(self,"const _fill: u8 = ' '; ");
    }

    try emitFmtConst(self, "if (_text.len >= _width) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _width); ");
    try emitConst(self,"const _pad = _width - _text.len; ");
    try emitConst(self,"@memset(_result[0.._pad], _fill); ");
    try emitConst(self,"@memcpy(_result[_pad..], _text); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.center(width[, fillchar])
/// Center with spaces or fillchar
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.center() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    const label = try self.emitInlineBlockStart("center");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _width = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try emitConst(self,")); ");

    if (args.len >= 2) {
        try emitConst(self,"const _fill = ");
        try self.genExpr(args[1]);
        try emitConst(self,"[0]; ");
    } else {
        try emitConst(self,"const _fill: u8 = ' '; ");
    }

    try emitFmtConst(self, "if (_text.len >= _width) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, _width); ");
    try emitConst(self,"const _total_pad = _width - _text.len; ");
    try emitConst(self,"const _left_pad = _total_pad / 2; ");
    try emitConst(self,"@memset(_result[0.._left_pad], _fill); ");
    try emitConst(self,"@memcpy(_result[_left_pad.._left_pad + _text.len], _text); ");
    try emitConst(self,"@memset(_result[_left_pad + _text.len..], _fill); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for text.zfill(width)
/// Pad with zeros on left
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genZfill(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.zfill() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    const label = try self.emitInlineBlockStart("zfill");
    try emitConst(self,"const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,"; ");
    try emitConst(self,"const _width = ");
    try self.genExpr(args[0]);
    try emitConst(self,"; ");
    try emitFmtConst(self, "if (_text.len >= _width) break :{s} _text; ", .{label});
    try emitConst(self,"const _result = try __global_allocator.alloc(u8, @intCast(_width)); ");
    try emitConst(self,"const _pad = @as(usize, @intCast(_width)) - _text.len; ");
    try emitConst(self,"@memset(_result[0.._pad], '0'); ");
    try emitConst(self,"@memcpy(_result[_pad..], _text); ");
    try emitFmtConst(self, "break :{s} _result; ", .{label});
    try self.emitInlineBlockEnd();
}
