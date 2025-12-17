/// Python fnmatch module - Unix filename pattern matching
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fnmatch", genFnmatch }, .{ "fnmatchcase", genFnmatch }, .{ "filter", genFilter }, .{ "translate", genTranslate },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genFnmatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("false"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_fnm: {{ const _name = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _pattern = "); try self.genExpr(args[1]);
    try self.emitFmt("; var pi: usize = 0; var ni: usize = 0; var star_pi: ?usize = null; var star_ni: usize = 0; while (ni < _name.len or pi < _pattern.len) {{ if (pi < _pattern.len) {{ const pc = _pattern[pi]; if (pc == '*') {{ star_pi = pi; star_ni = ni; pi += 1; continue; }} if (ni < _name.len) {{ const nc = _name[ni]; if (pc == '?' or pc == nc) {{ pi += 1; ni += 1; continue; }} }} }} if (star_pi) |sp| {{ pi = sp + 1; star_ni += 1; ni = star_ni; if (ni <= _name.len) continue; }} break :__m{d}_fnm false; }} break :__m{d}_fnm true; }})", .{ id, id });
}

fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_][]const u8{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_flt: {{ const _names = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _pattern = "); try self.genExpr(args[1]);
    try self.emitFmt("; var _result: std.ArrayList([]const u8) = .{{}}; for (_names) |_fname| {{ var _match = true; var _pi: usize = 0; var _ni: usize = 0; var _star_pi: ?usize = null; var _star_ni: usize = 0; __m{d}_fm: while (_ni < _fname.len or _pi < _pattern.len) {{ if (_pi < _pattern.len) {{ const _pc = _pattern[_pi]; if (_pc == '*') {{ _star_pi = _pi; _star_ni = _ni; _pi += 1; continue; }} if (_ni < _fname.len and (_pc == '?' or _pc == _fname[_ni])) {{ _pi += 1; _ni += 1; continue; }} }} if (_star_pi) |_sp| {{ _pi = _sp + 1; _star_ni += 1; _ni = _star_ni; if (_ni <= _fname.len) continue; }} _match = false; break :__m{d}_fm; }} if (_match) _result.append(__global_allocator, _fname) catch unreachable; }} break :__m{d}_flt _result.items; }})", .{ id, id, id });
}

fn genTranslate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_tr: {{ const _pattern = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; _result.appendSlice(__global_allocator, \"(?s:\") catch unreachable; for (_pattern) |c| {{ switch (c) {{ '*' => _result.appendSlice(__global_allocator, \".*\") catch unreachable, '?' => _result.append(__global_allocator, '.') catch unreachable, '.' => _result.appendSlice(__global_allocator, \"\\\\.\") catch unreachable, '[' => _result.append(__global_allocator, '[') catch unreachable, ']' => _result.append(__global_allocator, ']') catch unreachable, '^' => _result.appendSlice(__global_allocator, \"\\\\^\") catch unreachable, '$' => _result.appendSlice(__global_allocator, \"\\\\$\") catch unreachable, else => _result.append(__global_allocator, c) catch unreachable }} }} _result.appendSlice(__global_allocator, \")\\\\Z\") catch unreachable; break :__m{d}_tr _result.items; }})", .{id});
}
