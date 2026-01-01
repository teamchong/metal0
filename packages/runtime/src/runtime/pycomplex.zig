/// Complex number type for Python semantics
const std = @import("std");

/// Complex number type
pub const PyComplex = struct {
    real: f64,
    imag: f64,

    pub fn create(real: f64, imag: f64) PyComplex {
        return .{ .real = real, .imag = imag };
    }

    pub fn fromValue(value: anytype) PyComplex {
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        return switch (info) {
            .int, .comptime_int => .{ .real = @floatFromInt(value), .imag = 0.0 },
            .float, .comptime_float => .{ .real = value, .imag = 0.0 },
            .bool => .{ .real = if (value) 1.0 else 0.0, .imag = 0.0 },
            .pointer => |ptr_info| blk: {
                // Handle class instances with __float__ or __complex__ method
                const ChildType = ptr_info.child;
                if (@typeInfo(ChildType) == .@"struct") {
                    // Prefer __complex__ if available
                    if (@hasDecl(ChildType, "__complex__")) {
                        const result = value.__complex__() catch break :blk .{ .real = 0.0, .imag = 0.0 };
                        break :blk result;
                    }
                    // Fall back to __float__ for Real/Rational/Integral types
                    if (@hasDecl(ChildType, "__float__")) {
                        const float_val = value.__float__() catch break :blk .{ .real = 0.0, .imag = 0.0 };
                        break :blk .{ .real = float_val, .imag = 0.0 };
                    }
                }
                break :blk .{ .real = 0.0, .imag = 0.0 };
            },
            else => .{ .real = 0.0, .imag = 0.0 },
        };
    }

    pub fn add(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }

    pub fn sub(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real - other.real, .imag = self.imag - other.imag };
    }

    pub fn mul(self: PyComplex, other: PyComplex) PyComplex {
        return .{
            .real = self.real * other.real - self.imag * other.imag,
            .imag = self.real * other.imag + self.imag * other.real,
        };
    }

    pub fn div(self: PyComplex, other: PyComplex) PyComplex {
        // (a + bi) / (c + di) = (ac + bd) / (c^2 + d^2) + ((bc - ad) / (c^2 + d^2))i
        const denom = other.real * other.real + other.imag * other.imag;
        return .{
            .real = (self.real * other.real + self.imag * other.imag) / denom,
            .imag = (self.imag * other.real - self.real * other.imag) / denom,
        };
    }

    /// Negation operator for PyComplex (-c)
    pub fn neg(self: PyComplex) PyComplex {
        return .{ .real = -self.real, .imag = -self.imag };
    }

    pub fn eql(self: PyComplex, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                const f: f64 = @floatFromInt(other);
                return self.real == f and self.imag == 0.0;
            },
            .float, .comptime_float => {
                return self.real == other and self.imag == 0.0;
            },
            .bool => {
                // complex(False) == False is True (both are "zero")
                const f: f64 = if (other) 1.0 else 0.0;
                return self.real == f and self.imag == 0.0;
            },
            .@"struct" => {
                if (T == PyComplex) {
                    return self.real == other.real and self.imag == other.imag;
                }
            },
            else => {},
        }
        return false;
    }
};
