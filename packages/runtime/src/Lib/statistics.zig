//! CPython source: Lib/statistics.py
//!
//! Provides functions for calculating mathematical statistics of numeric data.
//!
//! Mirrors: CPython Lib/statistics.py

const std = @import("std");

// ============================================================================
// Errors
// ============================================================================

pub const StatisticsError = error{
    EmptyData,
    NotEnoughData,
    InvalidWeights,
};

// ============================================================================
// Averages and measures of central location
// ============================================================================

/// Return the arithmetic mean of numeric data.
pub fn mean(comptime T: type, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    var sum: f64 = 0;
    for (data) |x| {
        sum += toFloat(x);
    }
    return sum / @as(f64, @floatFromInt(data.len));
}

/// Return the geometric mean of numeric data.
pub fn geometric_mean(comptime T: type, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    var log_sum: f64 = 0;
    for (data) |x| {
        const val = toFloat(x);
        if (val <= 0) return error.InvalidValue;
        log_sum += @log(val);
    }
    return @exp(log_sum / @as(f64, @floatFromInt(data.len)));
}

/// Return the harmonic mean of numeric data.
pub fn harmonic_mean(comptime T: type, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    var reciprocal_sum: f64 = 0;
    for (data) |x| {
        const val = toFloat(x);
        if (val <= 0) return error.InvalidValue;
        reciprocal_sum += 1.0 / val;
    }
    return @as(f64, @floatFromInt(data.len)) / reciprocal_sum;
}

/// Return the median (middle value) of numeric data.
pub fn median(comptime T: type, allocator: std.mem.Allocator, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    // Copy and sort
    var sorted = try allocator.alloc(f64, data.len);
    defer allocator.free(sorted);

    for (data, 0..) |x, i| {
        sorted[i] = toFloat(x);
    }
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

    const n = sorted.len;
    if (n % 2 == 1) {
        return sorted[n / 2];
    } else {
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0;
    }
}

/// Return the low median of numeric data.
pub fn median_low(comptime T: type, allocator: std.mem.Allocator, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    var sorted = try allocator.alloc(f64, data.len);
    defer allocator.free(sorted);

    for (data, 0..) |x, i| {
        sorted[i] = toFloat(x);
    }
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

    const n = sorted.len;
    if (n % 2 == 1) {
        return sorted[n / 2];
    } else {
        return sorted[n / 2 - 1];
    }
}

/// Return the high median of numeric data.
pub fn median_high(comptime T: type, allocator: std.mem.Allocator, data: []const T) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    var sorted = try allocator.alloc(f64, data.len);
    defer allocator.free(sorted);

    for (data, 0..) |x, i| {
        sorted[i] = toFloat(x);
    }
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

    return sorted[sorted.len / 2];
}

/// Return the most common data point.
pub fn mode(comptime T: type, data: []const T) !T {
    if (data.len == 0) return StatisticsError.EmptyData;

    // Count occurrences
    var max_count: usize = 0;
    var max_value: T = data[0];

    for (data) |candidate| {
        var count: usize = 0;
        for (data) |x| {
            if (x == candidate) count += 1;
        }
        if (count > max_count) {
            max_count = count;
            max_value = candidate;
        }
    }

    return max_value;
}

/// Return a list of the most frequently occurring values.
pub fn multimode(comptime T: type, allocator: std.mem.Allocator, data: []const T) ![]T {
    if (data.len == 0) return allocator.alloc(T, 0);

    // Count occurrences and find max count
    var max_count: usize = 0;

    for (data) |candidate| {
        var count: usize = 0;
        for (data) |x| {
            if (x == candidate) count += 1;
        }
        if (count > max_count) {
            max_count = count;
        }
    }

    // Collect all values with max count
    var modes: std.ArrayList(T) = .{};
    errdefer modes.deinit(allocator);

    for (data) |candidate| {
        var count: usize = 0;
        for (data) |x| {
            if (x == candidate) count += 1;
        }
        if (count == max_count) {
            // Check if already in modes
            var found = false;
            for (modes.items) |m| {
                if (m == candidate) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try modes.append(allocator, candidate);
            }
        }
    }

    return modes.toOwnedSlice(allocator);
}

// ============================================================================
// Measures of spread
// ============================================================================

