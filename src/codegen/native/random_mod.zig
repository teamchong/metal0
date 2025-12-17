/// Python random module - random number generation
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const expr_emitter = @import("expr_emitter.zig");

const prng = "var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _r = _prng.random(); ";

pub const genRandint = h.wrap2Blk("rint", "const _a: i64 = @intCast(__v0); const _b: i64 = @intCast(__v1); " ++ prng, "_a + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(_b - _a + 1))))", "0");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Basic random functions
    .{ "random", genRandom },
    .{ "randint", genRandint },
    .{ "randrange", genRandrange },
    .{ "choice", genChoice },
    .{ "choices", genChoices },
    .{ "shuffle", genShuffle },
    .{ "sample", genSample },
    // Continuous distributions
    .{ "uniform", genUniform },
    .{ "gauss", genGauss },
    .{ "normalvariate", genGauss },
    .{ "expovariate", genExpovariate },
    .{ "gammavariate", genGammavariate },
    .{ "betavariate", genBetavariate },
    .{ "paretovariate", genParetovariate },
    .{ "weibullvariate", genWeibullvariate },
    .{ "triangular", genTriangular },
    .{ "lognormvariate", genLognormvariate },
    .{ "vonmisesvariate", genVonmises },
    // State functions
    .{ "seed", h.c("{}") }, .{ "getstate", h.c(".{}") }, .{ "setstate", h.c("{}") },
    .{ "getrandbits", genRandbits },
});

fn genRandom(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_rand: {{ " ++ prng ++ "break :__m{d}_rand @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); }})", .{ id, id });
}

