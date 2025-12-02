/// Python bisect module - Array bisection algorithms
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", genBisectLeft }, .{ "bisect_right", genBisectRight }, .{ "bisect", genBisectRight },
    .{ "insort_left", genInsortLeft }, .{ "insort_right", genInsortRight }, .{ "insort", genInsortRight },
});

const ArraySetup = "; const _a = if (@typeInfo(@TypeOf(_a_raw)) == .@\"struct\" and @hasField(@TypeOf(_a_raw), \"items\")) _a_raw.items else &_a_raw; const _x = ";
const BisectLoop = "; var _lo: usize = 0; var _hi: usize = _a.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2;";

fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(usize, 0)"); return; }
    try self.emit("blk: { const _a_raw = "); try self.genExpr(args[0]); try self.emit(ArraySetup); try self.genExpr(args[1]);
    try self.emit(BisectLoop ++ " if (_a[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; } } break :blk @as(i64, @intCast(_lo)); }");
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(usize, 0)"); return; }
    try self.emit("blk: { const _a_raw = "); try self.genExpr(args[0]); try self.emit(ArraySetup); try self.genExpr(args[1]);
    try self.emit(BisectLoop ++ " if (_x < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } break :blk @as(i64, @intCast(_lo)); }");
}

fn genInsortLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { var _a = "); try self.genExpr(args[0]); try self.emit("; const _x = "); try self.genExpr(args[1]);
    try self.emit("; var _lo: usize = 0; var _hi: usize = _a.items.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2; if (_a.items[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; } } _a.insert(__global_allocator, _lo, _x) catch {}; break :blk; }");
}

fn genInsortRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { var _a = "); try self.genExpr(args[0]); try self.emit("; const _x = "); try self.genExpr(args[1]);
    try self.emit("; var _lo: usize = 0; var _hi: usize = _a.items.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2; if (_x < _a.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } _a.insert(__global_allocator, _lo, _x) catch {}; break :blk; }");
}
