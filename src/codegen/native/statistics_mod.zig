/// Python statistics module - Mathematical statistics functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "mean", genMean }, .{ "fmean", genFmean }, .{ "geometric_mean", genGeometricMean },
    .{ "harmonic_mean", genHarmonicMean }, .{ "median", genMedian }, .{ "median_low", genMedianLow },
    .{ "median_high", genMedianHigh }, .{ "median_grouped", genMedianGrouped }, .{ "mode", genMode },
    .{ "multimode", genMultimode }, .{ "pstdev", genPstdev }, .{ "pvariance", genPvariance },
    .{ "stdev", genStdev }, .{ "variance", genVariance }, .{ "quantiles", genQuantiles },
    .{ "covariance", genCovariance }, .{ "correlation", genCorrelation }, .{ "linear_regression", genLinearRegression },
    .{ "NormalDist", genNormalDist }, .{ "StatisticsError", genStatisticsError },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Inline block helper
fn emitStatsBlock(self: *NativeCodegen, args: []ast.Node, label: []const u8, default: []const u8, body: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit(default); return; }
    try self.emit(label); try self.emit(": { const _data = &"); try self.genExpr(args[0]); try self.emit("; ");
    try self.emit("if (_data.len == 0) break "); try self.emit(label); try self.emit(" "); try self.emit(default); try self.emit("; ");
    try self.emit(body); try self.emit(" }");
}

pub fn genMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_mean_blk", "@as(f64, 0.0)",
        "var _sum: f64 = 0.0; for (_data) |v| _sum += @as(f64, @floatFromInt(v)); break :stats_mean_blk _sum / @as(f64, @floatFromInt(_data.len));");
}

pub fn genFmean(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMean(self, args); }

pub fn genGeometricMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_gmean_blk", "@as(f64, 0.0)",
        "var _prod: f64 = 1.0; for (_data) |v| _prod *= @as(f64, @floatFromInt(v)); break :stats_gmean_blk std.math.pow(f64, _prod, 1.0 / @as(f64, @floatFromInt(_data.len)));");
}

pub fn genHarmonicMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_hmean_blk", "@as(f64, 0.0)",
        "var _sum: f64 = 0.0; for (_data) |v| { const fv = @as(f64, @floatFromInt(v)); if (fv != 0) _sum += 1.0 / fv; } break :stats_hmean_blk if (_sum != 0) @as(f64, @floatFromInt(_data.len)) / _sum else 0.0;");
}

pub fn genMedian(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_median_blk", "@as(f64, 0.0)",
        "const _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_blk @as(f64, 0.0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {}, struct { fn cmp(_: void, a: i64, b: i64) bool { return a < b; } }.cmp); const _mid = _sorted.len / 2; break :stats_median_blk if (_sorted.len % 2 == 0) (@as(f64, @floatFromInt(_sorted[_mid - 1])) + @as(f64, @floatFromInt(_sorted[_mid]))) / 2.0 else @as(f64, @floatFromInt(_sorted[_mid]));");
}

pub fn genMedianLow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_median_low_blk", "@as(i64, 0)",
        "var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_low_blk @as(i64, 0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {}, struct { fn cmp(_: void, a: i64, b: i64) bool { return a < b; } }.cmp); break :stats_median_low_blk _sorted[(_sorted.len - 1) / 2];");
}

pub fn genMedianHigh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitStatsBlock(self, args, "stats_median_high_blk", "@as(i64, 0)",
        "var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :stats_median_high_blk @as(i64, 0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {}, struct { fn cmp(_: void, a: i64, b: i64) bool { return a < b; } }.cmp); break :stats_median_high_blk _sorted[_sorted.len / 2];");
}

pub fn genMedianGrouped(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMedian(self, args); }

pub fn genMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("stats_mode_blk: { const _data = &"); try self.genExpr(args[0]); try self.emit("; ");
    try self.emit("if (_data.len == 0) break :stats_mode_blk @as(@TypeOf(_data[0]), undefined); break :stats_mode_blk _data[0]; }");
}

pub fn genMultimode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("&[_]i64{}"); return; }
    try self.emit("&[_]@TypeOf("); try self.genExpr(args[0]); try self.emit("[0]){}");
}

// Variance/stdev helper
fn emitVarianceBlock(self: *NativeCodegen, args: []ast.Node, label: []const u8, min_len: []const u8, divisor: []const u8, is_sqrt: bool) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(f64, 0.0)"); return; }
    try self.emit(label); try self.emit(": { const _data = &"); try self.genExpr(args[0]); try self.emit("; ");
    try self.emit("if (_data.len < "); try self.emit(min_len); try self.emit(") break "); try self.emit(label); try self.emit(" @as(f64, 0.0); ");
    try self.emit("var _sum: f64 = 0.0; for (_data) |v| _sum += @as(f64, @floatFromInt(v)); const _mean = _sum / @as(f64, @floatFromInt(_data.len)); var _sq_sum: f64 = 0.0; for (_data) |v| { const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; } break ");
    try self.emit(label);
    if (is_sqrt) {
        try self.emit(" @sqrt(_sq_sum / @as(f64, @floatFromInt(_data.len");
        try self.emit(divisor);
        try self.emit(")))");
    } else {
        try self.emit(" _sq_sum / @as(f64, @floatFromInt(_data.len");
        try self.emit(divisor);
        try self.emit("))");
    }
    try self.emit("; }");
}

pub fn genPstdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVarianceBlock(self, args, "stats_pstdev_blk", "1", "", true); }
pub fn genPvariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVarianceBlock(self, args, "stats_pvar_blk", "1", "", false); }
pub fn genStdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVarianceBlock(self, args, "stats_stdev_blk", "2", " - 1", true); }
pub fn genVariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVarianceBlock(self, args, "stats_var_blk", "2", " - 1", false); }

pub fn genQuantiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]f64{}"); }
pub fn genCovariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
pub fn genCorrelation(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
pub fn genLinearRegression(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(f64, 0.0), @as(f64, 0.0) }"); }

pub fn genNormalDist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { mu: f64 = 0.0, sigma: f64 = 1.0, pub fn mean(__self: @This()) f64 { return __self.mu; } pub fn median(__self: @This()) f64 { return __self.mu; } pub fn mode(__self: @This()) f64 { return __self.mu; } pub fn stdev(__self: @This()) f64 { return __self.sigma; } pub fn variance(__self: @This()) f64 { return __self.sigma * __self.sigma; } pub fn pdf(__self: @This(), x: f64) f64 { const z = (x - __self.mu) / __self.sigma; return @exp(-0.5 * z * z) / (__self.sigma * @sqrt(2.0 * std.math.pi)); } pub fn cdf(__self: @This(), x: f64) f64 { _ = x; return 0.5; } pub fn inv_cdf(__self: @This(), p: f64) f64 { _ = p; return 0.0; } pub fn overlap(__self: @This(), other: @This()) f64 { _ = other; return 0.0; } pub fn samples(__self: @This(), n: usize) []f64 { _ = n; return &[_]f64{}; } }{}");
}

pub fn genStatisticsError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"StatisticsError\""); }
