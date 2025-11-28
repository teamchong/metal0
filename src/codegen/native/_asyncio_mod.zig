/// Python _asyncio module - Internal asyncio support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _asyncio.Task(coro, *, loop=None, name=None, context=None)
pub fn genTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .coro = null, .loop = null, .name = null, .context = null, .done = false, .cancelled = false }");
}

/// Generate _asyncio.Future(*, loop=None)
pub fn genFuture(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .loop = null, .done = false, .cancelled = false, .result = null, .exception = null }");
}

/// Generate _asyncio.get_event_loop()
pub fn genGetEventLoop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .running = false, .closed = false }");
}

/// Generate _asyncio.get_running_loop()
pub fn genGetRunningLoop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .running = true, .closed = false }");
}

/// Generate _asyncio._get_running_loop()
pub fn genInternalGetRunningLoop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _asyncio._set_running_loop(loop)
pub fn genSetRunningLoop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _asyncio._register_task(task)
pub fn genRegisterTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _asyncio._unregister_task(task)
pub fn genUnregisterTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _asyncio._enter_task(loop, task)
pub fn genEnterTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _asyncio._leave_task(loop, task)
pub fn genLeaveTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _asyncio.current_task(loop=None)
pub fn genCurrentTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _asyncio.all_tasks(loop=None)
pub fn genAllTasks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}
