/// Decimal type for fixed-point decimal arithmetic (Python's decimal module)
/// This is a simplified implementation using f64 for now
const std = @import("std");

pub const Decimal = struct {
    value: f64,

    pub fn create(value: f64) Decimal {
        return .{ .value = value };
    }

    pub fn fromString(s: []const u8) Decimal {
        return .{ .value = std.fmt.parseFloat(f64, s) catch 0 };
    }

    pub fn add(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value + other.value };
    }

    pub fn sub(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value - other.value };
    }

    pub fn mul(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value * other.value };
    }

    pub fn div(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value / other.value };
    }

    pub fn neg(self: Decimal) Decimal {
        return .{ .value = -self.value };
    }

    pub fn eql(self: Decimal, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return self.value == @as(f64, @floatFromInt(other)),
            .float, .comptime_float => return self.value == other,
            .@"struct" => {
                if (T == Decimal) {
                    return self.value == other.value;
                }
            },
            else => {},
        }
        return false;
    }
};
