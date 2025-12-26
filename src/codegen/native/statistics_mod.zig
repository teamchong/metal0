/// Python statistics module - Mathematical statistics functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "mean", genMean }, .{ "fmean", genMean }, .{ "geometric_mean", genGeometricMean },
    .{ "harmonic_mean", genHarmonicMean }, .{ "median", genMedian }, .{ "median_low", genMedianLow },
    .{ "median_high", genMedianHigh }, .{ "median_grouped", genMedian }, .{ "mode", genMode },
    .{ "multimode", genMultimode }, .{ "pstdev", genPstdev }, .{ "pvariance", genPvariance },
    .{ "stdev", genStdev }, .{ "variance", genVariance },
    .{ "quantiles", h.c("&[_]f64{}") }, .{ "covariance", h.F64(0.0) },
    .{ "correlation", h.F64(0.0) }, .{ "linear_regression", h.c(".{ @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "NormalDist", genNormalDist }, .{ "StatisticsError", h.c("\"StatisticsError\"") },
});

fn emitStats(self: *NativeCodegen, args: []ast.Node, comptime label_suffix: []const u8, comptime default: []const u8, comptime body: []const u8) CodegenError!void {
    if (args.len == 0) {
        try self.emit(default);
        return;
    }
    const Ctx = struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} " ++ default ++ "; " ++ body ++ " ", .{label});
        }
    };
    try self.withInlineBlock(label_suffix, args, Ctx.emit);
}

fn emitVar(self: *NativeCodegen, args: []ast.Node, comptime label_suffix: []const u8, comptime min_len: []const u8, comptime divisor: []const u8, comptime is_sqrt: bool) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    const Ctx = struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len < " ++ min_len ++ ") break :{s} @as(f64, 0.0); var _sum: f64 = 0.0; for (_data) |v| _sum += @as(f64, @floatFromInt(v)); const _mean = _sum / @as(f64, @floatFromInt(_data.len)); var _sq_sum: f64 = 0.0; for (_data) |v| {{ const d = @as(f64, @floatFromInt(v)) - _mean; _sq_sum += d * d; }} break :{s}" ++ if (is_sqrt) " @sqrt(_sq_sum / @as(f64, @floatFromInt(_data.len" ++ divisor ++ ")));" else " _sq_sum / @as(f64, @floatFromInt(_data.len" ++ divisor ++ "));" ++ " ", .{ label, label });
        }
    };
    try self.withInlineBlock(label_suffix, args, Ctx.emit);
}

fn genMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    try self.withInlineBlock("stats_mean", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(f64, 0.0); var _sum: f64 = 0.0; for (_data) |v| _sum += @as(f64, @floatFromInt(v)); break :{s} _sum / @as(f64, @floatFromInt(_data.len)); ", .{ label, label });
        }
    }.emit);
}
fn genGeometricMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    try self.withInlineBlock("stats_gmean", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(f64, 0.0); var _prod: f64 = 1.0; for (_data) |v| _prod *= @as(f64, @floatFromInt(v)); break :{s} std.math.pow(f64, _prod, 1.0 / @as(f64, @floatFromInt(_data.len))); ", .{ label, label });
        }
    }.emit);
}
fn genHarmonicMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    try self.withInlineBlock("stats_hmean", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(f64, 0.0); var _sum: f64 = 0.0; for (_data) |v| {{ const fv = @as(f64, @floatFromInt(v)); if (fv != 0) _sum += 1.0 / fv; }} break :{s} if (_sum != 0) @as(f64, @floatFromInt(_data.len)) / _sum else 0.0; ", .{ label, label });
        }
    }.emit);
}
fn genMedian(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    try self.withInlineBlock("stats_median", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(f64, 0.0); const _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :{s} @as(f64, 0.0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {{}}, struct {{ fn cmp(_: void, a1: i64, b1: i64) bool {{ return a1 < b1; }} }}.cmp); const _mid = _sorted.len / 2; break :{s} if (_sorted.len % 2 == 0) (@as(f64, @floatFromInt(_sorted[_mid - 1])) + @as(f64, @floatFromInt(_sorted[_mid]))) / 2.0 else @as(f64, @floatFromInt(_sorted[_mid])); ", .{ label, label, label });
        }
    }.emit);
}
fn genMedianLow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.withInlineBlock("stats_median_low", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(i64, 0); var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :{s} @as(i64, 0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {{}}, struct {{ fn cmp(_: void, a1: i64, b1: i64) bool {{ return a1 < b1; }} }}.cmp); break :{s} _sorted[(_sorted.len - 1) / 2]; ", .{ label, label, label });
        }
    }.emit);
}
fn genMedianHigh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.withInlineBlock("stats_median_high", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(i64, 0); var _sorted = __global_allocator.alloc(@TypeOf(_data[0]), _data.len) catch break :{s} @as(i64, 0); @memcpy(_sorted, _data); std.mem.sort(i64, _sorted, {{}}, struct {{ fn cmp(_: void, a1: i64, b1: i64) bool {{ return a1 < b1; }} }}.cmp); break :{s} _sorted[_sorted.len / 2]; ", .{ label, label, label });
        }
    }.emit);
}
fn genMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.withInlineBlock("stats_mode", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _data = &");
            try c.genExpr(a[0]);
            try c.emitFmt("; if (_data.len == 0) break :{s} @as(@TypeOf(_data[0]), undefined); break :{s} _data[0]; ", .{ label, label });
        }
    }.emit);
}
const genMultimode = h.wrap("&[_]@TypeOf(", "[0]){}", "&[_]i64{}");

fn genPstdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVar(self, args, "stats_pstdev", "1", "", true); }
fn genPvariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVar(self, args, "stats_pvar", "1", "", false); }
fn genStdev(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVar(self, args, "stats_stdev", "2", " - 1", true); }
fn genVariance(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try emitVar(self, args, "stats_var", "2", " - 1", false); }
const genNormalDist = h.c("struct { mu: f64 = 0.0, sigma: f64 = 1.0, pub fn mean(__self: @This()) f64 { return __self.mu; } pub fn median(__self: @This()) f64 { return __self.mu; } pub fn mode(__self: @This()) f64 { return __self.mu; } pub fn stdev(__self: @This()) f64 { return __self.sigma; } pub fn variance(__self: @This()) f64 { return __self.sigma * __self.sigma; } pub fn pdf(__self: @This(), x: f64) f64 { const z = (x - __self.mu) / __self.sigma; return @exp(-0.5 * z * z) / (__self.sigma * @sqrt(2.0 * std.math.pi)); } pub fn cdf(__self: @This(), x: f64) f64 { _ = x; return 0.5; } pub fn inv_cdf(__self: @This(), p: f64) f64 { _ = p; return 0.0; } pub fn overlap(__self: @This(), other: @This()) f64 { _ = other; return 0.0; } pub fn samples(__self: @This(), n: usize) []f64 { _ = n; return &[_]f64{}; } }{}");
