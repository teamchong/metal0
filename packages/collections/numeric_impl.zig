const std = @import("std");

/// Generic numeric type implementation using comptime for code reduction.
/// Supports integers, floats, and complex numbers with conditional fields/methods.
pub fn NumericImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        /// Python object base (refcount, type)
        ob_base: PyObject,

        /// Real value (or real part for complex)
        value: Config.ValueType,

        /// Imaginary part (only exists for complex numbers via comptime!)
        imag: if (@hasDecl(Config, "is_complex") and Config.is_complex)
            Config.ValueType
        else
            void,

        /// Create new numeric value
        pub fn init(allocator: std.mem.Allocator, value: Config.ValueType) !*Self {
            const num = try allocator.create(Self);
            num.* = Self{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
                .value = value,
                .imag = if (@hasDecl(Config, "is_complex") and Config.is_complex) 0 else {},
            };
            return num;
        }

        /// Create complex number with real and imaginary parts
        pub fn initComplex(allocator: std.mem.Allocator, real: Config.ValueType, imag_val: Config.ValueType) !*Self {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex initialization");
                }
            }
            const num = try allocator.create(Self);
            num.* = Self{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
                .value = real,
                .imag = imag_val,
            };
            return num;
        }

        /// Free numeric value
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }

        /// Addition
        pub fn add(self: *Self, other: *Self) Config.ValueType {
            return self.value + other.value;
        }

        /// Addition for complex (returns real part, caller handles imag)
        pub fn addComplex(self: *Self, other: *Self) struct { real: Config.ValueType, imag: Config.ValueType } {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            return .{
                .real = self.value + other.value,
                .imag = self.imag + other.imag,
            };
        }

        /// Subtraction
        pub fn sub(self: *Self, other: *Self) Config.ValueType {
            return self.value - other.value;
        }

        /// Subtraction for complex
        pub fn subComplex(self: *Self, other: *Self) struct { real: Config.ValueType, imag: Config.ValueType } {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            return .{
                .real = self.value - other.value,
                .imag = self.imag - other.imag,
            };
        }

        /// Multiplication
        pub fn mul(self: *Self, other: *Self) Config.ValueType {
            return self.value * other.value;
        }

        /// Multiplication for complex: (a+bi)(c+di) = (ac-bd) + (ad+bc)i
        pub fn mulComplex(self: *Self, other: *Self) struct { real: Config.ValueType, imag: Config.ValueType } {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            const a = self.value;
            const b = self.imag;
            const c = other.value;
            const d = other.imag;
            return .{
                .real = a * c - b * d,
                .imag = a * d + b * c,
            };
        }

        /// Division (integer truncation for integers, float division for floats)
        pub fn div(self: *Self, other: *Self) Config.ValueType {
            if (@hasDecl(Config, "is_integer") and Config.is_integer) {
                return @divTrunc(self.value, other.value);
            } else {
                return self.value / other.value;
            }
        }

        /// Division for complex: (a+bi)/(c+di) = ((ac+bd) + (bc-ad)i) / (c²+d²)
        pub fn divComplex(self: *Self, other: *Self) struct { real: Config.ValueType, imag: Config.ValueType } {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            const a = self.value;
            const b = self.imag;
            const c = other.value;
            const d = other.imag;
            const denom = c * c + d * d;
            return .{
                .real = (a * c + b * d) / denom,
                .imag = (b * c - a * d) / denom,
            };
        }

        /// Modulo (integers only)
        pub fn mod(self: *Self, other: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support modulo (integers only)");
                }
            }
            return @rem(self.value, other.value);
        }

        /// Negation
        pub fn neg(self: *Self) Config.ValueType {
            return -self.value;
        }

        /// Negation for complex
        pub fn negComplex(self: *Self) struct { real: Config.ValueType, imag: Config.ValueType } {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            return .{
                .real = -self.value,
                .imag = -self.imag,
            };
        }

        /// Absolute value
        pub fn abs(self: *Self) Config.ValueType {
            if (@hasDecl(Config, "is_signed") and Config.is_signed) {
                return if (self.value < 0) -self.value else self.value;
            } else {
                return self.value;
            }
        }

        /// Absolute value for complex: sqrt(a² + b²)
        pub fn absComplex(self: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_complex") and Config.is_complex)) {
                    @compileError(Config.name ++ " doesn't support complex arithmetic");
                }
            }
            const a = self.value;
            const b = self.imag;
            return @sqrt(a * a + b * b);
        }

        /// Compare: returns -1 (less), 0 (equal), 1 (greater)
        pub fn compare(self: *Self, other: *Self) i8 {
            if (self.value < other.value) return -1;
            if (self.value > other.value) return 1;
            return 0;
        }

        /// Equality check
        pub fn eql(self: *Self, other: *Self) bool {
            if (@hasDecl(Config, "is_complex") and Config.is_complex) {
                return self.value == other.value and self.imag == other.imag;
            } else {
                return self.value == other.value;
            }
        }

        /// Hash value
        pub fn hash(self: *Self) u64 {
            if (@hasDecl(Config, "is_integer") and Config.is_integer) {
                return @as(u64, @bitCast(@as(i64, @intCast(self.value))));
            } else {
                return @as(u64, @bitCast(self.value));
            }
        }

        /// String conversion
        pub fn toString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
            if (@hasDecl(Config, "is_complex") and Config.is_complex) {
                if (self.imag >= 0) {
                    return std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ self.value, self.imag });
                } else {
                    return std.fmt.allocPrint(allocator, "({d}{d}j)", .{ self.value, self.imag });
                }
            } else if (@hasDecl(Config, "is_integer") and Config.is_integer) {
                return std.fmt.allocPrint(allocator, "{d}", .{self.value});
            } else {
                return std.fmt.allocPrint(allocator, "{d}", .{self.value});
            }
        }

        // Bitwise operations (integers only)

        /// Bitwise AND
        pub fn bitwiseAnd(self: *Self, other: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return self.value & other.value;
        }

        /// Bitwise OR
        pub fn bitwiseOr(self: *Self, other: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return self.value | other.value;
        }

        /// Bitwise XOR
        pub fn bitwiseXor(self: *Self, other: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return self.value ^ other.value;
        }

        /// Bitwise NOT
        pub fn bitwiseNot(self: *Self) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return ~self.value;
        }

        /// Left shift
        pub fn shiftLeft(self: *Self, bits: u6) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return self.value << bits;
        }

        /// Right shift
        pub fn shiftRight(self: *Self, bits: u6) Config.ValueType {
            comptime {
                if (!(@hasDecl(Config, "is_integer") and Config.is_integer)) {
                    @compileError(Config.name ++ " doesn't support bitwise operations");
                }
            }
            return self.value >> bits;
        }
    };
}

