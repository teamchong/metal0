/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Random", genConst(".{ .state = std.Random.DefaultPrng.init(0) }") }, .{ "random", genConst("blk: { var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk prng.random().float(f64); }") },
    .{ "seed", genConst("{}") }, .{ "getstate", genConst(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }") }, .{ "setstate", genConst("{}") }, .{ "getrandbits", genGetrandbits },
});

fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const k = "); try self.genExpr(args[0]); try self.emit("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(prng.random().int(u64))); }"); } else { try self.emit("@as(i64, 0)"); }
}
