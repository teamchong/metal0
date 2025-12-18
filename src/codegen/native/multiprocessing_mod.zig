/// Python multiprocessing module - Process-based parallelism
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const process_struct = "struct { name: ?[]const u8 = null, daemon: bool = false, pid: ?i32 = null, exitcode: ?i32 = null, _alive: bool = false, pub fn start(__self: *@This()) void { __self._alive = true; } pub fn run(__self: *@This()) void { _ = __self; } pub fn join(__self: *@This(), timeout: ?f64) void { _ = timeout; __self._alive = false; } pub fn is_alive(__self: *@This()) bool { return __self._alive; } pub fn terminate(__self: *@This()) void { __self._alive = false; } pub fn kill(__self: *@This()) void { __self._alive = false; } pub fn close(__self: *@This()) void { _ = __self; } }{}";
const pool_struct = "struct { _processes: usize = 4, pub fn apply(__self: *@This(), func: anytype, a: anytype) @TypeOf(func(a)) { _ = __self; return func(a); } pub fn apply_async(__self: *@This(), func: anytype, a: anytype) AsyncResult { _ = __self; _ = func; _ = a; return AsyncResult{}; } pub fn map(__self: *@This(), func: anytype, it: anytype) []@TypeOf(func(it[0])) { _ = __self; var r = std.ArrayList(@TypeOf(func(it[0]))).init(__global_allocator); for (it) |i| r.append(func(i)) catch unreachable; return r.items; } pub fn map_async(__self: *@This(), func: anytype, it: anytype) AsyncResult { _ = __self; _ = func; _ = it; return AsyncResult{}; } pub fn imap(__self: *@This(), func: anytype, it: anytype) []@TypeOf(func(it[0])) { return __self.map(func, it); } pub fn imap_unordered(__self: *@This(), func: anytype, it: anytype) []@TypeOf(func(it[0])) { return __self.map(func, it); } pub fn starmap(__self: *@This(), func: anytype, it: anytype) []anyopaque { _ = __self; _ = func; _ = it; return &.{}; } pub fn close(__self: *@This()) void { _ = __self; } pub fn terminate(__self: *@This()) void { _ = __self; } pub fn join(__self: *@This()) void { _ = __self; } const AsyncResult = struct { pub fn get(s: @This(), t: ?f64) anyopaque { _ = s; _ = t; return undefined; } pub fn wait(s: @This(), t: ?f64) void { _ = s; _ = t; } pub fn ready(s: @This()) bool { _ = s; return true; } pub fn successful(s: @This()) bool { _ = s; return true; } }; }{}";
const queue_struct = "struct { items: std.ArrayList(anyopaque) = .{}, pub fn put(__self: *@This(), item: anytype, block: bool, timeout: ?f64) void { _ = block; _ = timeout; __self.items.append(__global_allocator, @ptrCast(&item)) catch unreachable; } pub fn put_nowait(__self: *@This(), item: anytype) void { __self.put(item, false, null); } pub fn get(__self: *@This(), block: bool, timeout: ?f64) ?*anyopaque { _ = block; _ = timeout; if (__self.items.items.len > 0) return __self.items.orderedRemove(0); return null; } pub fn get_nowait(__self: *@This()) ?*anyopaque { return __self.get(false, null); } pub fn qsize(__self: *@This()) usize { return __self.items.items.len; } pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; } pub fn full(__self: *@This()) bool { _ = __self; return false; } pub fn close(__self: *@This()) void { _ = __self; } pub fn join_thread(__self: *@This()) void { _ = __self; } pub fn cancel_join_thread(__self: *@This()) void { _ = __self; } }{}";
const pipe_struct = ".{ struct { pub fn send(s: @This(), o: anytype) void { _ = s; _ = o; } pub fn recv(s: @This()) ?*anyopaque { _ = s; return null; } pub fn poll(s: @This(), t: ?f64) bool { _ = s; _ = t; return false; } pub fn close(s: @This()) void { _ = s; } }{}, struct { pub fn send(s: @This(), o: anytype) void { _ = s; _ = o; } pub fn recv(s: @This()) ?*anyopaque { _ = s; return null; } pub fn poll(s: @This(), t: ?f64) bool { _ = s; _ = t; return false; } pub fn close(s: @This()) void { _ = s; } }{} }";
const value_struct = "struct { value: i64 = 0, pub fn get_lock(s: @This()) void { _ = s; } pub fn get_obj(__self: @This()) i64 { return __self.value; } pub fn acquire(s: @This()) void { _ = s; } pub fn release(s: @This()) void { _ = s; } }{}";
const array_struct = "struct { data: []i64 = &[_]i64{}, pub fn get_lock(s: @This()) void { _ = s; } pub fn get_obj(__self: @This()) []i64 { return __self.data; } pub fn acquire(s: @This()) void { _ = s; } pub fn release(s: @This()) void { _ = s; } }{}";
const manager_struct = "struct { pub fn list(s: @This()) std.ArrayList(anyopaque) { _ = s; return .{}; } pub fn dict(s: @This()) hashmap_helper.StringHashMap(anyopaque) { _ = s; return hashmap_helper.StringHashMap(anyopaque).init(__global_allocator); } pub fn Namespace(s: @This()) @This() { return s; } pub fn Value(s: @This(), tc: []const u8, v: anytype) anyopaque { _ = s; _ = tc; _ = v; return undefined; } pub fn Array(s: @This(), tc: []const u8, seq: anytype) anyopaque { _ = s; _ = tc; _ = seq; return undefined; } pub fn Queue(s: @This(), max: usize) anyopaque { _ = s; _ = max; return undefined; } pub fn Lock(s: @This()) void { _ = s; } pub fn RLock(s: @This()) void { _ = s; } pub fn Semaphore(s: @This(), v: usize) void { _ = s; _ = v; } pub fn Condition(s: @This()) void { _ = s; } pub fn Event(s: @This()) void { _ = s; } pub fn Barrier(s: @This(), p: usize) void { _ = s; _ = p; } pub fn shutdown(s: @This()) void { _ = s; } }{}";
const lock_struct = "struct { _locked: bool = false, pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool { _ = block; _ = timeout; if (__self._locked) return false; __self._locked = true; return true; } pub fn release(__self: *@This()) void { __self._locked = false; } }{}";
const rlock_struct = "struct { _count: usize = 0, pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool { _ = block; _ = timeout; __self._count += 1; return true; } pub fn release(__self: *@This()) void { if (__self._count > 0) __self._count -= 1; } }{}";
const semaphore_struct = "struct { _value: usize = 1, pub fn acquire(__self: *@This(), block: bool, timeout: ?f64) bool { _ = block; _ = timeout; if (__self._value == 0) return false; __self._value -= 1; return true; } pub fn release(__self: *@This(), n: usize) void { __self._value += n; } pub fn get_value(__self: *@This()) usize { return __self._value; } }{}";
const event_struct = "struct { _flag: bool = false, pub fn is_set(__self: *@This()) bool { return __self._flag; } pub fn set(__self: *@This()) void { __self._flag = true; } pub fn clear(__self: *@This()) void { __self._flag = false; } pub fn wait(__self: *@This(), timeout: ?f64) bool { _ = timeout; return __self._flag; } }{}";
const condition_struct = "struct { pub fn acquire(__self: *@This()) bool { _ = __self; return true; } pub fn release(__self: *@This()) void { _ = __self; } pub fn wait(__self: *@This(), timeout: ?f64) bool { _ = __self; _ = timeout; return true; } pub fn wait_for(__self: *@This(), pred: anytype, timeout: ?f64) bool { _ = __self; _ = pred; _ = timeout; return true; } pub fn notify(__self: *@This(), n: usize) void { _ = __self; _ = n; } pub fn notify_all(__self: *@This()) void { _ = __self; } }{}";
const barrier_struct = "struct { parties: usize = 0, n_waiting: usize = 0, broken: bool = false, pub fn wait(__self: *@This(), timeout: ?f64) usize { _ = timeout; __self.n_waiting += 1; return __self.n_waiting - 1; } pub fn reset(__self: *@This()) void { __self.n_waiting = 0; } pub fn abort(__self: *@This()) void { __self.broken = true; } }{}";
const current_process_struct = "struct { name: []const u8 = \"MainProcess\", daemon: bool = false, pid: i32 = @intCast(std.posix.getpid()), pub fn is_alive(s: @This()) bool { _ = s; return true; } }{}";
const get_context_struct = "struct { pub fn Process(s: @This()) type { _ = s; return @TypeOf(genProcess); } pub fn Pool(s: @This()) type { _ = s; return @TypeOf(genPool); } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
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

