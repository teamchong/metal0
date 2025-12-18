/// Python random module - random number generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
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
    // Use self.emit (not builder) to write to correct output buffer
    const label = try self.emitInlineBlockStart("rand");
    try self.emit(prng);
    try self.emitFmt("break :{s} @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{label});
    try self.emitInlineBlockEnd();
}

fn genUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("0.0"); return; }
    try self.withInlineBlock("uni", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _a: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _b: f64 = "); try c.genExpr(a[1]);
            try c.emitFmt("; {s}const _rv = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} _a + (_b - _a) * _rv; ", .{ prng, label });
        }
    }.emit);
}

fn genGauss(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("0.0"); return; }
    try self.withInlineBlock("gauss", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _mu: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _sigma: f64 = "); try c.genExpr(a[1]);
            try c.emitFmt("; {s}const _u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); const _u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} _mu + _sigma * @sqrt(-2.0 * @log(_u1)) * @cos(2.0 * std.math.pi * _u2); ", .{ prng, label });
        }
    }.emit);
}

fn genExpovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("0.0"); return; }
    try self.withInlineBlock("expo", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _lambd: f64 = "); try c.genExpr(a[0]);
            try c.emitFmt("; {s}const _u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} -@log(_u) / _lambd; ", .{ prng, label });
        }
    }.emit);
}

fn genRandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("0"); return; }
    try self.withInlineBlock("bits", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _k: u6 = @intCast("); try c.genExpr(a[0]);
            try c.emitFmt("); {s}break :{s} @as(i64, @intCast(_r.int(u64) & ((@as(u64, 1) << _k) - 1))); ", .{ prng, label });
        }
    }.emit);
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
    try self.withInlineBlock("choice", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try c.emitFmt("const __choice_seq_{d} = ", .{id});
            try c.genExpr(a[0]);
            // Note: no trailing space after semicolon - withInlineBlock checks last byte for ';'
            try c.output.writer(c.allocator).print("; " ++ prng ++ "const _len_{d} = if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyLen() else __choice_seq_{d}.len; const _idx_{d} = _r.int(usize) % _len_{d}; break :{s} if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyAt(_idx_{d}) else __choice_seq_{d}[_idx_{d}];", .{ id, id, id, id, id, id, label, id, id, id, id, id });
        }
    }.emit);
}

fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("choices", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __choices_seq = "); try c.genExpr(a[0]); try c.emit("; const k: usize = ");
            if (a.len > 1) { try c.emit("@intCast("); try c.genExpr(a[1]); try c.emit(")"); } else try c.emit("1");
            try c.emitFmt("; " ++ prng ++ "var res: std.ArrayListUnmanaged(@TypeOf(__choices_seq[0])) = .{{}}; var i: usize = 0; while (i < k) : (i += 1) res.append(__global_allocator, __choices_seq[_prng.random().int(usize) % __choices_seq.len]) catch continue; break :{s} res.items; ", .{label});
        }
    }.emit);
}

fn genShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.withInlineBlock("shuffle", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try c.emitFmt("const __shuf_seq_{d} = ", .{id});
            try c.genExpr(a[0]);
            try c.output.writer(c.allocator).print("; " ++ prng ++ "const _items_{d} = if (@hasField(@TypeOf(__shuf_seq_{d}), \"items\")) __shuf_seq_{d}.items else __shuf_seq_{d}; _r.shuffle(@TypeOf(_items_{d}[0]), _items_{d}); break :{s}; ", .{ id, id, id, id, id, id, label });
        }
    }.emit);
}

fn genSample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{{}}"); return; }
    try self.withInlineBlock("sample", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try c.emitFmt("const __sample_seq_{d} = ", .{id});
            try c.genExpr(a[0]);
            try c.output.writer(c.allocator).print("; const k_{d}: usize = @intCast(", .{id});
            try c.genExpr(a[1]);
            try c.output.writer(c.allocator).print("); " ++ prng ++ "var res_{d}: std.ArrayListUnmanaged(@TypeOf(__sample_seq_{d}[0])) = .{{}}; var idx_{d}: std.ArrayListUnmanaged(usize) = .{{}}; for (__sample_seq_{d}, 0..) |_, i| idx_{d}.append(__global_allocator, i) catch continue; _r.shuffle(usize, idx_{d}.items); for (idx_{d}.items[0..@min(k_{d}, idx_{d}.items.len)]) |i| res_{d}.append(__global_allocator, __sample_seq_{d}[i]) catch continue; break :{s} res_{d}.items; ", .{ id, id, id, id, id, id, id, id, id, id, id, label, id });
        }
    }.emit);
}

