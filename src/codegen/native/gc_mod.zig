/// Python gc module - Garbage collector interface
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "enable", genEnable },
    .{ "disable", genDisable },
    .{ "isenabled", genIsenabled },
    .{ "collect", genCollect },
    .{ "set_debug", genSetDebug },
    .{ "get_debug", genGetDebug },
    .{ "get_stats", genGetStats },
    .{ "set_threshold", genSetThreshold },
    .{ "get_threshold", genGetThreshold },
    .{ "get_count", genGetCount },
    .{ "get_objects", genGetObjects },
    .{ "get_referrers", genGetReferrers },
    .{ "get_referents", genGetReferents },
    .{ "is_tracked", genIsTracked },
    .{ "is_finalized", genIsFinalized },
    .{ "freeze", genFreeze },
    .{ "unfreeze", genUnfreeze },
    .{ "get_freeze_count", genGetFreezeCount },
    .{ "garbage", genGarbage },
    .{ "callbacks", genCallbacks },
    .{ "DEBUG_STATS", genDebugStats },
    .{ "DEBUG_COLLECTABLE", genDebugCollectable },
    .{ "DEBUG_UNCOLLECTABLE", genDebugUncollectable },
    .{ "DEBUG_SAVEALL", genDebugSaveall },
    .{ "DEBUG_LEAK", genDebugLeak },
});

fn genEnable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDisable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genIsenabled(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genCollect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genSetDebug(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetDebug(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]struct { collections: i64, collected: i64, uncollectable: i64 }{ .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 } }"), builder_mod.EmitConfig.forExpression());
}

fn genSetThreshold(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetThreshold(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 700), @as(i32, 10), @as(i32, 10) }"), builder_mod.EmitConfig.forExpression());
}

fn genGetCount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 0), @as(i32, 0), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genGetObjects(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetReferrers(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetReferents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genIsTracked(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genIsFinalized(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genFreeze(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnfreeze(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetFreezeCount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGarbage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genCallbacks(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*const fn () void{}"), builder_mod.EmitConfig.forExpression());
}

fn genDebugStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genDebugCollectable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genDebugUncollectable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genDebugSaveall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}

fn genDebugLeak(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(38), builder_mod.EmitConfig.forExpression());
}
