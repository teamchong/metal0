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
    try self.withInlineBlock("thr_snt", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __func = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const __thread = std.Thread.spawn(.{{}}, __func, .{{}}) catch break :{s} @as(i64, -1); break :{s} @as(i64, @intFromPtr(__thread))", .{ label, label });
        }
    }.emit);
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
