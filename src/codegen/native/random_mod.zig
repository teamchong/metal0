/// Python random module - random number generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "random", genRandom },
    .{ "randint", genRandint },
    .{ "randrange", genRandrange },
    .{ "choice", genChoice },
    .{ "choices", genChoices },
    .{ "shuffle", genShuffle },
    .{ "sample", genSample },
    .{ "uniform", genUniform },
    .{ "gauss", genGauss },
    .{ "seed", genSeed },
    .{ "getstate", genGetstate },
    .{ "setstate", genSetstate },
    .{ "getrandbits", genGetrandbits },
});

/// Generate random.random() -> float in [0.0, 1.0)
pub fn genRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("random_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("break :random_blk @as(f64, @floatFromInt(_rand.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.randint(a, b) -> int in [a, b]
pub fn genRandint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("randint_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _a: i64 = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("const _b: i64 = @intCast(");
    try self.genExpr(args[1]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("const _range: u64 = @intCast(_b - _a + 1);\n");
    try self.emitIndent();
    try self.emit("break :randint_blk _a + @as(i64, @intCast(_rand.int(u64) % _range));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.randrange(start, stop=None, step=1) -> int
pub fn genRandrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("randrange_blk: {\n");
    self.indent();
    try self.emitIndent();
    if (args.len == 1) {
        // randrange(stop) -> [0, stop)
        try self.emit("const _stop: i64 = @intCast(");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
        try self.emitIndent();
        try self.emit("const _rand = _prng.random();\n");
        try self.emitIndent();
        try self.emit("break :randrange_blk @as(i64, @intCast(_rand.int(u64) % @as(u64, @intCast(_stop))));\n");
    } else {
        // randrange(start, stop)
        try self.emit("const _start: i64 = @intCast(");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("const _stop: i64 = @intCast(");
        try self.genExpr(args[1]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
        try self.emitIndent();
        try self.emit("const _rand = _prng.random();\n");
        try self.emitIndent();
        try self.emit("const _range: u64 = @intCast(_stop - _start);\n");
        try self.emitIndent();
        try self.emit("break :randrange_blk _start + @as(i64, @intCast(_rand.int(u64) % _range));\n");
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.choice(seq) -> element
pub fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("choice_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _seq = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("const _idx = _rand.int(usize) % _seq.len;\n");
    try self.emitIndent();
    try self.emit("break :choice_blk _seq[_idx];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.choices(population, k=1) -> list
pub fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("choices_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _seq = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _k: usize = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("1");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(@TypeOf(_seq[0])) = .{};\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_i < _k) : (_i += 1) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _idx = _prng.random().int(usize) % _seq.len;\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _seq[_idx]) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :choices_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.shuffle(x) -> None (modifies in place)
pub fn genShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("shuffle_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _seq = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("_prng.random().shuffle(@TypeOf(_seq[0]), _seq);\n");
    try self.emitIndent();
    try self.emit("break :shuffle_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.sample(population, k) -> list
pub fn genSample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("sample_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _seq = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _k: usize = @intCast(");
    try self.genExpr(args[1]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(@TypeOf(_seq[0])) = .{};\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    // Simple reservoir sampling (without replacement)
    try self.emit("var _indices: std.ArrayList(usize) = .{};\n");
    try self.emitIndent();
    try self.emit("for (_seq, 0..) |_, idx| _indices.append(__global_allocator, idx) catch continue;\n");
    try self.emitIndent();
    try self.emit("_prng.random().shuffle(usize, _indices.items);\n");
    try self.emitIndent();
    try self.emit("for (_indices.items[0..@min(_k, _indices.items.len)]) |idx| _result.append(__global_allocator, _seq[idx]) catch continue;\n");
    try self.emitIndent();
    try self.emit("break :sample_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.uniform(a, b) -> float in [a, b)
pub fn genUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("uniform_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _a: f64 = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _b: f64 = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("const _r = @as(f64, @floatFromInt(_rand.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32)));\n");
    try self.emitIndent();
    try self.emit("break :uniform_blk _a + (_b - _a) * _r;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.gauss(mu, sigma) -> float with Gaussian distribution
pub fn genGauss(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("gauss_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _mu: f64 = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _sigma: f64 = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    // Box-Muller transform
    try self.emit("const _u1 = @as(f64, @floatFromInt(_rand.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32)));\n");
    try self.emitIndent();
    try self.emit("const _u2 = @as(f64, @floatFromInt(_rand.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32)));\n");
    try self.emitIndent();
    try self.emit("const _z = @sqrt(-2.0 * @log(_u1)) * @cos(2.0 * std.math.pi * _u2);\n");
    try self.emitIndent();
    try self.emit("break :gauss_blk _mu + _sigma * _z;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate random.seed(a=None) -> None
pub fn genSeed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Seed is handled implicitly by using time-based seed
    try self.emit("{}");
}

/// Generate random.getstate() -> state tuple
pub fn genGetstate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate random.setstate(state) -> None
pub fn genSetstate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate random.getrandbits(k) -> int with k random bits
pub fn genGetrandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("getrandbits_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _k: u6 = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("const _mask = (@as(u64, 1) << _k) - 1;\n");
    try self.emitIndent();
    try self.emit("break :getrandbits_blk @as(i64, @intCast(_rand.int(u64) & _mask));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
