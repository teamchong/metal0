/// Python fnmatch module - Unix filename pattern matching
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fnmatch", genFnmatch }, .{ "fnmatchcase", genFnmatch }, .{ "filter", genFilter }, .{ "translate", genTranslate },
});

const GlobMatchCore = "; var pi: usize = 0; var ni: usize = 0; var star_pi: ?usize = null; var star_ni: usize = 0; while (ni < _name.len or pi < _pattern.len) { if (pi < _pattern.len) { const pc = _pattern[pi]; if (pc == '*') { star_pi = pi; star_ni = ni; pi += 1; continue; } if (ni < _name.len) { const nc = _name[ni]; if (pc == '?' or pc == nc) { pi += 1; ni += 1; continue; } } } if (star_pi) |sp| { pi = sp + 1; star_ni += 1; ni = star_ni; if (ni <= _name.len) continue; } break :blk false; } break :blk true; }";

fn genFnmatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _name = "); try self.genExpr(args[0]); try self.emit("; const _pattern = "); try self.genExpr(args[1]);
    try self.emit(GlobMatchCore);
}

fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _names = "); try self.genExpr(args[0]); try self.emit("; const _pattern = "); try self.genExpr(args[1]);
    try self.emit("; var _result: std.ArrayList([]const u8) = .{}; for (_names) |_fname| { var _match = true; var _pi: usize = 0; var _ni: usize = 0; var _star_pi: ?usize = null; var _star_ni: usize = 0; filter_match: while (_ni < _fname.len or _pi < _pattern.len) { if (_pi < _pattern.len) { const _pc = _pattern[_pi]; if (_pc == '*') { _star_pi = _pi; _star_ni = _ni; _pi += 1; continue; } if (_ni < _fname.len and (_pc == '?' or _pc == _fname[_ni])) { _pi += 1; _ni += 1; continue; } } if (_star_pi) |_sp| { _pi = _sp + 1; _star_ni += 1; _ni = _star_ni; if (_ni <= _fname.len) continue; } _match = false; break :filter_match; } if (_match) _result.append(__global_allocator, _fname) catch {}; } break :blk _result.items; }");
}

fn genTranslate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _pattern = "); try self.genExpr(args[0]);
    try self.emit("; var _result: std.ArrayList(u8) = .{}; _result.appendSlice(__global_allocator, \"(?s:\") catch {}; for (_pattern) |c| { switch (c) { '*' => _result.appendSlice(__global_allocator, \".*\") catch {}, '?' => _result.append(__global_allocator, '.') catch {}, '.' => _result.appendSlice(__global_allocator, \"\\\\.\") catch {}, '[' => _result.append(__global_allocator, '[') catch {}, ']' => _result.append(__global_allocator, ']') catch {}, '^' => _result.appendSlice(__global_allocator, \"\\\\^\") catch {}, '$' => _result.appendSlice(__global_allocator, \"\\\\$\") catch {}, else => _result.append(__global_allocator, c) catch {} } } _result.appendSlice(__global_allocator, \")\\\\Z\") catch {}; break :blk _result.items; }");
}
