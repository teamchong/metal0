/// Python _random module - C accelerator for random (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



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

fn genRandom(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try self.withInlineBlock("rand", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitFmtConst(c, "var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :{s} prng.random().float(f64)", .{label});
        }
    }.emit);
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
    try self.withInlineBlock("grb", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const k = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :{s} @as(i64, @intCast(prng.random().int(u64)))", .{label});
        }
    }.emit);
}
