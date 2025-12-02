/// Python random module - random number generation
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const prng = "var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _r = _prng.random(); ";
const randintBody = "); " ++ prng ++ "break :blk a + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(b - a + 1)))); }";
const sampleBody = "); " ++ prng ++ "var res: std.ArrayList(@TypeOf(seq[0])) = .{}; var idx: std.ArrayList(usize) = .{}; for (seq, 0..) |_, i| idx.append(__global_allocator, i) catch continue; _r.shuffle(usize, idx.items); for (idx.items[0..@min(k, idx.items.len)]) |i| res.append(__global_allocator, seq[i]) catch continue; break :blk res.items; }";
const uniformBody = "; " ++ prng ++ "const rv = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :blk a + (b - a) * rv; }";
const gaussBody = "; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :blk mu + sigma * @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); }";

pub const genRandint = h.wrap2("blk: { const a: i64 = @intCast(", "); const b: i64 = @intCast(", randintBody, "0");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "random", h.c("blk: { " ++ prng ++ "break :blk @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); }") },
    .{ "randint", genRandint },
    .{ "randrange", genRandrange },
    .{ "choice", h.wrap("blk: { const seq = ", "; " ++ prng ++ "break :blk seq[_r.int(usize) % seq.len]; }", "undefined") },
    .{ "choices", genChoices },
    .{ "shuffle", h.wrap("blk: { var seq = ", "; " ++ prng ++ "_r.shuffle(@TypeOf(seq[0]), seq); break :blk; }", "{}") },
    .{ "sample", h.wrap2("blk: { const seq = ", "; const k: usize = @intCast(", sampleBody, "&[_]i64{}") },
    .{ "uniform", h.wrap2("blk: { const a: f64 = ", "; const b: f64 = ", uniformBody, "0.0") },
    .{ "gauss", h.wrap2("blk: { const mu: f64 = ", "; const sigma: f64 = ", gaussBody, "0.0") },
    .{ "seed", h.c("{}") }, .{ "getstate", h.c(".{}") }, .{ "setstate", h.c("{}") },
    .{ "getrandbits", h.wrap("blk: { const k: u6 = @intCast(", "); " ++ prng ++ "break :blk @as(i64, @intCast(_r.int(u64) & ((@as(u64, 1) << k) - 1))); }", "0") },
});

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

fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const k: usize = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit("1");
    try self.emit("; " ++ prng ++ "var res: std.ArrayList(@TypeOf(seq[0])) = .{}; var i: usize = 0; while (i < k) : (i += 1) res.append(__global_allocator, seq[_prng.random().int(usize) % seq.len]) catch continue; break :blk res.items; }");
}