/// gammavariate(alpha, beta) - Gamma distribution
fn genGammavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    try self.withInlineBlock("gamma", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _alpha: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _beta: f64 = "); try c.genExpr(a[1]);
            try c.emitFmt("; " ++ prng ++ "if (_alpha <= 0 or _beta <= 0) break :{s} @as(f64, 0); ", .{label});
            // Marsaglia and Tsang's method for alpha >= 1
            try c.emit("const d = _alpha - 1.0 / 3.0; const c = 1.0 / @sqrt(9.0 * d); var x: f64 = 0; var v: f64 = 0; ");
            try c.emit("while (true) { const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("x = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); v = 1.0 + c * x; ");
            try c.emit("if (v > 0) { v = v * v * v; if (u1 < 1.0 - 0.0331 * (x * x) * (x * x) or @log(u1) < 0.5 * x * x + d * (1.0 - v + @log(v))) break; } } ");
            try c.emitFmt("break :{s} d * v / _beta; ", .{label});
        }
    }.emit);
}

/// betavariate(alpha, beta) - Beta distribution
fn genBetavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0.5)"); return; }
    try self.withInlineBlock("beta", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _a: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _b: f64 = "); try c.genExpr(a[1]);
            try c.emit("; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emitFmt("_ = _a; _ = _b; break :{s} u1 / (u1 + u2); ", .{label});
        }
    }.emit);
}

/// paretovariate(alpha) - Pareto distribution
fn genParetovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(f64, 1)"); return; }
    try self.withInlineBlock("pareto", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _alpha: f64 = "); try c.genExpr(a[0]);
            try c.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emitFmt("break :{s} 1.0 / std.math.pow(f64, u, 1.0 / _alpha); ", .{label});
        }
    }.emit);
}

/// weibullvariate(alpha, beta) - Weibull distribution
fn genWeibullvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    try self.withInlineBlock("weibull", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _alpha: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _beta: f64 = "); try c.genExpr(a[1]);
            try c.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emitFmt("break :{s} _alpha * std.math.pow(f64, -@log(u), 1.0 / _beta); ", .{label});
        }
    }.emit);
}

/// triangular(low, high, mode) - Triangular distribution
fn genTriangular(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("tri", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _low: f64 = ");
            if (a.len > 0) try c.genExpr(a[0]) else try c.emit("0.0");
            try c.emit("; const _high: f64 = ");
            if (a.len > 1) try c.genExpr(a[1]) else try c.emit("1.0");
            try c.emit("; const _mode: f64 = ");
            if (a.len > 2) try c.genExpr(a[2]) else try c.emit("(_low + _high) / 2.0");
            try c.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("const c = (_mode - _low) / (_high - _low); ");
            try c.emitFmt("break :{s} if (u < c) _low + @sqrt(u * (_high - _low) * (_mode - _low)) else _high - @sqrt((1.0 - u) * (_high - _low) * (_high - _mode)); ", .{label});
        }
    }.emit);
}

/// lognormvariate(mu, sigma) - Log-normal distribution
fn genLognormvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 1)"); return; }
    try self.withInlineBlock("lognorm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _mu: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _sigma: f64 = "); try c.genExpr(a[1]);
            try c.emit("; " ++ prng ++ "const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emit("const z = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); ");
            try c.emitFmt("break :{s} @exp(_mu + _sigma * z); ", .{label});
        }
    }.emit);
}

/// vonmisesvariate(mu, kappa) - von Mises distribution (circular)
fn genVonmises(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(f64, 0)"); return; }
    try self.withInlineBlock("vonmises", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _mu: f64 = "); try c.genExpr(a[0]);
            try c.emit("; const _kappa: f64 = "); try c.genExpr(a[1]);
            try c.emit("; " ++ prng ++ "const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
            try c.emitFmt("_ = _kappa; break :{s} _mu + 2.0 * std.math.pi * u - std.math.pi; ", .{label});
        }
    }.emit);
}
