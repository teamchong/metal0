/// Python concurrent.futures module - High-level interface for async execution
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ThreadPoolExecutor", h.c("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}") },
    .{ "ProcessPoolExecutor", h.c("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}") },
    .{ "Future", h.c("struct { _done: bool = false, _cancelled: bool = false, _result: ?*anyopaque = null, _exception: ?*anyopaque = null, pub fn cancel(s: *@This()) bool { if (s._done) return false; s._cancelled = true; return true; } pub fn cancelled(s: *@This()) bool { return s._cancelled; } pub fn running(s: *@This()) bool { return !s._done and !s._cancelled; } pub fn done(s: *@This()) bool { return s._done; } pub fn result(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._result; } pub fn exception(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._exception; } pub fn add_done_callback(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn set_result(s: *@This(), r: anytype) void { s._result = @ptrCast(&r); s._done = true; } pub fn set_exception(s: *@This(), e: anytype) void { s._exception = @ptrCast(&e); s._done = true; } }{}") },
    .{ "wait", h.c(".{ .done = .{}, .not_done = .{} }") }, .{ "as_completed", h.c("&[_]Future{}") },
    .{ "ALL_COMPLETED", h.c("\"ALL_COMPLETED\"") }, .{ "FIRST_COMPLETED", h.c("\"FIRST_COMPLETED\"") },
    .{ "FIRST_EXCEPTION", h.c("\"FIRST_EXCEPTION\"") },
    .{ "CancelledError", h.c("\"CancelledError\"") }, .{ "TimeoutError", h.c("\"TimeoutError\"") },
    .{ "BrokenExecutor", h.c("\"BrokenExecutor\"") }, .{ "InvalidStateError", h.c("\"InvalidStateError\"") },
});
