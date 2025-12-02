/// Python _thread module - Low-level threading primitives
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "start_new_thread", genStartThread }, .{ "interrupt_main", genConst("{}") }, .{ "exit", genConst("return") },
    .{ "allocate_lock", genConst(".{ .mutex = std.Thread.Mutex{} }") }, .{ "get_ident", genConst("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "get_native_id", genConst("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "stack_size", genConst("@as(i64, 0)") }, .{ "TIMEOUT_MAX", genConst("@as(f64, 4294967.0)") },
    .{ "LockType", genConst("@TypeOf(.{ .mutex = std.Thread.Mutex{} })") },
    .{ "RLock", genConst(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }") },
    .{ "error", genConst("error.ThreadError") },
});

fn genStartThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const func = "); try self.genExpr(args[0]); try self.emit("; const thread = std.Thread.spawn(.{}, func, .{}) catch break :blk @as(i64, -1); break :blk @as(i64, @intFromPtr(thread)); }"); } else { try self.emit("@as(i64, -1)"); }
}
