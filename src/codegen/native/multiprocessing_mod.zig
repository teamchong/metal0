/// Python multiprocessing module - Process-based parallelism
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Process", genProcess },
    .{ "Pool", genPool },
    .{ "Queue", genQueue },
    .{ "Pipe", genPipe },
    .{ "Value", genValue },
    .{ "Array", genArray },
    .{ "Manager", genManager },
    .{ "Lock", genLock },
    .{ "RLock", genRLock },
    .{ "Semaphore", genSemaphore },
    .{ "Event", genEvent },
    .{ "Condition", genCondition },
    .{ "Barrier", genBarrier },
    .{ "cpu_count", genCpuCount },
    .{ "current_process", genCurrentProcess },
    .{ "parent_process", genParentProcess },
    .{ "active_children", genActiveChildren },
    .{ "set_start_method", genSetStartMethod },
    .{ "get_start_method", genGetStartMethod },
    .{ "get_all_start_methods", genGetAllStartMethods },
    .{ "get_context", genGetContext },
});

/// Generate multiprocessing.Process(target=None, args=(), kwargs={}, name=None, daemon=None)
pub fn genProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("daemon: bool = false,\n");
    try self.emitIndent();
    try self.emit("pid: ?i32 = null,\n");
    try self.emitIndent();
    try self.emit("exitcode: ?i32 = null,\n");
    try self.emitIndent();
    try self.emit("_alive: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn start(self: *@This()) void { self._alive = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn run(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn join(self: *@This(), timeout: ?f64) void { _ = self; _ = timeout; self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn is_alive(self: *@This()) bool { return self._alive; }\n");
    try self.emitIndent();
    try self.emit("pub fn terminate(self: *@This()) void { self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn kill(self: *@This()) void { self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Pool(processes=None, initializer=None, initargs=(), maxtasksperchild=None)
pub fn genPool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_processes: usize = 4,\n");
    try self.emitIndent();
    try self.emit("pub fn apply(self: *@This(), func: anytype, args: anytype) @TypeOf(func(args)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("return func(args);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn apply_async(self: *@This(), func: anytype, args: anytype) AsyncResult {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = args;\n");
    try self.emitIndent();
    try self.emit("return AsyncResult{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn map(self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("var result: std.ArrayList(@TypeOf(func(iterable[0]))) = .{};\n");
    try self.emitIndent();
    try self.emit("for (iterable) |item| result.append(__global_allocator, func(item)) catch {};\n");
    try self.emitIndent();
    try self.emit("return result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn map_async(self: *@This(), func: anytype, iterable: anytype) AsyncResult {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = iterable;\n");
    try self.emitIndent();
    try self.emit("return AsyncResult{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn imap(self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return self.map(func, iterable);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn imap_unordered(self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return self.map(func, iterable);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn starmap(self: *@This(), func: anytype, iterable: anytype) []anyopaque {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = iterable;\n");
    try self.emitIndent();
    try self.emit("return &.{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn terminate(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn join(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("const AsyncResult = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn get(self: @This(), timeout: ?f64) anyopaque { _ = self; _ = timeout; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: @This(), timeout: ?f64) void { _ = self; _ = timeout; }\n");
    try self.emitIndent();
    try self.emit("pub fn ready(self: @This()) bool { _ = self; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn successful(self: @This()) bool { _ = self; return true; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Queue(maxsize=0)
pub fn genQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("items: std.ArrayList(anyopaque) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn put(self: *@This(), item: anytype, block: bool, timeout: ?f64) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("self.items.append(__global_allocator, @ptrCast(&item)) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put_nowait(self: *@This(), item: anytype) void { self.put(item, false, null); }\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), block: bool, timeout: ?f64) ?*anyopaque {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (self.items.items.len > 0) return self.items.orderedRemove(0);\n");
    try self.emitIndent();
    try self.emit("return null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get_nowait(self: *@This()) ?*anyopaque { return self.get(false, null); }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(self: *@This()) usize { return self.items.items.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn empty(self: *@This()) bool { return self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn full(self: *@This()) bool { _ = self; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn join_thread(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn cancel_join_thread(self: *@This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Pipe(duplex=True)
pub fn genPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn send(self: @This(), obj: anytype) void { _ = self; _ = obj; }\n");
    try self.emitIndent();
    try self.emit("pub fn recv(self: @This()) ?*anyopaque { _ = self; return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(self: @This(), timeout: ?f64) bool { _ = self; _ = timeout; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: @This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}, struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn send(self: @This(), obj: anytype) void { _ = self; _ = obj; }\n");
    try self.emitIndent();
    try self.emit("pub fn recv(self: @This()) ?*anyopaque { _ = self; return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(self: @This(), timeout: ?f64) bool { _ = self; _ = timeout; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: @This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{} }");
}

/// Generate multiprocessing.Value(typecode_or_type, *args, lock=True)
pub fn genValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("value: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn get_lock(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_obj(self: @This()) i64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: @This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Array(typecode_or_type, size_or_initializer, *, lock=True)
pub fn genArray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: []i64 = &[_]i64{},\n");
    try self.emitIndent();
    try self.emit("pub fn get_lock(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_obj(self: @This()) []i64 { return self.data; }\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: @This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Manager()
pub fn genManager(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn list(self: @This()) std.ArrayList(anyopaque) { _ = self; return .{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn dict(self: @This()) hashmap_helper.StringHashMap(anyopaque) { _ = self; return hashmap_helper.StringHashMap(anyopaque).init(__global_allocator); }\n");
    try self.emitIndent();
    try self.emit("pub fn Namespace(self: @This()) @This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn Value(self: @This(), typecode: []const u8, value: anytype) anyopaque { _ = self; _ = typecode; _ = value; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Array(self: @This(), typecode: []const u8, sequence: anytype) anyopaque { _ = self; _ = typecode; _ = sequence; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Queue(self: @This(), maxsize: usize) anyopaque { _ = self; _ = maxsize; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Lock(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn RLock(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn Semaphore(self: @This(), value: usize) void { _ = self; _ = value; }\n");
    try self.emitIndent();
    try self.emit("pub fn Condition(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn Event(self: @This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn Barrier(self: @This(), parties: usize) void { _ = self; _ = parties; }\n");
    try self.emitIndent();
    try self.emit("pub fn shutdown(self: @This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Lock()
pub fn genLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_locked: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (self._locked) return false;\n");
    try self.emitIndent();
    try self.emit("self._locked = true;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { self._locked = false; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.RLock()
pub fn genRLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_count: usize = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("self._count += 1;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { if (self._count > 0) self._count -= 1; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Semaphore(value=1)
pub fn genSemaphore(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_value: usize = 1,\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (self._value == 0) return false;\n");
    try self.emitIndent();
    try self.emit("self._value -= 1;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This(), n: usize) void { self._value += n; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_value(self: *@This()) usize { return self._value; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Event()
pub fn genEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_flag: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn is_set(self: *@This()) bool { return self._flag; }\n");
    try self.emitIndent();
    try self.emit("pub fn set(self: *@This()) void { self._flag = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn clear(self: *@This()) void { self._flag = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: *@This(), timeout: ?f64) bool { _ = timeout; return self._flag; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Condition(lock=None)
pub fn genCondition(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn acquire(self: *@This()) bool { _ = self; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: *@This(), timeout: ?f64) bool { _ = self; _ = timeout; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait_for(self: *@This(), predicate: anytype, timeout: ?f64) bool { _ = self; _ = predicate; _ = timeout; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn notify(self: *@This(), n: usize) void { _ = self; _ = n; }\n");
    try self.emitIndent();
    try self.emit("pub fn notify_all(self: *@This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.Barrier(parties, action=None, timeout=None)
pub fn genBarrier(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("parties: usize = 0,\n");
    try self.emitIndent();
    try self.emit("n_waiting: usize = 0,\n");
    try self.emitIndent();
    try self.emit("broken: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: *@This(), timeout: ?f64) usize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = timeout;\n");
    try self.emitIndent();
    try self.emit("self.n_waiting += 1;\n");
    try self.emitIndent();
    try self.emit("return self.n_waiting - 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn reset(self: *@This()) void { self.n_waiting = 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn abort(self: *@This()) void { self.broken = true; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.cpu_count()
pub fn genCpuCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, std.Thread.getCpuCount() catch 1)");
}

/// Generate multiprocessing.current_process()
pub fn genCurrentProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8 = \"MainProcess\",\n");
    try self.emitIndent();
    try self.emit("daemon: bool = false,\n");
    try self.emitIndent();
    try self.emit("pid: i32 = @intCast(std.posix.getpid()),\n");
    try self.emitIndent();
    try self.emit("pub fn is_alive(self: @This()) bool { _ = self; return true; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate multiprocessing.parent_process()
pub fn genParentProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate multiprocessing.active_children()
pub fn genActiveChildren(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*anyopaque{}");
}

/// Generate multiprocessing.set_start_method(method, force=False)
pub fn genSetStartMethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate multiprocessing.get_start_method(allow_none=False)
pub fn genGetStartMethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"fork\"");
}

/// Generate multiprocessing.get_all_start_methods()
pub fn genGetAllStartMethods(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"fork\", \"spawn\", \"forkserver\" }");
}

/// Generate multiprocessing.get_context(method=None)
pub fn genGetContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn Process(self: @This()) type { _ = self; return @TypeOf(genProcess); }\n");
    try self.emitIndent();
    try self.emit("pub fn Pool(self: @This()) type { _ = self; return @TypeOf(genPool); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
