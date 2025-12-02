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
    try self.emit("pub fn start(__self: *@This()) void { __self._alive = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn run(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn join(__self: *@This(), timeout: ?f64) void { _ = timeout; __self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn is_alive(__self: *@This()) bool { return __self._alive; }\n");
    try self.emitIndent();
    try self.emit("pub fn terminate(__self: *@This()) void { __self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn kill(__self: *@This()) void { __self._alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { }\n");
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
    try self.emit("pub fn apply(__self: *@This(), func: anytype, args: anytype) @TypeOf(func(args)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("return func(args);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn apply_async(__self: *@This(), func: anytype, args: anytype) AsyncResult {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = args;\n");
    try self.emitIndent();
    try self.emit("return AsyncResult{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn map(__self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
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
    try self.emit("pub fn map_async(__self: *@This(), func: anytype, iterable: anytype) AsyncResult {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = iterable;\n");
    try self.emitIndent();
    try self.emit("return AsyncResult{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn imap(__self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return __self.map(func, iterable);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn imap_unordered(__self: *@This(), func: anytype, iterable: anytype) []@TypeOf(func(iterable[0])) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return __self.map(func, iterable);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn starmap(__self: *@This(), func: anytype, iterable: anytype) []anyopaque {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = func; _ = iterable;\n");
    try self.emitIndent();
    try self.emit("return &.{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn terminate(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn join(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("const AsyncResult = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn get(self: @This(), timeout: ?f64) anyopaque { _ = timeout; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(self: @This(), timeout: ?f64) void { _ = timeout; }\n");
    try self.emitIndent();
    try self.emit("pub fn ready(self: @This()) bool { return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn successful(self: @This()) bool { return true; }\n");
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
    try self.emit("pub fn put(__self: *@This(), item: anytype, block: bool, timeout: ?f64) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("__self.items.append(__global_allocator, @ptrCast(&item)) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put_nowait(__self: *@This(), item: anytype) void { __self.put(item, false, null); }\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), block: bool, timeout: ?f64) ?*anyopaque {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (__self.items.items.len > 0) return __self.items.orderedRemove(0);\n");
    try self.emitIndent();
    try self.emit("return null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get_nowait(__self: *@This()) ?*anyopaque { return __self.get(false, null); }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(__self: *@This()) usize { return __self.items.items.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn full(__self: *@This()) bool { return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn join_thread(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn cancel_join_thread(__self: *@This()) void { }\n");
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
    try self.emit("pub fn send(self: @This(), obj: anytype) void { _ = obj; }\n");
    try self.emitIndent();
    try self.emit("pub fn recv(self: @This()) ?*anyopaque { return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(self: @This(), timeout: ?f64) bool { _ = timeout; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: @This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}, struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn send(self: @This(), obj: anytype) void { _ = obj; }\n");
    try self.emitIndent();
    try self.emit("pub fn recv(self: @This()) ?*anyopaque { return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn poll(self: @This(), timeout: ?f64) bool { _ = timeout; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: @This()) void { }\n");
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
    try self.emit("pub fn get_lock(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn get_obj(self: @This()) i64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: @This()) void { }\n");
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
    try self.emit("pub fn get_lock(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn get_obj(self: @This()) []i64 { return __self.data; }\n");
    try self.emitIndent();
    try self.emit("pub fn acquire(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn release(self: @This()) void { }\n");
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
    try self.emit("pub fn list(self: @This()) std.ArrayList(anyopaque) { return .{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn dict(self: @This()) hashmap_helper.StringHashMap(anyopaque) { return hashmap_helper.StringHashMap(anyopaque).init(__global_allocator); }\n");
    try self.emitIndent();
    try self.emit("pub fn Namespace(self: @This()) @This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn Value(self: @This(), typecode: []const u8, value: anytype) anyopaque { _ = typecode; _ = value; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Array(self: @This(), typecode: []const u8, sequence: anytype) anyopaque { _ = typecode; _ = sequence; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Queue(self: @This(), maxsize: usize) anyopaque { _ = maxsize; return undefined; }\n");
    try self.emitIndent();
    try self.emit("pub fn Lock(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn RLock(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn Semaphore(self: @This(), value: usize) void { _ = value; }\n");
    try self.emitIndent();
    try self.emit("pub fn Condition(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn Event(self: @This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn Barrier(self: @This(), parties: usize) void { _ = parties; }\n");
    try self.emitIndent();
    try self.emit("pub fn shutdown(self: @This()) void { }\n");
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
    try self.emit("pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (__self._locked) return false;\n");
    try self.emitIndent();
    try self.emit("__self._locked = true;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { __self._locked = false; }\n");
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
    try self.emit("pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("__self._count += 1;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { if (__self._count > 0) __self._count -= 1; }\n");
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
    try self.emit("pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = block; _ = timeout;\n");
    try self.emitIndent();
    try self.emit("if (__self._value == 0) return false;\n");
    try self.emitIndent();
    try self.emit("__self._value -= 1;\n");
    try self.emitIndent();
    try self.emit("return true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This(), n: usize) void { __self._value += n; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_value(__self: *@This()) usize { return __self._value; }\n");
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
    try self.emit("pub fn is_set(__self: *@This()) bool { return __self._flag; }\n");
    try self.emitIndent();
    try self.emit("pub fn set(__self: *@This()) void { __self._flag = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn clear(__self: *@This()) void { __self._flag = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(__self: *@This(), timeout: ?f64) bool { _ = timeout; return __self._flag; }\n");
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
    try self.emit("pub fn acquire(__self: *@This()) bool { return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn release(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn wait(__self: *@This(), timeout: ?f64) bool { _ = timeout; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn wait_for(__self: *@This(), predicate: anytype, timeout: ?f64) bool { _ = predicate; _ = timeout; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn notify(__self: *@This(), n: usize) void { _ = n; }\n");
    try self.emitIndent();
    try self.emit("pub fn notify_all(__self: *@This()) void { }\n");
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
    try self.emit("pub fn wait(__self: *@This(), timeout: ?f64) usize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = timeout;\n");
    try self.emitIndent();
    try self.emit("__self.n_waiting += 1;\n");
    try self.emitIndent();
    try self.emit("return __self.n_waiting - 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn reset(__self: *@This()) void { __self.n_waiting = 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn abort(__self: *@This()) void { __self.broken = true; }\n");
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
    try self.emit("pub fn is_alive(self: @This()) bool { return true; }\n");
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
    try self.emit("pub fn Process(self: @This()) type { return @TypeOf(genProcess); }\n");
    try self.emitIndent();
    try self.emit("pub fn Pool(self: @This()) type { return @TypeOf(genPool); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
