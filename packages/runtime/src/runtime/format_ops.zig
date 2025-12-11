/// Format operations for Python str/repr/format
const std = @import("std");

/// Format mode for formatInt
pub const FormatMode = enum {
    hex_lower,
    hex_upper,
    octal,
    decimal,
};

/// Convert any numeric value (including bool) to a hex/octal formatted string
/// This is needed because Zig's {x} format doesn't support bool directly
/// Returns a stack-allocated formatted string (valid for the current scope)
pub fn formatInt(value: anytype, mode: FormatMode) []const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Convert to unsigned int for formatting
    const int_val: u64 = if (info == .bool)
        @as(u64, if (value) 1 else 0)
    else if (info == .int or info == .comptime_int)
        @as(u64, @intCast(if (value < 0) @as(i64, value) +% @as(i64, @bitCast(@as(u64, std.math.maxInt(u64)))) +% 1 else @as(i64, value)))
    else if (info == .float or info == .comptime_float)
        @as(u64, @intFromFloat(@abs(value)))
    else
        0;

    // Use thread-local buffer for result
    const S = struct {
        threadlocal var buf: [32]u8 = undefined;
    };

    const len = switch (mode) {
        .hex_lower => std.fmt.bufPrint(&S.buf, "{x}", .{int_val}) catch return "0",
        .hex_upper => std.fmt.bufPrint(&S.buf, "{X}", .{int_val}) catch return "0",
        .octal => std.fmt.bufPrint(&S.buf, "{o}", .{int_val}) catch return "0",
        .decimal => std.fmt.bufPrint(&S.buf, "{d}", .{int_val}) catch return "0",
    };
    return len;
}
