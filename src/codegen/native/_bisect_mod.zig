/// Python _bisect module - C accelerator for bisect (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", genBisectLeft },
    .{ "bisect_right", genBisectRight }, .{ "bisect", genBisectRight },
    .{ "insort_left", h.c("{}") }, .{ "insort_right", h.c("{}") }, .{ "insort", h.c("{}") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_bsl: {{ const arr = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const x = "); try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (arr[mid] < x) {{ lo = mid + 1; }} else {{ hi = mid; }} }} break :__m{d}_bsl @as(i64, @intCast(lo)); }})", .{id});
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_bsr: {{ const arr = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const x = "); try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (x < arr[mid]) {{ hi = mid; }} else {{ lo = mid + 1; }} }} break :__m{d}_bsr @as(i64, @intCast(lo)); }})", .{id});
}
