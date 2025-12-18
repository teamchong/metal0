/// Python threading module - Thread-based parallelism
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const thread_struct = "struct { handle: ?std.Thread = null, name: ?[]const u8 = null, daemon: bool = false, pub fn start(s: *@This()) void { _ = s; } pub fn join(s: *@This()) void { if (s.handle) |hnd| hnd.join(); } pub fn is_alive(s: *@This()) bool { _ = s; return false; } pub fn getName(s: *@This()) ?[]const u8 { return s.name; } pub fn setName(s: *@This(), n: []const u8) void { s.name = n; } pub fn isDaemon(s: *@This()) bool { return s.daemon; } pub fn setDaemon(s: *@This(), d: bool) void { s.daemon = d; } }{}";
const lock_struct = "struct { mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); } pub fn release(s: *@This()) void { s.mutex.unlock(); } pub fn locked(s: *@This()) bool { _ = s; return false; } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}";
const condition_struct = "struct { cond: std.Thread.Condition = .{}, mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); } pub fn release(s: *@This()) void { s.mutex.unlock(); } pub fn wait(s: *@This()) void { s.cond.wait(&s.mutex); } pub fn notify(s: *@This()) void { s.cond.signal(); } pub fn notify_all(s: *@This()) void { s.cond.broadcast(); } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}";
const semaphore_struct = "struct { count: i64 = 1, mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); s.count -= 1; s.mutex.unlock(); } pub fn release(s: *@This()) void { s.mutex.lock(); s.count += 1; s.mutex.unlock(); } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}";
const event_struct = "struct { flag: bool = false, mutex: std.Thread.Mutex = .{}, cond: std.Thread.Condition = .{}, pub fn set(s: *@This()) void { s.mutex.lock(); s.flag = true; s.cond.broadcast(); s.mutex.unlock(); } pub fn clear(s: *@This()) void { s.mutex.lock(); s.flag = false; s.mutex.unlock(); } pub fn is_set(s: *@This()) bool { s.mutex.lock(); defer s.mutex.unlock(); return s.flag; } pub fn wait(s: *@This()) void { s.mutex.lock(); while (!s.flag) s.cond.wait(&s.mutex); s.mutex.unlock(); } }{}";
const barrier_struct = "struct { parties: i64 = 1, count: i64 = 0, pub fn wait(s: *@This()) i64 { s.count += 1; return s.count - 1; } pub fn reset(s: *@This()) void { s.count = 0; } pub fn abort(s: *@This()) void { _ = s; } }{}";
const timer_struct = "struct { interval: f64 = 0, pub fn start(s: *@This()) void { _ = s; } pub fn cancel(s: *@This()) void { _ = s; } }{}";
const local_struct = "struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Thread", genThread },
    .{ "Lock", genLock },
    .{ "RLock", genLock },
    .{ "Condition", genCondition },
    .{ "Semaphore", genSemaphore },
    .{ "BoundedSemaphore", genSemaphore },
    .{ "Event", genEvent },
    .{ "Barrier", genBarrier },
    .{ "Timer", genTimer },
    .{ "current_thread", genThread },
    .{ "main_thread", genThread },
    .{ "active_count", genActiveCount },
    .{ "enumerate", genEnumerate },
    .{ "local", genLocal },
});

fn genThread(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(thread_struct), builder_mod.EmitConfig.forExpression());
}

fn genLock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(lock_struct), builder_mod.EmitConfig.forExpression());
}

fn genCondition(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(condition_struct), builder_mod.EmitConfig.forExpression());
}

fn genSemaphore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(semaphore_struct), builder_mod.EmitConfig.forExpression());
}

fn genEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(event_struct), builder_mod.EmitConfig.forExpression());
}

fn genBarrier(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(barrier_struct), builder_mod.EmitConfig.forExpression());
}

fn genTimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(timer_struct), builder_mod.EmitConfig.forExpression());
}

fn genActiveCount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genEnumerate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(struct{}{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genLocal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(local_struct), builder_mod.EmitConfig.forExpression());
}
