/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _random.Random()
pub fn genRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .state = std.Random.DefaultPrng.init(0) }");
}

/// Generate _random.Random.random()
pub fn genRandomRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk prng.random().float(f64); }");
}

/// Generate _random.Random.seed(n=None)
pub fn genSeed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _random.Random.getstate()
pub fn genGetstate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }");
}

/// Generate _random.Random.setstate(state)
pub fn genSetstate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _random.Random.getrandbits(k)
pub fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const k = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(prng.random().int(u64))); }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}
