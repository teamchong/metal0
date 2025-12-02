/// Python _thread module - Low-level threading primitives
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start_new_thread", genStartThread }, .{ "interrupt_main", h.c("{}") }, .{ "exit", h.c("return") },
    .{ "allocate_lock", h.c(".{ .mutex = std.Thread.Mutex{} }") }, .{ "get_ident", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "get_native_id", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "stack_size", h.I64(0) }, .{ "TIMEOUT_MAX", h.F64(4294967.0) },
    .{ "LockType", h.c("@TypeOf(.{ .mutex = std.Thread.Mutex{} })") },
    .{ "RLock", h.c(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }") },
    .{ "error", h.err("ThreadError") },
});

fn genStartThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const func = "); try self.genExpr(args[0]); try self.emit("; const thread = std.Thread.spawn(.{}, func, .{}) catch break :blk @as(i64, -1); break :blk @as(i64, @intFromPtr(thread)); }"); } else { try self.emit("@as(i64, -1)"); }
}