/// Return the population variance of data.
pub fn pvariance(comptime T: type, data: []const T, mu_opt: ?f64) !f64 {
    if (data.len == 0) return StatisticsError.EmptyData;

    const mu = mu_opt orelse try mean(T, data);
    var ss: f64 = 0;
    for (data) |x| {
        const diff = toFloat(x) - mu;
        ss += diff * diff;
    }
    return ss / @as(f64, @floatFromInt(data.len));
}

/// Return the sample variance of data.
pub fn variance(comptime T: type, data: []const T, xbar_opt: ?f64) !f64 {
    if (data.len < 2) return StatisticsError.NotEnoughData;

    const xbar = xbar_opt orelse try mean(T, data);
    var ss: f64 = 0;
    for (data) |x| {
        const diff = toFloat(x) - xbar;
        ss += diff * diff;
    }
    return ss / @as(f64, @floatFromInt(data.len - 1));
}

/// Return the population standard deviation of data.
pub fn pstdev(comptime T: type, data: []const T, mu_opt: ?f64) !f64 {
    return @sqrt(try pvariance(T, data, mu_opt));
}

/// Return the sample standard deviation of data.
pub fn stdev(comptime T: type, data: []const T, xbar_opt: ?f64) !f64 {
    return @sqrt(try variance(T, data, xbar_opt));
}

// ============================================================================
// Quantiles
// ============================================================================

/// Divide data into n continuous intervals with equal probability.
pub fn quantiles(
    comptime T: type,
    allocator: std.mem.Allocator,
    data: []const T,
    n: usize,
) ![]f64 {
    if (data.len < 2) return StatisticsError.NotEnoughData;
    if (n < 1) return error.InvalidValue;

    // Sort data
    var sorted = try allocator.alloc(f64, data.len);
    defer allocator.free(sorted);

    for (data, 0..) |x, i| {
        sorted[i] = toFloat(x);
    }
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

    // Calculate cut points
    var result = try allocator.alloc(f64, n - 1);
    errdefer allocator.free(result);

    for (1..n) |i| {
        const m: f64 = @as(f64, @floatFromInt(i)) * @as(f64, @floatFromInt(data.len)) / @as(f64, @floatFromInt(n));
        const j: usize = @intFromFloat(@floor(m));
        const g = m - @as(f64, @floatFromInt(j));

        if (j >= sorted.len - 1) {
            result[i - 1] = sorted[sorted.len - 1];
        } else {
            result[i - 1] = sorted[j] * (1.0 - g) + sorted[j + 1] * g;
        }
    }

    return result;
}

// ============================================================================
// Correlation and regression
// ============================================================================

/// Return Pearson's correlation coefficient for two inputs.
pub fn correlation(comptime T: type, x: []const T, y: []const T) !f64 {
    if (x.len != y.len) return error.LengthMismatch;
    if (x.len < 2) return StatisticsError.NotEnoughData;

    const n = x.len;
    const mean_x = try mean(T, x);
    const mean_y = try mean(T, y);

    var numerator: f64 = 0;
    var sum_sq_x: f64 = 0;
    var sum_sq_y: f64 = 0;

    for (x, y) |xi, yi| {
        const dx = toFloat(xi) - mean_x;
        const dy = toFloat(yi) - mean_y;
        numerator += dx * dy;
        sum_sq_x += dx * dx;
        sum_sq_y += dy * dy;
    }

    const denominator = @sqrt(sum_sq_x * sum_sq_y);
    if (denominator == 0) return 0;

    return numerator / denominator;
}

/// Return the slope and intercept of simple linear regression.
pub fn linear_regression(comptime T: type, x: []const T, y: []const T) !struct { slope: f64, intercept: f64 } {
    if (x.len != y.len) return error.LengthMismatch;
    if (x.len < 2) return StatisticsError.NotEnoughData;

    const mean_x = try mean(T, x);
    const mean_y = try mean(T, y);

    var numerator: f64 = 0;
    var denominator: f64 = 0;

    for (x, y) |xi, yi| {
        const dx = toFloat(xi) - mean_x;
        numerator += dx * (toFloat(yi) - mean_y);
        denominator += dx * dx;
    }

    if (denominator == 0) return error.InvalidValue;

    const slope = numerator / denominator;
    const intercept = mean_y - slope * mean_x;

    return .{ .slope = slope, .intercept = intercept };
}

/// Return the covariance of two inputs.
pub fn covariance(comptime T: type, x: []const T, y: []const T) !f64 {
    if (x.len != y.len) return error.LengthMismatch;
    if (x.len < 2) return StatisticsError.NotEnoughData;

    const mean_x = try mean(T, x);
    const mean_y = try mean(T, y);

    var total: f64 = 0;
    for (x, y) |xi, yi| {
        total += (toFloat(xi) - mean_x) * (toFloat(yi) - mean_y);
    }

    return total / @as(f64, @floatFromInt(x.len - 1));
}

