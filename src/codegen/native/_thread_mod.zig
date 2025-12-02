/// Python _thread module - Low-level threading primitives
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "start_new_thread", genStartThread }, .{ "interrupt_main", genUnit }, .{ "exit", genRet },
    .{ "allocate_lock", genLock }, .{ "get_ident", genIdent }, .{ "get_native_id", genIdent },
    .{ "stack_size", genI64_0 }, .{ "TIMEOUT_MAX", genTimeout }, .{ "LockType", genLockType },
    .{ "RLock", genRLock }, .{ "error", genErr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genRet(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "return"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genTimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 4294967.0)"); }
fn genLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .mutex = std.Thread.Mutex{} }"); }
fn genIdent(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, @intFromPtr(std.Thread.getCurrentId()))"); }
fn genLockType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@TypeOf(.{ .mutex = std.Thread.Mutex{} })"); }
fn genRLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ThreadError"); }

fn genStartThread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const func = "); try self.genExpr(args[0]); try self.emit("; const thread = std.Thread.spawn(.{}, func, .{}) catch break :blk @as(i64, -1); break :blk @as(i64, @intFromPtr(thread)); }"); } else { try self.emit("@as(i64, -1)"); }
}
