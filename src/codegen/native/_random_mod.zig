/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Random", h.c(".{ .state = std.Random.DefaultPrng.init(0) }") }, .{ "random", genRandom },
    .{ "seed", h.c("{}") }, .{ "getstate", h.c(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }") }, .{ "setstate", h.c("{}") }, .{ "getrandbits", genGetrandbits },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genRandom(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_rand: {{ var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :__m{d}_rand prng.random().float(f64); }})", .{ id, id });
}

fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_grb: {{ const k = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :__m{d}_grb @as(i64, @intCast(prng.random().int(u64))); }})", .{id});
}