// ============================================================================
// Helper functions
// ============================================================================

fn toFloat(x: anytype) f64 {
    const T = @TypeOf(x);
    if (@typeInfo(T) == .float) {
        return @floatCast(x);
    } else if (@typeInfo(T) == .int) {
        return @floatFromInt(x);
    } else if (@typeInfo(T) == .comptime_int or @typeInfo(T) == .comptime_float) {
        return @as(f64, x);
    }
    return 0;
}

// ============================================================================
// Tests
// ============================================================================

test "mean" {
    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const result = try mean(f64, &data);
    try std.testing.expectApproxEqAbs(3.0, result, 0.001);
}

test "mean integers" {
    const data = [_]i32{ 1, 2, 3, 4, 5 };
    const result = try mean(i32, &data);
    try std.testing.expectApproxEqAbs(3.0, result, 0.001);
}

test "geometric_mean" {
    const data = [_]f64{ 1.0, 2.0, 4.0, 8.0 };
    const result = try geometric_mean(f64, &data);
    try std.testing.expectApproxEqAbs(2.828, result, 0.01);
}

test "harmonic_mean" {
    const data = [_]f64{ 2.5, 3.0, 10.0 };
    const result = try harmonic_mean(f64, &data);
    try std.testing.expectApproxEqAbs(3.6, result, 0.01);
}

test "median odd" {
    const allocator = std.testing.allocator;
    const data = [_]f64{ 1.0, 3.0, 5.0, 7.0, 9.0 };
    const result = try median(f64, allocator, &data);
    try std.testing.expectApproxEqAbs(5.0, result, 0.001);
}

test "median even" {
    const allocator = std.testing.allocator;
    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0 };
    const result = try median(f64, allocator, &data);
    try std.testing.expectApproxEqAbs(2.5, result, 0.001);
}

test "mode" {
    const data = [_]i32{ 1, 1, 2, 3, 3, 3, 4 };
    const result = try mode(i32, &data);
    try std.testing.expectEqual(@as(i32, 3), result);
}

test "variance" {
    const data = [_]f64{ 2.75, 1.75, 1.25, 0.25, 0.5, 1.25, 3.5 };
    const result = try variance(f64, &data, null);
    try std.testing.expectApproxEqAbs(1.372, result, 0.01);
}

test "stdev" {
    const data = [_]f64{ 1.5, 2.5, 2.5, 2.75, 3.25, 4.75 };
    const result = try stdev(f64, &data, null);
    try std.testing.expectApproxEqAbs(1.081, result, 0.01);
}

test "pvariance" {
    const data = [_]f64{ 0.0, 0.25, 0.25, 1.25, 1.5, 1.75, 2.75, 3.25 };
    const result = try pvariance(f64, &data, null);
    try std.testing.expectApproxEqAbs(1.25, result, 0.01);
}

test "pstdev" {
    const data = [_]f64{ 1.5, 2.5, 2.5, 2.75, 3.25, 4.75 };
    const result = try pstdev(f64, &data, null);
    try std.testing.expectApproxEqAbs(0.986, result, 0.01);
}

test "correlation" {
    const x = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const y = [_]f64{ 2.0, 4.0, 6.0, 8.0, 10.0 };
    const result = try correlation(f64, &x, &y);
    try std.testing.expectApproxEqAbs(1.0, result, 0.001);
}

test "linear_regression" {
    const x = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const y = [_]f64{ 3.0, 5.0, 7.0, 9.0, 11.0 };
    const result = try linear_regression(f64, &x, &y);
    try std.testing.expectApproxEqAbs(2.0, result.slope, 0.001);
    try std.testing.expectApproxEqAbs(1.0, result.intercept, 0.001);
}

test "quantiles" {
    const allocator = std.testing.allocator;
    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 };
    const q = try quantiles(f64, allocator, &data, 4);
    defer allocator.free(q);

    try std.testing.expectEqual(@as(usize, 3), q.len);
    try std.testing.expectApproxEqAbs(3.25, q[0], 0.1);
    try std.testing.expectApproxEqAbs(5.5, q[1], 0.1);
    try std.testing.expectApproxEqAbs(7.75, q[2], 0.1);
}
