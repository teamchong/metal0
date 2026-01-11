const std = @import("std");

pub const Decimal = struct {
    // Use string representation for exact decimal (like Python)
    value: []const u8,

    pub fn init(str: []const u8) Decimal {
        return .{ .value = str };
    }

    pub fn toFloat(self: Decimal) f64 {
        return std.fmt.parseFloat(f64, self.value) catch 0;
    }

    pub fn format(
        self: Decimal,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(self.value);
    }
};
