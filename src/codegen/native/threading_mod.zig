/// Python threading module - Thread-based parallelism
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Thread", genThread }, .{ "Lock", genLock }, .{ "RLock", genLock },
    .{ "Condition", genCondition }, .{ "Semaphore", genSemaphore }, .{ "BoundedSemaphore", genSemaphore },
    .{ "Event", genEvent }, .{ "Barrier", genBarrier }, .{ "Timer", genTimer },
    .{ "current_thread", genThread }, .{ "main_thread", genThread },
    .{ "active_count", genActiveCount }, .{ "enumerate", genEnumerate }, .{ "local", genLocal },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genActiveCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 1)"); }
fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(struct{}{}){}"); }
fn genLocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}"); }

pub fn genThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { handle: ?std.Thread = null, name: ?[]const u8 = null, daemon: bool = false, pub fn start(s: *@This()) void { _ = s; } pub fn join(s: *@This()) void { if (s.handle) |h| h.join(); } pub fn is_alive(s: *@This()) bool { _ = s; return false; } pub fn getName(s: *@This()) ?[]const u8 { return s.name; } pub fn setName(s: *@This(), n: []const u8) void { s.name = n; } pub fn isDaemon(s: *@This()) bool { return s.daemon; } pub fn setDaemon(s: *@This(), d: bool) void { s.daemon = d; } }{}");
}

pub fn genLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); } pub fn release(s: *@This()) void { s.mutex.unlock(); } pub fn locked(s: *@This()) bool { _ = s; return false; } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}");
}

pub fn genCondition(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { cond: std.Thread.Condition = .{}, mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); } pub fn release(s: *@This()) void { s.mutex.unlock(); } pub fn wait(s: *@This()) void { s.cond.wait(&s.mutex); } pub fn notify(s: *@This()) void { s.cond.signal(); } pub fn notify_all(s: *@This()) void { s.cond.broadcast(); } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}");
}

pub fn genSemaphore(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { count: i64 = 1, mutex: std.Thread.Mutex = .{}, pub fn acquire(s: *@This()) void { s.mutex.lock(); s.count -= 1; s.mutex.unlock(); } pub fn release(s: *@This()) void { s.mutex.lock(); s.count += 1; s.mutex.unlock(); } pub fn __enter__(s: *@This()) *@This() { s.acquire(); return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.release(); } }{}");
}

pub fn genEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { flag: bool = false, mutex: std.Thread.Mutex = .{}, cond: std.Thread.Condition = .{}, pub fn set(s: *@This()) void { s.mutex.lock(); s.flag = true; s.cond.broadcast(); s.mutex.unlock(); } pub fn clear(s: *@This()) void { s.mutex.lock(); s.flag = false; s.mutex.unlock(); } pub fn is_set(s: *@This()) bool { s.mutex.lock(); defer s.mutex.unlock(); return s.flag; } pub fn wait(s: *@This()) void { s.mutex.lock(); while (!s.flag) s.cond.wait(&s.mutex); s.mutex.unlock(); } }{}");
}

pub fn genBarrier(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { parties: i64 = 1, count: i64 = 0, pub fn wait(s: *@This()) i64 { s.count += 1; return s.count - 1; } pub fn reset(s: *@This()) void { s.count = 0; } pub fn abort(s: *@This()) void { _ = s; } }{}");
}

pub fn genTimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { interval: f64 = 0, pub fn start(s: *@This()) void { _ = s; } pub fn cancel(s: *@This()) void { _ = s; } }{}");
}
