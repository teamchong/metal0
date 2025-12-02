/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Random", genRandom }, .{ "random", genRandomRandom }, .{ "seed", genUnit }, .{ "getstate", genGetstate }, .{ "setstate", genUnit }, .{ "getrandbits", genGetrandbits },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .state = std.Random.DefaultPrng.init(0) }"); }
fn genRandomRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "blk: { var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk prng.random().float(f64); }"); }
fn genGetstate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }"); }
fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const k = "); try self.genExpr(args[0]); try self.emit("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(prng.random().int(u64))); }"); } else { try self.emit("@as(i64, 0)"); }
}
