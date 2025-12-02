/// Python concurrent.futures module - High-level interface for async execution
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ThreadPoolExecutor", genConst("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}") },
    .{ "ProcessPoolExecutor", genConst("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}") },
    .{ "Future", genConst("struct { _done: bool = false, _cancelled: bool = false, _result: ?*anyopaque = null, _exception: ?*anyopaque = null, pub fn cancel(s: *@This()) bool { if (s._done) return false; s._cancelled = true; return true; } pub fn cancelled(s: *@This()) bool { return s._cancelled; } pub fn running(s: *@This()) bool { return !s._done and !s._cancelled; } pub fn done(s: *@This()) bool { return s._done; } pub fn result(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._result; } pub fn exception(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._exception; } pub fn add_done_callback(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn set_result(s: *@This(), r: anytype) void { s._result = @ptrCast(&r); s._done = true; } pub fn set_exception(s: *@This(), e: anytype) void { s._exception = @ptrCast(&e); s._done = true; } }{}") },
    .{ "wait", genConst(".{ .done = .{}, .not_done = .{} }") }, .{ "as_completed", genConst("&[_]Future{}") },
    .{ "ALL_COMPLETED", genConst("\"ALL_COMPLETED\"") }, .{ "FIRST_COMPLETED", genConst("\"FIRST_COMPLETED\"") },
    .{ "FIRST_EXCEPTION", genConst("\"FIRST_EXCEPTION\"") },
    .{ "CancelledError", genConst("\"CancelledError\"") }, .{ "TimeoutError", genConst("\"TimeoutError\"") },
    .{ "BrokenExecutor", genConst("\"BrokenExecutor\"") }, .{ "InvalidStateError", genConst("\"InvalidStateError\"") },
});
