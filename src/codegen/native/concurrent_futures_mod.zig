/// Python concurrent.futures module - High-level interface for async execution
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ThreadPoolExecutor", genExecutor }, .{ "ProcessPoolExecutor", genExecutor },
    .{ "Future", genFuture }, .{ "wait", genWait }, .{ "as_completed", genAsCompleted },
    .{ "ALL_COMPLETED", genAllCompleted }, .{ "FIRST_COMPLETED", genFirstCompleted }, .{ "FIRST_EXCEPTION", genFirstException },
    .{ "CancelledError", genCancelledError }, .{ "TimeoutError", genTimeoutError },
    .{ "BrokenExecutor", genBrokenExecutor }, .{ "InvalidStateError", genInvalidStateError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genAllCompleted(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ALL_COMPLETED\""); }
fn genFirstCompleted(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FIRST_COMPLETED\""); }
fn genFirstException(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FIRST_EXCEPTION\""); }
fn genCancelledError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"CancelledError\""); }
fn genTimeoutError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"TimeoutError\""); }
fn genBrokenExecutor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"BrokenExecutor\""); }
fn genInvalidStateError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"InvalidStateError\""); }
fn genAsCompleted(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]Future{}"); }
fn genWait(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .done = .{}, .not_done = .{} }"); }

pub fn genExecutor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}");
}

pub fn genFuture(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { _done: bool = false, _cancelled: bool = false, _result: ?*anyopaque = null, _exception: ?*anyopaque = null, pub fn cancel(s: *@This()) bool { if (s._done) return false; s._cancelled = true; return true; } pub fn cancelled(s: *@This()) bool { return s._cancelled; } pub fn running(s: *@This()) bool { return !s._done and !s._cancelled; } pub fn done(s: *@This()) bool { return s._done; } pub fn result(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._result; } pub fn exception(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._exception; } pub fn add_done_callback(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn set_result(s: *@This(), r: anytype) void { s._result = @ptrCast(&r); s._done = true; } pub fn set_exception(s: *@This(), e: anytype) void { s._exception = @ptrCast(&e); s._done = true; } }{}");
}
