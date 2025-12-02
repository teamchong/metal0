/// Python random module - random number generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "random", genRandom }, .{ "randint", genRandint }, .{ "randrange", genRandrange },
    .{ "choice", genChoice }, .{ "choices", genChoices }, .{ "shuffle", genShuffle },
    .{ "sample", genSample }, .{ "uniform", genUniform }, .{ "gauss", genGauss },
    .{ "seed", genConst("{}") }, .{ "getstate", genConst(".{}") }, .{ "setstate", genConst("{}") }, .{ "getrandbits", genGetrandbits },
});

const prng = "var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _r = _prng.random(); ";

fn genRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { " ++ prng ++ "break :blk @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); }");
}

pub fn genRandint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const a: i64 = @intCast("); try self.genExpr(args[0]); try self.emit("); const b: i64 = @intCast("); try self.genExpr(args[1]);
    try self.emit("); " ++ prng ++ "break :blk a + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(b - a + 1)))); }");
}

pub fn genRandrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    if (args.len == 1) {
        try self.emit("blk: { const stop: i64 = @intCast("); try self.genExpr(args[0]);
        try self.emit("); " ++ prng ++ "break :blk @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(stop)))); }");
    } else {
        try self.emit("blk: { const start: i64 = @intCast("); try self.genExpr(args[0]); try self.emit("); const stop: i64 = @intCast("); try self.genExpr(args[1]);
        try self.emit("); " ++ prng ++ "break :blk start + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(stop - start)))); }");
    }
}

fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; " ++ prng ++ "break :blk seq[_r.int(usize) % seq.len]; }");
}

fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const k: usize = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit("1");
    try self.emit("; " ++ prng ++ "var res: std.ArrayList(@TypeOf(seq[0])) = .{}; var i: usize = 0; while (i < k) : (i += 1) res.append(__global_allocator, seq[_prng.random().int(usize) % seq.len]) catch continue; break :blk res.items; }");
}

fn genShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { var seq = "); try self.genExpr(args[0]); try self.emit("; " ++ prng ++ "_r.shuffle(@TypeOf(seq[0]), seq); break :blk; }");
}

fn genSample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const k: usize = @intCast("); try self.genExpr(args[1]);
    try self.emit("); " ++ prng ++ "var res: std.ArrayList(@TypeOf(seq[0])) = .{}; var idx: std.ArrayList(usize) = .{}; for (seq, 0..) |_, i| idx.append(__global_allocator, i) catch continue; _r.shuffle(usize, idx.items); for (idx.items[0..@min(k, idx.items.len)]) |i| res.append(__global_allocator, seq[i]) catch continue; break :blk res.items; }");
}

fn genUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const a: f64 = "); try self.genExpr(args[0]); try self.emit("; const b: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const rv = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :blk a + (b - a) * rv; }");
}

fn genGauss(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const mu: f64 = "); try self.genExpr(args[0]); try self.emit("; const sigma: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :blk mu + sigma * @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); }");
}

fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const k: u6 = @intCast("); try self.genExpr(args[0]); try self.emit("); " ++ prng ++ "break :blk @as(i64, @intCast(_r.int(u64) & ((@as(u64, 1) << k) - 1))); }");
}
