/// Python _asyncio module - Internal asyncio support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Task", h.c(".{ .coro = null, .loop = null, .name = null, .context = null, .done = false, .cancelled = false }") },
    .{ "Future", h.c(".{ .loop = null, .done = false, .cancelled = false, .result = null, .exception = null }") },
    .{ "get_event_loop", h.c(".{ .running = false, .closed = false }") },
    .{ "get_running_loop", h.c(".{ .running = true, .closed = false }") },
    .{ "_get_running_loop", h.c("null") }, .{ "_set_running_loop", h.c("{}") },
    .{ "_register_task", h.c("{}") }, .{ "_unregister_task", h.c("{}") },
    .{ "_enter_task", h.c("{}") }, .{ "_leave_task", h.c("{}") },
    .{ "current_task", h.c("null") }, .{ "all_tasks", h.c("&[_]@TypeOf(.{}){}") },
});
