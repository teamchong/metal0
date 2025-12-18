/// Python _thread module - Low-level threading primitives
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start_new_thread", genStartNewThread },
    .{ "interrupt_main", genInterruptMain },
    .{ "exit", genExit },
    .{ "allocate_lock", genAllocateLock },
    .{ "get_ident", genGetIdent },
    .{ "get_native_id", genGetNativeId },
    .{ "stack_size", genStackSize },
    .{ "TIMEOUT_MAX", genTimeoutMax },
    .{ "LockType", genLockType },
    .{ "RLock", genRLock },
    .{ "error", genError },
});

fn genStartNewThread(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, -1)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__thr_snt_{d}: {{ const __func_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __thread_{d} = std.Thread.spawn(.{{}}, __func_{d}, .{{}}) catch break :__thr_snt_{d} @as(i64, -1); break :__thr_snt_{d} @as(i64, @intFromPtr(__thread_{d})); }})", .{ id, id, id, id, id });
}

fn genInterruptMain(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genExit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("return"), builder_mod.EmitConfig.forExpression());
}

fn genAllocateLock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .mutex = std.Thread.Mutex{} }"), builder_mod.EmitConfig.forExpression());
}

fn genGetIdent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, @intFromPtr(std.Thread.getCurrentId()))"), builder_mod.EmitConfig.forExpression());
}

fn genGetNativeId(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, @intFromPtr(std.Thread.getCurrentId()))"), builder_mod.EmitConfig.forExpression());
}

fn genStackSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genTimeoutMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 4294967.0)"), builder_mod.EmitConfig.forExpression());
}

fn genLockType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{ .mutex = std.Thread.Mutex{} })"), builder_mod.EmitConfig.forExpression());
}

fn genRLock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ThreadError"), builder_mod.EmitConfig.forExpression());
}
