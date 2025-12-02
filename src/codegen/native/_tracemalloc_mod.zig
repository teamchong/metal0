/// Python _tracemalloc module - Internal tracemalloc support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "start", genUnit }, .{ "stop", genUnit }, .{ "is_tracing", genFalse }, .{ "clear_traces", genUnit },
    .{ "get_traceback_limit", genI32_1 }, .{ "get_traced_memory", genTracedMem }, .{ "reset_peak", genUnit },
    .{ "get_tracemalloc_memory", genI64_0 }, .{ "get_object_traceback", genNull }, .{ "get_traces", genEmptyList },
    .{ "get_object_traceback_internal", genNull },
});

fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genTracedMem(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i64, 0), @as(i64, 0) }"); }
fn genEmptyList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
