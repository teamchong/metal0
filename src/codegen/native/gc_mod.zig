/// Python gc module - Garbage collector interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "enable", genConst("{}") }, .{ "disable", genConst("{}") }, .{ "isenabled", genConst("true") }, .{ "collect", genConst("@as(i64, 0)") },
    .{ "set_debug", genConst("{}") }, .{ "get_debug", genConst("@as(i32, 0)") },
    .{ "get_stats", genConst("&[_]struct { collections: i64, collected: i64, uncollectable: i64 }{ .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 } }") },
    .{ "set_threshold", genConst("{}") }, .{ "get_threshold", genConst(".{ @as(i32, 700), @as(i32, 10), @as(i32, 10) }") },
    .{ "get_count", genConst(".{ @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "get_objects", genConst("&[_]*anyopaque{}") }, .{ "get_referrers", genConst("&[_]*anyopaque{}") }, .{ "get_referents", genConst("&[_]*anyopaque{}") },
    .{ "is_tracked", genConst("false") }, .{ "is_finalized", genConst("false") }, .{ "freeze", genConst("{}") }, .{ "unfreeze", genConst("{}") },
    .{ "get_freeze_count", genConst("@as(i64, 0)") }, .{ "garbage", genConst("&[_]*anyopaque{}") }, .{ "callbacks", genConst("&[_]*const fn () void{}") },
    .{ "DEBUG_STATS", genConst("@as(i32, 1)") }, .{ "DEBUG_COLLECTABLE", genConst("@as(i32, 2)") }, .{ "DEBUG_UNCOLLECTABLE", genConst("@as(i32, 4)") },
    .{ "DEBUG_SAVEALL", genConst("@as(i32, 32)") }, .{ "DEBUG_LEAK", genConst("@as(i32, 38)") },
});
