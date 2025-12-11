/// Conversion Functions
/// Time unit conversion utilities with rounding support

const constants = @import("constants.zig");
const types = @import("types.zig");

/// Convert seconds (f64) to nanoseconds (i64)
pub fn secondsToNanos(seconds: f64) !i64 {
    const scaled = seconds * @as(f64, @floatFromInt(constants.NS_PER_SEC));
    if (scaled > @as(f64, @floatFromInt(constants.TIME_MAX)) or scaled < @as(f64, @floatFromInt(constants.TIME_MIN))) {
        return error.Overflow;
    }
    return @intFromFloat(scaled);
}

/// Convert nanoseconds to seconds (f64)
pub fn nanosToSeconds(nanos: i64) f64 {
    return @as(f64, @floatFromInt(nanos)) / @as(f64, @floatFromInt(constants.NS_PER_SEC));
}

/// Convert nanoseconds to milliseconds
pub fn nanosToMillis(nanos: i64, round: types.RoundMode) i64 {
    return divRound(nanos, constants.NS_PER_MS, round);
}

/// Convert nanoseconds to microseconds
pub fn nanosToMicros(nanos: i64, round: types.RoundMode) i64 {
    return divRound(nanos, constants.NS_PER_US, round);
}

/// Convert milliseconds to nanoseconds
pub fn millisToNanos(millis: i64) !i64 {
    const result = @mulWithOverflow(millis, constants.NS_PER_MS);
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

/// Convert microseconds to nanoseconds
pub fn microsToNanos(micros: i64) !i64 {
    const result = @mulWithOverflow(micros, constants.NS_PER_US);
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

/// Division with rounding mode
fn divRound(numerator: i64, denominator: i64, round: types.RoundMode) i64 {
    const quotient = @divFloor(numerator, denominator);
    const remainder = @mod(numerator, denominator);

    if (remainder == 0) return quotient;

    return switch (round) {
        .floor => quotient,
        .ceiling => quotient + 1,
        .down => if (numerator >= 0) quotient else quotient + 1,
        .up => if (numerator >= 0) quotient + 1 else quotient,
        .half_even => blk: {
            const half = @divFloor(denominator, 2);
            if (remainder > half) {
                break :blk quotient + 1;
            } else if (remainder < half) {
                break :blk quotient;
            } else {
                // Exactly half - round to even
                break :blk if (@mod(quotient, 2) == 0) quotient else quotient + 1;
            }
        },
    };
}
