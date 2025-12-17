/// Python concurrent.futures module - High-level interface for async execution
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ThreadPoolExecutor", genThreadPoolExecutor },
    .{ "ProcessPoolExecutor", genProcessPoolExecutor },
    .{ "Future", genFuture },
    .{ "wait", genWait },
    .{ "as_completed", genAsCompleted },
    .{ "ALL_COMPLETED", genAllCompleted },
    .{ "FIRST_COMPLETED", genFirstCompleted },
    .{ "FIRST_EXCEPTION", genFirstException },
    .{ "CancelledError", genCancelledError },
    .{ "TimeoutError", genTimeoutError },
    .{ "BrokenExecutor", genBrokenExecutor },
    .{ "InvalidStateError", genInvalidStateError },
});

fn genThreadPoolExecutor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genProcessPoolExecutor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { max_workers: usize = 4, _shutdown: bool = false, pub fn submit(s: *@This(), f: anytype, a: anytype) Future { _ = s; _ = f; _ = a; return Future{}; } pub fn map(s: *@This(), f: anytype, it: anytype, t: ?f64, c: usize) []anyopaque { _ = s; _ = f; _ = it; _ = t; _ = c; return &.{}; } pub fn shutdown(s: *@This(), w: bool, cf: bool) void { _ = w; _ = cf; s._shutdown = true; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype, _: anytype, _: anytype) void { s.shutdown(true, false); } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genFuture(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { _done: bool = false, _cancelled: bool = false, _result: ?*anyopaque = null, _exception: ?*anyopaque = null, pub fn cancel(s: *@This()) bool { if (s._done) return false; s._cancelled = true; return true; } pub fn cancelled(s: *@This()) bool { return s._cancelled; } pub fn running(s: *@This()) bool { return !s._done and !s._cancelled; } pub fn done(s: *@This()) bool { return s._done; } pub fn result(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._result; } pub fn exception(s: *@This(), t: ?f64) ?*anyopaque { _ = t; return s._exception; } pub fn add_done_callback(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn set_result(s: *@This(), r: anytype) void { s._result = @ptrCast(&r); s._done = true; } pub fn set_exception(s: *@This(), e: anytype) void { s._exception = @ptrCast(&e); s._done = true; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genWait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .done = .{}, .not_done = .{} }"), builder_mod.EmitConfig.forExpression());
}

fn genAsCompleted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]Future{}"), builder_mod.EmitConfig.forExpression());
}

fn genAllCompleted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ALL_COMPLETED"), builder_mod.EmitConfig.forExpression());
}

fn genFirstCompleted(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("FIRST_COMPLETED"), builder_mod.EmitConfig.forExpression());
}

fn genFirstException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("FIRST_EXCEPTION"), builder_mod.EmitConfig.forExpression());
}

fn genCancelledError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("CancelledError"), builder_mod.EmitConfig.forExpression());
}

fn genTimeoutError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("TimeoutError"), builder_mod.EmitConfig.forExpression());
}

fn genBrokenExecutor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("BrokenExecutor"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidStateError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("InvalidStateError"), builder_mod.EmitConfig.forExpression());
}