fn genProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(process_struct), builder_mod.EmitConfig.forExpression());
}

fn genPool(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(pool_struct), builder_mod.EmitConfig.forExpression());
}

fn genQueue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(queue_struct), builder_mod.EmitConfig.forExpression());
}

fn genPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(pipe_struct), builder_mod.EmitConfig.forExpression());
}

fn genValue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(value_struct), builder_mod.EmitConfig.forExpression());
}

fn genArray(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(array_struct), builder_mod.EmitConfig.forExpression());
}

fn genManager(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(manager_struct), builder_mod.EmitConfig.forExpression());
}

fn genLock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(lock_struct), builder_mod.EmitConfig.forExpression());
}

fn genRLock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(rlock_struct), builder_mod.EmitConfig.forExpression());
}

fn genSemaphore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(semaphore_struct), builder_mod.EmitConfig.forExpression());
}

fn genEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(event_struct), builder_mod.EmitConfig.forExpression());
}

fn genCondition(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(condition_struct), builder_mod.EmitConfig.forExpression());
}

fn genBarrier(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(barrier_struct), builder_mod.EmitConfig.forExpression());
}

fn genCpuCount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, std.Thread.getCpuCount() catch 1)"), builder_mod.EmitConfig.forExpression());
}

fn genCurrentProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(current_process_struct), builder_mod.EmitConfig.forExpression());
}

fn genParentProcess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genActiveChildren(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetStartMethod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetStartMethod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("fork"), builder_mod.EmitConfig.forExpression());
}

fn genGetAllStartMethods(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"fork\", \"spawn\", \"forkserver\" }"), builder_mod.EmitConfig.forExpression());
}

fn genGetContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(get_context_struct), builder_mod.EmitConfig.forExpression());
}
