/// Python bdb module - Debugger framework
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Bdb", h.c(".{ .skip = null, .breaks = .{}, .fncache = .{}, .frame_returning = null }") },
    .{ "Breakpoint", h.wrap2(".{ .file = ", ", .line = ", ", .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }", ".{ .file = \"\", .line = 0, .temporary = false, .cond = null, .funcname = null, .enabled = true, .ignore = 0, .hits = 0 }") },
    .{ "effective", h.c(".{ null, false }") },
    .{ "checkfuncname", h.c("true") }, .{ "set_trace", h.c("{}") }, .{ "BdbQuit", h.err("BdbQuit") },
    .{ "reset", h.c("{}") }, .{ "trace_dispatch", h.c("null") }, .{ "dispatch_line", h.c("null") },
    .{ "dispatch_call", h.c("null") }, .{ "dispatch_return", h.c("null") }, .{ "dispatch_exception", h.c("null") },
    .{ "is_skipped_module", h.c("false") }, .{ "stop_here", h.c("false") }, .{ "break_here", h.c("false") },
    .{ "break_anywhere", h.c("false") }, .{ "set_step", h.c("{}") }, .{ "set_next", h.c("{}") },
    .{ "set_return", h.c("{}") }, .{ "set_until", h.c("{}") }, .{ "set_continue", h.c("{}") },
    .{ "set_quit", h.c("{}") }, .{ "set_break", h.c("null") }, .{ "clear_break", h.c("null") },
    .{ "clear_bpbynumber", h.c("null") }, .{ "clear_all_file_breaks", h.c("null") }, .{ "clear_all_breaks", h.c("null") },
    .{ "get_bpbynumber", h.c("null") }, .{ "get_break", h.c("false") }, .{ "get_breaks", h.c("&[_]@TypeOf(.{}){}") },
    .{ "get_file_breaks", h.c("&[_]i64{}") }, .{ "get_all_breaks", h.c(".{}") },
    .{ "get_stack", h.c(".{ &[_]@TypeOf(.{}){}, 0 }") }, .{ "format_stack_entry", h.c("\"\"") },
    .{ "run", h.c("{}") }, .{ "runeval", h.c("null") }, .{ "runctx", h.c("{}") }, .{ "runcall", h.c("null") },
    .{ "canonic", h.pass("\"\"") },
});
