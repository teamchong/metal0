//! test.test_ctypes.test_parameters - Tests for parameter handling
//! Reference: cpython/Lib/test/test_ctypes/test_parameters.py
//!
//! Tests for ctypes function parameter type conversion and validation.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Parameter Types
// ============================================================================

pub const ParamType = enum {
    by_value,
    by_ref,
    by_out,
    by_inout,
};

pub const ParamInfo = struct {
    name: []const u8,
    type_name: []const u8,
    param_type: ParamType = .by_value,
    default_value: ?i64 = null,
};

// ============================================================================
// Parameter Conversion
// ============================================================================

/// Convert a Zig value to a C-compatible parameter
pub fn toParam(comptime T: type, value: anytype) T {
    const ValueType = @TypeOf(value);
    const value_info = @typeInfo(ValueType);
    const target_info = @typeInfo(T);

    // Integer to integer
    if (value_info == .int and target_info == .int) {
        return @intCast(value);
    }

    // Float to float
    if (value_info == .float and target_info == .float) {
        return @floatCast(value);
    }

    // Integer to float
    if (value_info == .int and target_info == .float) {
        return @floatFromInt(value);
    }

    // Float to integer
    if (value_info == .float and target_info == .int) {
        return @intFromFloat(value);
    }

    return value;
}

/// Convert a C value back to a Zig type
pub fn fromParam(comptime T: type, value: anytype) T {
    return toParam(T, value);
}

// ============================================================================
// Parameter Validation
// ============================================================================

pub const ValidationError = error{
    TypeMismatch,
    NullPointer,
    OutOfRange,
    InvalidValue,
};

/// Validate an integer parameter
pub fn validateInt(comptime T: type, value: anytype) ValidationError!T {
    const info = @typeInfo(T);
    if (info != .int) return ValidationError.TypeMismatch;

    const min = std.math.minInt(T);
    const max = std.math.maxInt(T);

    if (value < min or value > max) {
        return ValidationError.OutOfRange;
    }

    return @intCast(value);
}

/// Validate a pointer parameter
pub fn validatePtr(comptime T: type, ptr: ?*anyopaque) ValidationError!T {
    if (ptr == null) return ValidationError.NullPointer;
    return @ptrCast(@alignCast(ptr));
}

// ============================================================================
// Parameter Pack
// ============================================================================

pub fn ParamPack(comptime param_count: usize) type {
    return struct {
        const Self = @This();

        values: [param_count]i64 = [_]i64{0} ** param_count,
        types: [param_count][]const u8 = [_][]const u8{""} ** param_count,

        pub fn init() Self {
            return .{};
        }

        pub fn set(self: *Self, idx: usize, value: i64, type_name: []const u8) void {
            if (idx < param_count) {
                self.values[idx] = value;
                self.types[idx] = type_name;
            }
        }

        pub fn get(self: *const Self, idx: usize) ?i64 {
            if (idx >= param_count) return null;
            return self.values[idx];
        }

        pub fn count(_: *const Self) usize {
            return param_count;
        }
    };
}

// ============================================================================
// Output Parameters
// ============================================================================

pub fn OutParam(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T = std.mem.zeroes(T),
        is_set: bool = false,

        pub fn init() Self {
            return .{};
        }

        pub fn set(self: *Self, val: T) void {
            self.value = val;
            self.is_set = true;
        }

        pub fn get(self: *const Self) ?T {
            if (!self.is_set) return null;
            return self.value;
        }

        pub fn ptr(self: *Self) *T {
            return &self.value;
        }
    };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testToParamIntToInt() !void {
    const result = toParam(i32, @as(i64, 42));
    try std.testing.expectEqual(@as(i32, 42), result);
}

fn testToParamFloatToFloat() !void {
    const result = toParam(f32, @as(f64, 3.14));
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), result, 0.001);
}

fn testToParamIntToFloat() !void {
    const result = toParam(f64, @as(i32, 42));
    try std.testing.expectEqual(@as(f64, 42.0), result);
}

fn testToParamFloatToInt() !void {
    const result = toParam(i32, @as(f64, 42.9));
    try std.testing.expectEqual(@as(i32, 42), result);
}

fn testValidateIntSuccess() !void {
    const result = try validateInt(i8, @as(i32, 100));
    try std.testing.expectEqual(@as(i8, 100), result);
}

fn testValidateIntOutOfRange() !void {
    try std.testing.expectError(ValidationError.OutOfRange, validateInt(i8, @as(i32, 200)));
}

fn testValidatePtrSuccess() !void {
    var value: i32 = 42;
    const ptr: ?*anyopaque = @ptrCast(&value);
    const result = try validatePtr(*i32, ptr);
    try std.testing.expectEqual(@as(i32, 42), result.*);
}

fn testValidatePtrNull() !void {
    try std.testing.expectError(ValidationError.NullPointer, validatePtr(*i32, null));
}

fn testParamPack() !void {
    var pack = ParamPack(3).init();

    pack.set(0, 10, "int");
    pack.set(1, 20, "int");
    pack.set(2, 30, "int");

    try std.testing.expectEqual(@as(?i64, 10), pack.get(0));
    try std.testing.expectEqual(@as(?i64, 20), pack.get(1));
    try std.testing.expectEqual(@as(?i64, 30), pack.get(2));
    try std.testing.expectEqual(@as(usize, 3), pack.count());
}

fn testOutParam() !void {
    var out = OutParam(i32).init();

    try std.testing.expect(out.get() == null);

    out.set(42);
    try std.testing.expectEqual(@as(?i32, 42), out.get());
}

fn testOutParamPtr() !void {
    var out = OutParam(i32).init();
    const p = out.ptr();

    p.* = 100;
    out.is_set = true;

    try std.testing.expectEqual(@as(?i32, 100), out.get());
}

fn testParamInfo() !void {
    const info = ParamInfo{
        .name = "count",
        .type_name = "c_int",
        .param_type = .by_value,
        .default_value = 0,
    };

    try std.testing.expectEqualStrings("count", info.name);
    try std.testing.expectEqual(ParamType.by_value, info.param_type);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "to_param_int_to_int" {
    try testToParamIntToInt();
}

test "to_param_float_to_float" {
    try testToParamFloatToFloat();
}

test "to_param_int_to_float" {
    try testToParamIntToFloat();
}

test "to_param_float_to_int" {
    try testToParamFloatToInt();
}

test "validate_int_success" {
    try testValidateIntSuccess();
}

test "validate_int_out_of_range" {
    try testValidateIntOutOfRange();
}

test "validate_ptr_success" {
    try testValidatePtrSuccess();
}

test "validate_ptr_null" {
    try testValidatePtrNull();
}

test "param_pack" {
    try testParamPack();
}

test "out_param" {
    try testOutParam();
}

test "out_param_ptr" {
    try testOutParamPtr();
}

test "param_info" {
    try testParamInfo();
}
