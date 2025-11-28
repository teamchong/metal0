/// Python threading module - Thread-based parallelism
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
    try self.emit("pub fn start(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn join(self: *@This()) void { if (self.handle) |h| h.join(); }\n");
    try self.emitIndent();
    try self.emit("pub fn is_alive(self: *@This()) bool { _ = self; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn getName(self: *@This()) ?[]const u8 { return self.name; }\n");
    try self.emitIndent();
    try self.emit("pub fn setName(self: *@This(), n: []const u8) void { self.name = n; }\n");
    try self.emitIndent();
    try self.emit("pub fn isDaemon(self: *@This()) bool { return self.daemon; }\n");
    try self.emitIndent();
    try self.emit("pub fn setDaemon(self: *@This(), d: bool) void { self.daemon = d; }\n");
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
    try self.emit("pub fn acquire(self: *@This()) void { self.mutex.lock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn locked(self: *@This()) bool { _ = self; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { self.acquire(); return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.release(); }\n");
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
    try self.emit("pub fn acquire(self: *@This()) void { self.mutex.lock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: *@This()) void { self.cond.wait(&self.mutex); }\n");
    try self.emitIndent();
    try self.emit("pub fn notify(self: *@This()) void { self.cond.signal(); }\n");
    try self.emitIndent();
    try self.emit("pub fn notify_all(self: *@This()) void { self.cond.broadcast(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { self.acquire(); return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.release(); }\n");
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
    try self.emit("pub fn acquire(self: *@This()) void { self.mutex.lock(); self.count -= 1; self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { self.mutex.lock(); self.count += 1; self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { self.acquire(); return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.release(); }\n");
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
    try self.emit("pub fn set(self: *@This()) void { self.mutex.lock(); self.flag = true; self.cond.broadcast(); self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn clear(self: *@This()) void { self.mutex.lock(); self.flag = false; self.mutex.unlock(); }\n");
    try self.emitIndent();
    try self.emit("pub fn is_set(self: *@This()) bool { self.mutex.lock(); defer self.mutex.unlock(); return self.flag; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: *@This()) void { self.mutex.lock(); while (!self.flag) self.cond.wait(&self.mutex); self.mutex.unlock(); }\n");
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
    try self.emit("pub fn wait(self: *@This()) i64 { self.count += 1; return self.count - 1; }\n");
    try self.emitIndent();
    try self.emit("pub fn reset(self: *@This()) void { self.count = 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn abort(self: *@This()) void { _ = self; }\n");
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
    try self.emit("pub fn start(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn cancel(self: *@This()) void { _ = self; }\n");
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
    try self.emit("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(allocator) }{}");
}
