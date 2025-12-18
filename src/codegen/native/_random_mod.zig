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
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("rand");
    try self.emit("var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :");
    try self.emit(label);
    try self.emit(" prng.random().float(f64); ");
    try b.emitInlineBlockEnd();
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
    const label = try b.emitInlineBlockStart("grb");
    try self.emit("const k = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :{s} @as(i64, @intCast(prng.random().int(u64))); ", .{label});
    try b.emitInlineBlockEnd();
}
