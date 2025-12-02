/// Python textwrap module - text wrapping and filling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "wrap", genWrap }, .{ "fill", genFill }, .{ "dedent", genDedent },
    .{ "indent", genIndent }, .{ "shorten", genShorten }, .{ "TextWrapper", genTextWrapper },
});

fn genWidth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("; const _width: usize = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); }
    else { try self.emit("70"); }
}

fn genWrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _text = "); try self.genExpr(args[0]); try genWidth(self, args);
    try self.emit("; var _lines = std.ArrayList([]const u8){}; var _start: usize = 0; while (_start < _text.len) { const _end = @min(_start + _width, _text.len); _lines.append(__global_allocator, _text[_start.._end]) catch continue; _start = _end; } break :blk _lines.items; }");
}

fn genFill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _text = "); try self.genExpr(args[0]); try genWidth(self, args);
    try self.emit("; var _result = std.ArrayList(u8){}; var _start: usize = 0; while (_start < _text.len) { const _end = @min(_start + _width, _text.len); if (_start > 0) _result.append(__global_allocator, '\\n') catch continue; _result.appendSlice(__global_allocator, _text[_start.._end]) catch continue; _start = _end; } break :blk _result.items; }");
}

fn genDedent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _text = "); try self.genExpr(args[0]);
    try self.emit("; var _min_indent: usize = std.math.maxInt(usize); var _lines_iter = std.mem.splitSequence(u8, _text, \"\\n\"); while (_lines_iter.next()) |line| { if (line.len == 0) continue; var _spaces: usize = 0; for (line) |c| { if (c == ' ') _spaces += 1 else break; } if (_spaces < _min_indent) _min_indent = _spaces; } if (_min_indent == std.math.maxInt(usize)) _min_indent = 0; var _result = std.ArrayList(u8){}; var _lines_iter2 = std.mem.splitSequence(u8, _text, \"\\n\"); var _first = true; while (_lines_iter2.next()) |line| { if (!_first) _result.append(__global_allocator, '\\n') catch continue; _first = false; if (line.len > _min_indent) _result.appendSlice(__global_allocator, line[_min_indent..]) catch continue; } break :blk _result.items; }");
}

fn genIndent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _text = "); try self.genExpr(args[0]); try self.emit("; const _prefix = "); try self.genExpr(args[1]);
    try self.emit("; var _result = std.ArrayList(u8){}; var _lines_iter = std.mem.splitSequence(u8, _text, \"\\n\"); var _first = true; while (_lines_iter.next()) |line| { if (!_first) _result.append(__global_allocator, '\\n') catch continue; _first = false; _result.appendSlice(__global_allocator, _prefix) catch continue; _result.appendSlice(__global_allocator, line) catch continue; } break :blk _result.items; }");
}

fn genShorten(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _text = "); try self.genExpr(args[0]); try self.emit("; const _width: usize = @intCast("); try self.genExpr(args[1]);
    try self.emit("); if (_text.len <= _width) break :blk _text; if (_width <= 3) break :blk \"...\"; var _result = __global_allocator.alloc(u8, _width) catch break :blk _text; @memcpy(_result[0.._width-3], _text[0.._width-3]); @memcpy(_result[_width-3..], \"...\"); break :blk _result; }");
}

fn genTextWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { width: usize = 70, initial_indent: []const u8 = \"\", subsequent_indent: []const u8 = \"\", pub fn wrap(__self: *@This(), text: []const u8) [][]const u8 { _ = __self; _ = text; return &.{}; } pub fn fill(__self: *@This(), text: []const u8) []const u8 { _ = __self; return text; } }{}");
}
