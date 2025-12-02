/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Random", h.c(".{ .state = std.Random.DefaultPrng.init(0) }") }, .{ "random", h.c("blk: { var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk prng.random().float(f64); }") },
    .{ "seed", h.c("{}") }, .{ "getstate", h.c(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }") }, .{ "setstate", h.c("{}") }, .{ "getrandbits", genGetrandbits },
});

fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const k = "); try self.genExpr(args[0]); try self.emit("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(prng.random().int(u64))); }"); } else { try self.emit("@as(i64, 0)"); }
}
