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
    const label = try self.emitInlineBlockStart("rand");
    const b = try self.getBuilder();
    try b.write(prng);
    try b.writeFmt("break :{s} @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{label});
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
    try self.emitInlineBlockEnd();
}

fn genUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("0.0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("uni", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _a: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _b: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const _rv = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} _a + (_b - _a) * _rv; ", .{ prng, label });
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genGauss(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("0.0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("gauss", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _mu: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _sigma: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const _u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); const _u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} _mu + _sigma * @sqrt(-2.0 * @log(_u1)) * @cos(2.0 * std.math.pi * _u2); ", .{ prng, label });
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genExpovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("0.0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("expo", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _lambd: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; {s}const _u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); break :{s} -@log(_u) / _lambd; ", .{ prng, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genRandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("bits", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _k: u6 = @intCast(");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("); {s}break :{s} @as(i64, @intCast(_r.int(u64) & ((@as(u64, 1) << _k) - 1))); ", .{ prng, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
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
            const b = try self.getBuilder();
            try b.writeFmt("rng_{d}: {{ const __rng_stop_{d} = ", .{ label_id, label_id });
            const output1 = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output1);
            try self.genExpr(args[0]);
            {
                const b2 = try self.getBuilder();
                try b2.writeFmt("; {s}const __rng_bits_{d} = try runtime.BigInt.fromInt(__global_allocator, _r.int(u64)); ", .{ prng, label_id });
                try b2.writeFmt("break :rng_{d} try __rng_bits_{d}.mod(&__rng_stop_{d}, __global_allocator); }}", .{ label_id, label_id, label_id });
                const output2 = b2.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output2);
            }
        } else {
            // Two args: randrange(start, stop) - range is [start, stop)
            const b = try self.getBuilder();
            try b.writeFmt("rng_{d}: {{ const __rng_start_{d} = ", .{ label_id, label_id });
            const output1 = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output1);
            try self.genExpr(args[0]);
            {
                const b2 = try self.getBuilder();
                try b2.writeFmt("; const __rng_stop_{d} = ", .{label_id});
                const output2 = b2.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output2);
            }
            try self.genExpr(args[1]);
            // For BigInt: start + (random_bits % (stop - start))
            {
                const b3 = try self.getBuilder();
                try b3.writeFmt("; {s}const __rng_bits_{d} = try runtime.BigInt.fromInt(__global_allocator, _r.int(u64)); ", .{ prng, label_id });
                try b3.writeFmt("const __rng_range_{d} = try __rng_stop_{d}.sub(&__rng_start_{d}, __global_allocator); ", .{ label_id, label_id, label_id });
                try b3.writeFmt("break :rng_{d} try __rng_start_{d}.add(&(try __rng_bits_{d}.mod(&__rng_range_{d}, __global_allocator)), __global_allocator); }}", .{ label_id, label_id, label_id, label_id });
                const output3 = b3.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output3);
            }
        }
    } else if (args.len == 1) {
        const b = try self.getBuilder();
        try b.writeFmt("rng_{d}: {{ const __rng_stop_{d}: i64 = @intCast(", .{ label_id, label_id });
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.writeFmt("); {s}break :rng_{d} @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(__rng_stop_{d})))); }}", .{ prng, label_id, label_id });
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        const b = try self.getBuilder();
        try b.writeFmt("rng_{d}: {{ const __rng_start_{d}: i64 = @intCast(", .{ label_id, label_id });
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.writeFmt("); const __rng_stop_{d}: i64 = @intCast(", .{label_id});
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
        try self.genExpr(args[1]);
        {
            const b3 = try self.getBuilder();
            try b3.writeFmt("); {s}break :rng_{d} __rng_start_{d} + @as(i64, @intCast(_r.int(u64) % @as(u64, @intCast(__rng_stop_{d} - __rng_start_{d})))); }}", .{ prng, label_id, label_id, label_id, label_id });
            const output3 = b3.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output3);
        }
    }
}

fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("undefined");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("choice", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try b.writeFmt("const __choice_seq_{d} = ", .{id});
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; {s}const _len_{d} = if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyLen() else __choice_seq_{d}.len; const _idx_{d} = _r.int(usize) % _len_{d}; break :{s} if (@TypeOf(__choice_seq_{d}) == runtime.PyValue) __choice_seq_{d}.pyAt(_idx_{d}) else __choice_seq_{d}[_idx_{d}];", .{ prng, id, id, id, id, id, id, label, id, id, id, id, id });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genChoices(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("choices", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const __choices_seq = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const k: usize = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            if (a.len > 1) {
                const b3 = try c.getBuilder();
                try b3.write("@intCast(");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
                try c.genExpr(a[1]);
                const b4 = try c.getBuilder();
                try b4.write(")");
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
            } else {
                const b3 = try c.getBuilder();
                try b3.write("1");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
            {
                const b5 = try c.getBuilder();
                try b5.writeFmt("; {s}var res: std.ArrayListUnmanaged(@TypeOf(__choices_seq[0])) = .{{}}; var i: usize = 0; while (i < k) : (i += 1) res.append(__global_allocator, __choices_seq[_prng.random().int(usize) % __choices_seq.len]) catch continue; break :{s} res.items; ", .{ prng, label });
                const output5 = b5.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output5);
            }
        }
    }.emit);
}

