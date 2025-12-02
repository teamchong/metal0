/// Python threading module - Thread-based parallelism
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Thread", genThread },
    .{ "Lock", genLock },
    .{ "RLock", genRLock },
    .{ "Condition", genCondition },
    .{ "Semaphore", genSemaphore },
    .{ "BoundedSemaphore", genBoundedSemaphore },
    .{ "Event", genEvent },
    .{ "Barrier", genBarrier },
    .{ "Timer", genTimer },
    .{ "current_thread", genCurrentThread },
    .{ "main_thread", genMainThread },
    .{ "active_count", genActiveCount },
    .{ "enumerate", genEnumerate },
    .{ "local", genLocal },
});

/// Generate threading.Thread(target=None, args=(), kwargs={}) -> Thread
pub fn genThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("handle: ?std.Thread = null,\n");
    try self.emitIndent();
    try self.emit("name: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("daemon: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn start(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn join(__self: *@This()) void { if (__self.handle) |h| h.join(); }\n");
    try self.emitIndent();
    try self.emit("pub fn is_alive(__self: *@This()) bool { return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn getName(__self: *@This()) ?[]const u8 { return __self.name; }\n");
    try self.emitIndent();
    try self.emit("pub fn setName(__self: *@This(), n: []const u8) void { __self.name = n; }\n");
    try self.emitIndent();
    try self.emit("pub fn isDaemon(__self: *@This()) bool { return __self.daemon; }\n");
    try self.emitIndent();
    try self.emit("pub fn setDaemon(__self: *@This(), d: bool) void { __self.daemon = d; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.Lock() -> Lock
pub fn genLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(__self: *@This()) void { __self.mutex.lock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn locked(__self: *@This()) bool { return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { __self.acquire(); return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.release(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.RLock() -> RLock (reentrant lock)
pub fn genRLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genLock(self, args);
}

/// Generate threading.Condition(lock=None) -> Condition
pub fn genCondition(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("cond: std.Thread.Condition = .{},\n");
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(__self: *@This()) void { __self.mutex.lock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(__self: *@This()) void { __self.cond.wait(&__self.mutex); }\n");
    try self.emitIndent();
    try self.emit("pub fn notify(__self: *@This()) void { __self.cond.signal(); }\n");
    try self.emitIndent();
    try self.emit("pub fn notify_all(__self: *@This()) void { __self.cond.broadcast(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { __self.acquire(); return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.release(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.Semaphore(value=1) -> Semaphore
pub fn genSemaphore(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("count: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(__self: *@This()) void { __self.mutex.lock(); __self.count -= 1; __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { __self.mutex.lock(); __self.count += 1; __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { __self.acquire(); return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.release(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.BoundedSemaphore(value=1) -> BoundedSemaphore
pub fn genBoundedSemaphore(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genSemaphore(self, args);
}

/// Generate threading.Event() -> Event
pub fn genEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("flag: bool = false,\n");
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("cond: std.Thread.Condition = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn set(__self: *@This()) void { __self.mutex.lock(); __self.flag = true; __self.cond.broadcast(); __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn clear(__self: *@This()) void { __self.mutex.lock(); __self.flag = false; __self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn is_set(__self: *@This()) bool { __self.mutex.lock(); defer __self.mutex.unlock(); return __self.flag; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(__self: *@This()) void { __self.mutex.lock(); while (!__self.flag) __self.cond.wait(&__self.mutex); __self.mutex.unlock(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.Barrier(parties) -> Barrier
pub fn genBarrier(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("parties: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("count: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn wait(__self: *@This()) i64 { __self.count += 1; return __self.count - 1; }\n");
    try self.emitIndent();
    try self.emit("pub fn reset(__self: *@This()) void { __self.count = 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn abort(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.Timer(interval, function) -> Timer
pub fn genTimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("interval: f64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn start(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn cancel(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate threading.current_thread() -> Thread
pub fn genCurrentThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genThread(self, args);
}

/// Generate threading.main_thread() -> Thread
pub fn genMainThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genThread(self, args);
}

/// Generate threading.active_count() -> int
pub fn genActiveCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate threading.enumerate() -> list of threads
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(struct{}{}){}");
}

/// Generate threading.local() -> thread local storage
pub fn genLocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}");
}
