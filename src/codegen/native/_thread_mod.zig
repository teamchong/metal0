/// Python _thread module - Low-level threading primitives
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genStartNewThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, -1)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__thr_snt_{d}: {{ const __func_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __thread_{d} = std.Thread.spawn(.{{}}, __func_{d}, .{{}}) catch break :__thr_snt_{d} @as(i64, -1); break :__thr_snt_{d} @as(i64, @intFromPtr(__thread_{d})); }})", .{ id, id, id, id, id });
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start_new_thread", genStartNewThread }, .{ "interrupt_main", h.c("{}") }, .{ "exit", h.c("return") },
    .{ "allocate_lock", h.c(".{ .mutex = std.Thread.Mutex{} }") }, .{ "get_ident", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "get_native_id", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "stack_size", h.I64(0) }, .{ "TIMEOUT_MAX", h.F64(4294967.0) },
    .{ "LockType", h.c("@TypeOf(.{ .mutex = std.Thread.Mutex{} })") },
    .{ "RLock", h.c(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }") },
    .{ "error", h.err("ThreadError") },
});
