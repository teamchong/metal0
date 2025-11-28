/// Python statistics module - Mathematical statistics functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate statistics.mean(data) -> arithmetic mean
pub fn genMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_mean_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_mean_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _sum += @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("break :stats_mean_blk _sum / @as(f64, @floatFromInt(_data.len));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.fmean(data, weights=None) -> fast floating point mean
pub fn genFmean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMean(self, args);
}

/// Generate statistics.geometric_mean(data) -> geometric mean
pub fn genGeometricMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_gmean_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_gmean_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _prod: f64 = 1.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _prod *= @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("break :stats_gmean_blk std.math.pow(f64, _prod, 1.0 / @as(f64, @floatFromInt(_data.len)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.harmonic_mean(data, weights=None) -> harmonic mean
pub fn genHarmonicMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_hmean_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_hmean_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| { const fv = @as(f64, @floatFromInt(v)); if (fv != 0) _sum += 1.0 / fv; }\n");
    try self.emitIndent();
    try self.emit("break :stats_hmean_blk if (_sum != 0) @as(f64, @floatFromInt(_data.len)) / _sum else 0.0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.median(data) -> median value
pub fn genMedian(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_median_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_median_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("@memcpy(_sorted, _data);\n");
    try self.emitIndent();
    try self.emit("std.mem.sort(@TypeOf(_data[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a < b; } }.cmp);\n");
    try self.emitIndent();
    try self.emit("const _mid = _sorted.len / 2;\n");
    try self.emitIndent();
    try self.emit("break :stats_median_blk if (_sorted.len % 2 == 0) (@as(f64, @floatFromInt(_sorted[_mid - 1])) + @as(f64, @floatFromInt(_sorted[_mid]))) / 2.0 else @as(f64, @floatFromInt(_sorted[_mid]));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.median_low(data) -> low median
pub fn genMedianLow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    try self.emit("stats_median_low_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_median_low_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_low_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("@memcpy(_sorted, _data);\n");
    try self.emitIndent();
    try self.emit("std.mem.sort(@TypeOf(_data[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a < b; } }.cmp);\n");
    try self.emitIndent();
    try self.emit("break :stats_median_low_blk _sorted[(_sorted.len - 1) / 2];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.median_high(data) -> high median
pub fn genMedianHigh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    try self.emit("stats_median_high_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_median_high_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_high_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("@memcpy(_sorted, _data);\n");
    try self.emitIndent();
    try self.emit("std.mem.sort(@TypeOf(_data[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a < b; } }.cmp);\n");
    try self.emitIndent();
    try self.emit("break :stats_median_high_blk _sorted[_sorted.len / 2];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.median_grouped(data, interval=1) -> grouped median
pub fn genMedianGrouped(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMedian(self, args);
}

/// Generate statistics.mode(data) -> most common value
pub fn genMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    try self.emit("stats_mode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_mode_blk @as(@TypeOf(_data[0]), undefined);\n");
    try self.emitIndent();
    try self.emit("break :stats_mode_blk _data[0];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.multimode(data) -> list of modes
pub fn genMultimode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("&[_]i64{}");
        return;
    }
    try self.emit("&[_]@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("[0]){}");
}

/// Generate statistics.pstdev(data, mu=None) -> population standard deviation
pub fn genPstdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_pstdev_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_pstdev_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _sum += @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("const _mean = _sum / @as(f64, @floatFromInt(_data.len));\n");
    try self.emitIndent();
    try self.emit("var _sq_sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| { const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; }\n");
    try self.emitIndent();
    try self.emit("break :stats_pstdev_blk @sqrt(_sq_sum / @as(f64, @floatFromInt(_data.len)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.pvariance(data, mu=None) -> population variance
pub fn genPvariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_pvar_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len == 0) break :stats_pvar_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _sum += @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("const _mean = _sum / @as(f64, @floatFromInt(_data.len));\n");
    try self.emitIndent();
    try self.emit("var _sq_sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| { const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; }\n");
    try self.emitIndent();
    try self.emit("break :stats_pvar_blk _sq_sum / @as(f64, @floatFromInt(_data.len));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.stdev(data, xbar=None) -> sample standard deviation
pub fn genStdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_stdev_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len < 2) break :stats_stdev_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _sum += @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("const _mean = _sum / @as(f64, @floatFromInt(_data.len));\n");
    try self.emitIndent();
    try self.emit("var _sq_sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| { const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; }\n");
    try self.emitIndent();
    try self.emit("break :stats_stdev_blk @sqrt(_sq_sum / @as(f64, @floatFromInt(_data.len - 1)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.variance(data, xbar=None) -> sample variance
pub fn genVariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    try self.emit("stats_var_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_data.len < 2) break :stats_var_blk @as(f64, 0.0);\n");
    try self.emitIndent();
    try self.emit("var _sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| _sum += @as(f64, @floatFromInt(v));\n");
    try self.emitIndent();
    try self.emit("const _mean = _sum / @as(f64, @floatFromInt(_data.len));\n");
    try self.emitIndent();
    try self.emit("var _sq_sum: f64 = 0.0;\n");
    try self.emitIndent();
    try self.emit("for (_data) |v| { const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; }\n");
    try self.emitIndent();
    try self.emit("break :stats_var_blk _sq_sum / @as(f64, @floatFromInt(_data.len - 1));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate statistics.quantiles(data, n=4, method='exclusive') -> quantiles
pub fn genQuantiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]f64{}");
}

/// Generate statistics.covariance(x, y) -> covariance
pub fn genCovariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate statistics.correlation(x, y) -> Pearson's correlation coefficient
pub fn genCorrelation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate statistics.linear_regression(x, y) -> (slope, intercept)
pub fn genLinearRegression(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate statistics.NormalDist(mu=0.0, sigma=1.0) -> normal distribution
pub fn genNormalDist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("mu: f64 = 0.0,\n");
    try self.emitIndent();
    try self.emit("sigma: f64 = 1.0,\n");
    try self.emitIndent();
    try self.emit("pub fn mean(self: @This()) f64 { return self.mu; }\n");
    try self.emitIndent();
    try self.emit("pub fn median(self: @This()) f64 { return self.mu; }\n");
    try self.emitIndent();
    try self.emit("pub fn mode(self: @This()) f64 { return self.mu; }\n");
    try self.emitIndent();
    try self.emit("pub fn stdev(self: @This()) f64 { return self.sigma; }\n");
    try self.emitIndent();
    try self.emit("pub fn variance(self: @This()) f64 { return self.sigma * self.sigma; }\n");
    try self.emitIndent();
    try self.emit("pub fn pdf(self: @This(), x: f64) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const z = (x - self.mu) / self.sigma;\n");
    try self.emitIndent();
    try self.emit("return @exp(-0.5 * z * z) / (self.sigma * @sqrt(2.0 * std.math.pi));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn cdf(self: @This(), x: f64) f64 { _ = self; _ = x; return 0.5; }\n");
    try self.emitIndent();
    try self.emit("pub fn inv_cdf(self: @This(), p: f64) f64 { _ = self; _ = p; return 0.0; }\n");
    try self.emitIndent();
    try self.emit("pub fn overlap(self: @This(), other: @This()) f64 { _ = self; _ = other; return 0.0; }\n");
    try self.emitIndent();
    try self.emit("pub fn samples(self: @This(), n: usize) []f64 { _ = self; _ = n; return &[_]f64{}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate statistics.StatisticsError exception
pub fn genStatisticsError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"StatisticsError\"");
}