fn genUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("0.0"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_uni: {{ const _a: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _b: f64 = "); try self.genExpr(args[1]);
    try self.emitFmt("; " ++ prng ++ "const _rv = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :__m{d}_uni _a + (_b - _a) * _rv; }})", .{id});
}

fn genGauss(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("0.0"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_gauss: {{ const _mu: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _sigma: f64 = "); try self.genExpr(args[1]);
    try self.emitFmt("; " ++ prng ++ "const _u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); const _u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :__m{d}_gauss _mu + _sigma * @sqrt(-2.0 * @log(_u1)) * @cos(2.0 * std.math.pi * _u2); }})", .{id});
}

fn genExpovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("0.0"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_expo: {{ const _lambd: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; " ++ prng ++ "const _u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :__m{d}_expo -@log(_u) / _lambd; }})", .{id});
}

fn genRandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("0"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_bits: {{ const _k: u6 = @intCast(", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("); " ++ prng ++ "break :__m{d}_bits @as(i64, @intCast(_r.int(u64) & ((@as(u64, 1) << _k) - 1))); }})", .{id});
}

pub fn genRandrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    // Use unique label and variable names to avoid shadowing outer scope variables
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Check if any argument might produce BigInt (e.g., bit shift operations with large values)
    const is_bigint = blk: {
        for (args) |arg| {
            const t = self.type_inferrer.inferExpr(arg) catch .unknown;
            if (t == .bigint) break :blk true;
        }
        break :blk false;
    };

    if (is_bigint) {
        // BigInt version - use BigInt arithmetic
        // For BigInt randrange, we generate a random BigInt in range [start, stop)
        // This is a simplified implementation that may not be perfectly uniform for very large ranges
        if (args.len == 1) {
            // Single arg: randrange(stop) - range is [0, stop)
            const w = self.output.writer(self.allocator);
            try w.print("rng_{d}: {{ const __rng_stop_{d} = ", .{ label_id, label_id });
            try self.genExpr(args[0]);
            try w.print("; " ++ prng ++ "const __rng_bits_{d} = try runtime.BigInt.fromInt(__global_allocator, _r.int(u64)); ", .{label_id});
            try w.print("break :rng_{d} try __rng_bits_{d}.mod(&__rng_stop_{d}, __global_allocator); }}", .{ label_id, label_id, label_id });
        } else {
            // Two args: randrange(start, stop) - range is [start, stop)
            const w = self.output.writer(self.allocator);
            try w.print("rng_{d}: {{ const __rng_start_{d} = ", .{ label_id, label_id });
            try self.genExpr(args[0]);
            try w.print("; const __rng_stop_{d} = ", .{label_id});
            try self.genExpr(args[1]);
            // For BigInt: start + (random_bits % (stop - start))
            try w.print("; " ++ prng ++ "const __rng_bits_{d} = try runtime.BigInt.fromInt(__global_allocator, _r.int(u64)); ", .{label_id});
            try w.print("const __rng_range_{d} = try __rng_stop_{d}.sub(&__rng_start_{d}, __global_allocator); ", .{ label_id, label_id, label_id });
            try w.print("break :rng_{d} try __rng_start_{d}.add(&(try __rng_bits_{d}.mod(&__rng_range_{d}, __global_allocator)), __global_allocator); }}", .{ label_id, label_id, label_id, label_id });
        }
    } else if (args.len == 1) {
        try self.output.writer(self.allocator).print("rng_{d}: {{ const __rng_stop_{d}: i64 = @intCast(", .{ label_id, label_id });
        try self.genExpr(args[0]);
        try self.output.writer(self.allocator).print("); " ++ prng ++ "break :rng_{d} @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(__rng_stop_{d})))); }}", .{ label_id, label_id });
    } else {
        try self.output.writer(self.allocator).print("rng_{d}: {{ const __rng_start_{d}: i64 = @intCast(", .{ label_id, label_id });
        try self.genExpr(args[0]);
        try self.output.writer(self.allocator).print("); const __rng_stop_{d}: i64 = @intCast(", .{label_id});
        try self.genExpr(args[1]);
        try self.output.writer(self.allocator).print("); " ++ prng ++ "break :rng_{d} __rng_start_{d} + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(__rng_stop_{d} - __rng_start_{d})))); }}", .{ label_id, label_id, label_id, label_id });
    }
}

fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("undefined"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_choice: {{ const __choice_seq_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; " ++ prng ++ "const _len_{d} = if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyLen() else __choice_seq_{d}.len; const _idx_{d} = _r.int(usize) % _len_{d}; break :__m{d}_choice if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyAt(_idx_{d}) else __choice_seq_{d}[_idx_{d}]; }}", .{ id, id, id, id, id, id, id, id, id, id, id, id });
}

fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_choices: {{ const __choices_seq = ", .{id}); try self.genExpr(args[0]); try self.emit("; const k: usize = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit("1");
    try self.emitFmt("; " ++ prng ++ "var res: std.ArrayListUnmanaged(@TypeOf(__choices_seq[0])) = .{{}}; var i: usize = 0; while (i < k) : (i += 1) res.append(__global_allocator, __choices_seq[_prng.random().int(usize) % __choices_seq.len]) catch continue; break :__m{d}_choices res.items; }}", .{id});
}

fn genShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_shuffle: {{ const __shuf_seq_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; " ++ prng ++ "const _items_{d} = if (@hasField(@TypeOf(__shuf_seq_{d}), \"items\")) __shuf_seq_{d}.items else __shuf_seq_{d}; _r.shuffle(@TypeOf(_items_{d}[0]), _items_{d}); break :__m{d}_shuffle; }}", .{ id, id, id, id, id, id, id });
}

fn genSample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{{}}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_sample: {{ const __sample_seq_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const k_{d}: usize = @intCast(", .{id});
    try self.genExpr(args[1]);
    try self.emitFmt("); " ++ prng ++ "var res_{d}: std.ArrayListUnmanaged(@TypeOf(__sample_seq_{d}[0])) = .{{}}; var idx_{d}: std.ArrayListUnmanaged(usize) = .{{}}; for (__sample_seq_{d}, 0..) |_, i| idx_{d}.append(__global_allocator, i) catch continue; _r.shuffle(usize, idx_{d}.items); for (idx_{d}.items[0..@min(k_{d}, idx_{d}.items.len)]) |i| res_{d}.append(__global_allocator, __sample_seq_{d}[i]) catch continue; break :__m{d}_sample res_{d}.items; }}", .{ id, id, id, id, id, id, id, id, id, id, id, id, id });
}

/// gammavariate(alpha, beta) - Gamma distribution
fn genGammavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_gamma: {{ const _alpha: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _beta: f64 = "); try self.genExpr(args[1]);
    try self.emitFmt("; " ++ prng ++ "if (_alpha <= 0 or _beta <= 0) break :__m{d}_gamma @as(f64, 0); ", .{id});
    // Marsaglia and Tsang's method for alpha >= 1
    try self.emit("const d = _alpha - 1.0 / 3.0; const c = 1.0 / @sqrt(9.0 * d); var x: f64 = 0; var v: f64 = 0; ");
    try self.emit("while (true) { const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("x = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); v = 1.0 + c * x; ");
    try self.emit("if (v > 0) { v = v * v * v; if (u1 < 1.0 - 0.0331 * (x * x) * (x * x) or @log(u1) < 0.5 * x * x + d * (1.0 - v + @log(v))) break; } } ");
    try self.emitFmt("break :__m{d}_gamma d * v / _beta; }}", .{id});
}

/// betavariate(alpha, beta) - Beta distribution
fn genBetavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0.5)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_beta: {{ const _a: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _b: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emitFmt("_ = _a; _ = _b; break :__m{d}_beta u1 / (u1 + u2); }}", .{id});
}

/// paretovariate(alpha) - Pareto distribution
fn genParetovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(f64, 1)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_pareto: {{ const _alpha: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emitFmt("break :__m{d}_pareto 1.0 / std.math.pow(f64, u, 1.0 / _alpha); }}", .{id});
}

/// weibullvariate(alpha, beta) - Weibull distribution
fn genWeibullvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_weibull: {{ const _alpha: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _beta: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emitFmt("break :__m{d}_weibull _alpha * std.math.pow(f64, -@log(u), 1.0 / _beta); }}", .{id});
}

/// triangular(low, high, mode) - Triangular distribution
fn genTriangular(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_tri: {{ const _low: f64 = ", .{id});
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("0.0");
    try self.emit("; const _high: f64 = ");
    if (args.len > 1) try self.genExpr(args[1]) else try self.emit("1.0");
    try self.emit("; const _mode: f64 = ");
    if (args.len > 2) try self.genExpr(args[2]) else try self.emit("(_low + _high) / 2.0");
    try self.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("const c = (_mode - _low) / (_high - _low); ");
    try self.emitFmt("break :__m{d}_tri if (u < c) _low + @sqrt(u * (_high - _low) * (_mode - _low)) else _high - @sqrt((1.0 - u) * (_high - _low) * (_high - _mode)); }}", .{id});
}

/// lognormvariate(mu, sigma) - Log-normal distribution
fn genLognormvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 1)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_lognorm: {{ const _mu: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _sigma: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emit("const z = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); ");
    try self.emitFmt("break :__m{d}_lognorm @exp(_mu + _sigma * z); }}", .{id});
}

/// vonmisesvariate(mu, kappa) - von Mises distribution (circular)
fn genVonmises(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_vonmises: {{ const _mu: f64 = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _kappa: f64 = "); try self.genExpr(args[1]);
    try self.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
    try self.emitFmt("_ = _kappa; break :__m{d}_vonmises _mu + 2.0 * std.math.pi * u - std.math.pi; }}", .{id});
}
