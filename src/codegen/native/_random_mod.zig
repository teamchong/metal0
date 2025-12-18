/// Python _random module - C accelerator for random (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Random", genRandomClass },
    .{ "random", genRandom },
    .{ "seed", genSeed },
    .{ "getstate", genGetstate },
    .{ "setstate", genSetstate },
    .{ "getrandbits", genGetrandbits },
});

fn genRandomClass(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .state = std.Random.DefaultPrng.init(0) }"), builder_mod.EmitConfig.forExpression());
}

fn genRandom(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_rand: {{ var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :__m{d}_rand prng.random().float(f64); }})", .{ id, id });
}

fn genSeed(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetstate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }"), builder_mod.EmitConfig.forExpression());
}

fn genSetstate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetrandbits(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_grb: {{ const k = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :__m{d}_grb @as(i64, @intCast(prng.random().int(u64))); }})", .{id});
}