/// Minimal PyObject definition (will be replaced by real one from c_interop)
const PyObject = struct {
    ob_refcnt: i64,
    ob_type: ?*anyopaque,
};

// Tests

const testing = std.testing;

const PyInt64Config = struct {
    pub const ValueType = i64;
    pub const name = "int64";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: i64 = std.math.minInt(i64);
    pub const max_value: i64 = std.math.maxInt(i64);
};

const PyFloat64Config = struct {
    pub const ValueType = f64;
    pub const name = "float64";
    pub const is_integer = false;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: f64 = -std.math.inf(f64);
    pub const max_value: f64 = std.math.inf(f64);
};

const PyComplex128Config = struct {
    pub const ValueType = f64;
    pub const name = "complex128";
    pub const is_integer = false;
    pub const is_complex = true;
    pub const is_signed = true;
    pub const min_value: f64 = -std.math.inf(f64);
    pub const max_value: f64 = std.math.inf(f64);
};

test "NumericImpl - integer arithmetic" {
    const PyInt64 = NumericImpl(PyInt64Config);
    var a = try PyInt64.init(testing.allocator, 10);
    defer a.deinit(testing.allocator);

    var b = try PyInt64.init(testing.allocator, 5);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, 15), a.add(b));
    try testing.expectEqual(@as(i64, 5), a.sub(b));
    try testing.expectEqual(@as(i64, 50), a.mul(b));
    try testing.expectEqual(@as(i64, 2), a.div(b));
    try testing.expectEqual(@as(i64, 0), a.mod(b));
}

test "NumericImpl - float arithmetic" {
    const PyFloat64 = NumericImpl(PyFloat64Config);
    var a = try PyFloat64.init(testing.allocator, 10.5);
    defer a.deinit(testing.allocator);

    var b = try PyFloat64.init(testing.allocator, 2.5);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(f64, 13.0), a.add(b));
    try testing.expectEqual(@as(f64, 8.0), a.sub(b));
    try testing.expectEqual(@as(f64, 26.25), a.mul(b));
    try testing.expectApproxEqRel(@as(f64, 4.2), a.div(b), 0.0001);
}

