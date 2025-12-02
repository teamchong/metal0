/// Python gc module - Garbage collector interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "enable", genUnit }, .{ "disable", genUnit }, .{ "isenabled", genTrue }, .{ "collect", genI64_0 },
    .{ "set_debug", genUnit }, .{ "get_debug", genI32_0 }, .{ "get_stats", genGetStats },
    .{ "set_threshold", genUnit }, .{ "get_threshold", genGetThreshold }, .{ "get_count", genGetCount },
    .{ "get_objects", genPtrArr }, .{ "get_referrers", genPtrArr }, .{ "get_referents", genPtrArr },
    .{ "is_tracked", genFalse }, .{ "is_finalized", genFalse }, .{ "freeze", genUnit }, .{ "unfreeze", genUnit },
    .{ "get_freeze_count", genI64_0 }, .{ "garbage", genPtrArr }, .{ "callbacks", genFnPtrArr },
    .{ "DEBUG_STATS", genI32_1 }, .{ "DEBUG_COLLECTABLE", genI32_2 }, .{ "DEBUG_UNCOLLECTABLE", genI32_4 },
    .{ "DEBUG_SAVEALL", genI32_32 }, .{ "DEBUG_LEAK", genI32_38 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 32)"); }
fn genI32_38(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 38)"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genPtrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]*anyopaque{}"); }
fn genFnPtrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]*const fn () void{}"); }
fn genGetStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { collections: i64, collected: i64, uncollectable: i64 }{ .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 } }"); }
fn genGetThreshold(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 700), @as(i32, 10), @as(i32, 10) }"); }
fn genGetCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 0), @as(i32, 0), @as(i32, 0) }"); }
