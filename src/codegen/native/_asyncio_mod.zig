/// Python _asyncio module - Internal asyncio support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Task", genConst(".{ .coro = null, .loop = null, .name = null, .context = null, .done = false, .cancelled = false }") },
    .{ "Future", genConst(".{ .loop = null, .done = false, .cancelled = false, .result = null, .exception = null }") },
    .{ "get_event_loop", genConst(".{ .running = false, .closed = false }") },
    .{ "get_running_loop", genConst(".{ .running = true, .closed = false }") },
    .{ "_get_running_loop", genConst("null") }, .{ "_set_running_loop", genConst("{}") },
    .{ "_register_task", genConst("{}") }, .{ "_unregister_task", genConst("{}") },
    .{ "_enter_task", genConst("{}") }, .{ "_leave_task", genConst("{}") },
    .{ "current_task", genConst("null") }, .{ "all_tasks", genConst("&[_]@TypeOf(.{}){}") },
});