test "NumericImpl - complex arithmetic" {
    const PyComplex128 = NumericImpl(PyComplex128Config);
    var a = try PyComplex128.initComplex(testing.allocator, 3.0, 4.0);
    defer a.deinit(testing.allocator);

    var b = try PyComplex128.initComplex(testing.allocator, 1.0, 2.0);
    defer b.deinit(testing.allocator);

    const sum = a.addComplex(b);
    try testing.expectEqual(@as(f64, 4.0), sum.real);
    try testing.expectEqual(@as(f64, 6.0), sum.imag);

    const diff = a.subComplex(b);
    try testing.expectEqual(@as(f64, 2.0), diff.real);
    try testing.expectEqual(@as(f64, 2.0), diff.imag);

    // (3+4i)(1+2i) = (3-8) + (6+4)i = -5 + 10i
    const prod = a.mulComplex(b);
    try testing.expectEqual(@as(f64, -5.0), prod.real);
    try testing.expectEqual(@as(f64, 10.0), prod.imag);
}

test "NumericImpl - bitwise operations" {
    const PyInt64 = NumericImpl(PyInt64Config);
    var a = try PyInt64.init(testing.allocator, 12);
    defer a.deinit(testing.allocator);

    var b = try PyInt64.init(testing.allocator, 5);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, 4), a.bitwiseAnd(b)); // 12 & 5 = 4
    try testing.expectEqual(@as(i64, 13), a.bitwiseOr(b)); // 12 | 5 = 13
    try testing.expectEqual(@as(i64, 9), a.bitwiseXor(b)); // 12 ^ 5 = 9
    try testing.expectEqual(@as(i64, ~@as(i64, 12)), a.bitwiseNot()); // ~12
    try testing.expectEqual(@as(i64, 24), a.shiftLeft(1)); // 12 << 1 = 24
    try testing.expectEqual(@as(i64, 6), a.shiftRight(1)); // 12 >> 1 = 6
}

test "NumericImpl - comparison" {
    const PyInt64 = NumericImpl(PyInt64Config);
    var a = try PyInt64.init(testing.allocator, 10);
    defer a.deinit(testing.allocator);

    var b = try PyInt64.init(testing.allocator, 5);
    defer b.deinit(testing.allocator);

    var c = try PyInt64.init(testing.allocator, 10);
    defer c.deinit(testing.allocator);

    try testing.expectEqual(@as(i8, 1), a.compare(b)); // 10 > 5
    try testing.expectEqual(@as(i8, 0), a.compare(c)); // 10 == 10
    try testing.expectEqual(@as(i8, -1), b.compare(a)); // 5 < 10

    try testing.expect(a.eql(c));
    try testing.expect(!a.eql(b));
}

test "NumericImpl - size optimization" {
    const PyInt64 = NumericImpl(PyInt64Config);
    const PyFloat64 = NumericImpl(PyFloat64Config);
    const PyComplex128 = NumericImpl(PyComplex128Config);

    const int_size = @sizeOf(PyInt64);
    const float_size = @sizeOf(PyFloat64);
    const complex_size = @sizeOf(PyComplex128);

    // Complex should be larger (has imag field)
    try testing.expect(complex_size > int_size);
    try testing.expect(complex_size > float_size);
}

test "NumericImpl - string conversion" {
    const PyInt64 = NumericImpl(PyInt64Config);
    const PyFloat64 = NumericImpl(PyFloat64Config);
    const PyComplex128 = NumericImpl(PyComplex128Config);

    var int_val = try PyInt64.init(testing.allocator, 42);
    defer int_val.deinit(testing.allocator);
    const int_str = try int_val.toString(testing.allocator);
    defer testing.allocator.free(int_str);
    try testing.expectEqualStrings("42", int_str);

    var float_val = try PyFloat64.init(testing.allocator, 3.14);
    defer float_val.deinit(testing.allocator);
    const float_str = try float_val.toString(testing.allocator);
    defer testing.allocator.free(float_str);
    try testing.expect(std.mem.startsWith(u8, float_str, "3.14"));

    var complex_val = try PyComplex128.initComplex(testing.allocator, 3.0, 4.0);
    defer complex_val.deinit(testing.allocator);
    const complex_str = try complex_val.toString(testing.allocator);
    defer testing.allocator.free(complex_str);
    try testing.expect(std.mem.indexOf(u8, complex_str, "3") != null);
    try testing.expect(std.mem.indexOf(u8, complex_str, "4") != null);
}