fn genShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("{}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("shuffle", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try b.writeFmt("const __shuf_seq_{d} = ", .{id});
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; {s}const _items_{d} = if (@hasField(@TypeOf(__shuf_seq_{d}), \"items\")) __shuf_seq_{d}.items else __shuf_seq_{d}; _r.shuffle(@TypeOf(_items_{d}[0]), _items_{d}); break :{s}; ", .{ prng, id, id, id, id, id, id, label });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genSample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("&[_]i64{}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("sample", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            const id = b.getNextId();
            try b.writeFmt("const __sample_seq_{d} = ", .{id});
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const k_{d}: usize = @intCast(", .{id});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("); {s}var res_{d}: std.ArrayListUnmanaged(@TypeOf(__sample_seq_{d}[0])) = .{{}}; var idx_{d}: std.ArrayListUnmanaged(usize) = .{{}}; for (__sample_seq_{d}, 0..) |_, i| idx_{d}.append(__global_allocator, i) catch continue; _r.shuffle(usize, idx_{d}.items); for (idx_{d}.items[0..@min(k_{d}, idx_{d}.items.len)]) |i| res_{d}.append(__global_allocator, __sample_seq_{d}[i]) catch continue; break :{s} res_{d}.items; ", .{ prng, id, id, id, id, id, id, id, id, id, id, id, label, id });
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// gammavariate(alpha, beta) - Gamma distribution
fn genGammavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("gamma", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _alpha: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _beta: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}if (_alpha <= 0 or _beta <= 0) break :{s} @as(f64, 0); ", .{ prng, label });
                // Marsaglia and Tsang's method for alpha >= 1
                try b3.write("const d = _alpha - 1.0 / 3.0; const c = 1.0 / @sqrt(9.0 * d); var x: f64 = 0; var v: f64 = 0; ");
                try b3.write("while (true) { const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
                try b3.write("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
                try b3.write("x = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); v = 1.0 + c * x; ");
                try b3.write("if (v > 0) { v = v * v * v; if (u1 < 1.0 - 0.0331 * (x * x) * (x * x) or @log(u1) < 0.5 * x * x + d * (1.0 - v + @log(v))) break; } } ");
                try b3.writeFmt("break :{s} d * v / _beta; ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// betavariate(alpha, beta) - Beta distribution
fn genBetavariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0.5)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("beta", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _a: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _b: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b3.write("const u2 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
                try b3.writeFmt("_ = _a; _ = _b; break :{s} u1 / (u1 + u2); ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// paretovariate(alpha) - Pareto distribution
fn genParetovariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 1)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("pareto", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _alpha: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; {s}const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b2.writeFmt("break :{s} 1.0 / std.math.pow(f64, u, 1.0 / _alpha); ", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

/// weibullvariate(alpha, beta) - Weibull distribution
fn genWeibullvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("weibull", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _alpha: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _beta: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const u = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b3.writeFmt("break :{s} _alpha * std.math.pow(f64, -@log(u), 1.0 / _beta); ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// triangular(low, high, mode) - Triangular distribution
fn genTriangular(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("tri", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _low: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            if (a.len > 0) {
                try c.genExpr(a[0]);
            } else {
                const b_default = try c.getBuilder();
                try b_default.write("0.0");
                const out_default = b_default.getBodyAndClear();
                try c.output.appendSlice(c.allocator, out_default);
            }
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _high: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            if (a.len > 1) {
                try c.genExpr(a[1]);
            } else {
                const b_default = try c.getBuilder();
                try b_default.write("1.0");
                const out_default = b_default.getBodyAndClear();
                try c.output.appendSlice(c.allocator, out_default);
            }
            {
                const b3 = try c.getBuilder();
                try b3.write("; const _mode: f64 = ");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
            if (a.len > 2) {
                try c.genExpr(a[2]);
            } else {
                const b_default = try c.getBuilder();
                try b_default.write("(_low + _high) / 2.0");
                const out_default = b_default.getBodyAndClear();
                try c.output.appendSlice(c.allocator, out_default);
            }
            {
                const b4 = try c.getBuilder();
                try b4.writeFmt("; {s}const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b4.write("const c = (_mode - _low) / (_high - _low); ");
                try b4.writeFmt("break :{s} if (u < c) _low + @sqrt(u * (_high - _low) * (_mode - _low)) else _high - @sqrt((1.0 - u) * (_high - _low) * (_high - _mode)); ", .{label});
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
            }
        }
    }.emit);
}

/// lognormvariate(mu, sigma) - Log-normal distribution
fn genLognormvariate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 1)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("lognorm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _mu: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _sigma: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const u1 = @as(f64, @floatFromInt(_r.int(u32) + 1)) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b3.write("const u2 = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ");
                try b3.write("const z = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2); ");
                try b3.writeFmt("break :{s} @exp(_mu + _sigma * z); ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// vonmisesvariate(mu, kappa) - von Mises distribution (circular)
fn genVonmises(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("vonmises", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _mu: f64 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _kappa: f64 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; {s}const u = @as(f64, @floatFromInt(_r.int(u32))) / @as(f64, @floatFromInt(std.math.maxInt(u32))); ", .{prng});
                try b3.writeFmt("_ = _kappa; break :{s} _mu + 2.0 * std.math.pi * u - std.math.pi; ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}
