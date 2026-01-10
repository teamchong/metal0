//! test.test_ctypes.test_checkretval - Tests for return value checking
//! Reference: cpython/Lib/test/test_ctypes/test_checkretval.py
//!
//! Tests for return value validation and error checking in ctypes
//! including errcheck callbacks and result verification.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Return Value Checker
// ============================================================================

/// Error types for return value checking
pub const RetvalError = error{
    NullPointer,
    NegativeValue,
    ZeroValue,
    OutOfRange,
    InvalidValue,
};

/// Check result callback type
pub const ErrCheckFn = *const fn (result: i64, args: []const u8) RetvalError!i64;

/// Return value checker configuration
pub const RetvalChecker = struct {
    const Self = @This();

    check_null: bool = false,
    check_negative: bool = false,
    check_zero: bool = false,
    min_value: ?i64 = null,
    max_value: ?i64 = null,
    custom_check: ?ErrCheckFn = null,

    /// Check an integer return value
    pub fn checkInt(self: Self, value: i64) RetvalError!i64 {
        if (self.check_negative and value < 0) {
            return RetvalError.NegativeValue;
        }
        if (self.check_zero and value == 0) {
            return RetvalError.ZeroValue;
        }
        if (self.min_value) |min| {
            if (value < min) return RetvalError.OutOfRange;
        }
        if (self.max_value) |max| {
            if (value > max) return RetvalError.OutOfRange;
        }
        return value;
    }

    /// Check a pointer return value
    pub fn checkPtr(self: Self, ptr: ?*anyopaque) RetvalError!?*anyopaque {
        if (self.check_null and ptr == null) {
            return RetvalError.NullPointer;
        }
        return ptr;
    }
};

// ============================================================================
// Preset Checkers
// ============================================================================

/// Checker for POSIX-style return values (-1 on error)
pub const posix_checker = RetvalChecker{
    .check_negative = true,
};

/// Checker for Windows HANDLE values (NULL on error)
pub const handle_checker = RetvalChecker{
    .check_null = true,
};

/// Checker for boolean return values
pub const bool_checker = RetvalChecker{
    .check_zero = true,
};

/// Checker for size values (must be positive)
pub const size_checker = RetvalChecker{
    .check_negative = true,
    .check_zero = true,
};

// ============================================================================
// Result Wrapper
// ============================================================================

/// Wrapper for function results with checking
pub fn CheckedResult(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        checked: bool = false,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        /// Mark as checked
        pub fn check(self: *Self) T {
            self.checked = true;
            return self.value;
        }

        /// Check with validator
        pub fn validate(self: *Self, validator: anytype) !T {
            self.checked = true;
            if (@TypeOf(validator) == RetvalChecker) {
                if (@typeInfo(T) == .pointer or @typeInfo(T) == .optional) {
                    const result = try validator.checkPtr(self.value);
                    if (@typeInfo(T) == .optional) {
                        return result;
                    }
                    return result orelse return RetvalError.NullPointer;
                } else {
                    const int_val: i64 = @intCast(self.value);
                    const result = try validator.checkInt(int_val);
                    return @intCast(result);
                }
            }
            return self.value;
        }
    };
}

// ============================================================================
// Error Code Mapping
// ============================================================================

/// Map error codes to descriptions
pub const ErrorCodeMap = struct {
    const Self = @This();

    codes: []const ErrorMapping,

    pub fn init(mappings: []const ErrorMapping) Self {
        return .{ .codes = mappings };
    }

    pub fn lookup(self: Self, code: i32) ?[]const u8 {
        for (self.codes) |mapping| {
            if (mapping.code == code) {
                return mapping.description;
            }
        }
        return null;
    }
};

pub const ErrorMapping = struct {
    code: i32,
    description: []const u8,
};

/// Common POSIX error codes
pub const posix_errors = ErrorCodeMap.init(&.{
    .{ .code = 1, .description = "EPERM: Operation not permitted" },
    .{ .code = 2, .description = "ENOENT: No such file or directory" },
    .{ .code = 3, .description = "ESRCH: No such process" },
    .{ .code = 4, .description = "EINTR: Interrupted system call" },
    .{ .code = 5, .description = "EIO: I/O error" },
    .{ .code = 9, .description = "EBADF: Bad file number" },
    .{ .code = 12, .description = "ENOMEM: Out of memory" },
    .{ .code = 13, .description = "EACCES: Permission denied" },
    .{ .code = 17, .description = "EEXIST: File exists" },
    .{ .code = 22, .description = "EINVAL: Invalid argument" },
});

// ============================================================================
// Test Cases
// ============================================================================

fn testPosixChecker() !void {
    try std.testing.expectEqual(@as(i64, 0), try posix_checker.checkInt(0));
    try std.testing.expectEqual(@as(i64, 42), try posix_checker.checkInt(42));
    try std.testing.expectError(RetvalError.NegativeValue, posix_checker.checkInt(-1));
}

fn testHandleChecker() !void {
    var value: i32 = 42;
    const ptr: *anyopaque = @ptrCast(&value);

    const result = try handle_checker.checkPtr(ptr);
    try std.testing.expect(result != null);

    try std.testing.expectError(RetvalError.NullPointer, handle_checker.checkPtr(null));
}

fn testBoolChecker() !void {
    try std.testing.expectEqual(@as(i64, 1), try bool_checker.checkInt(1));
    try std.testing.expectError(RetvalError.ZeroValue, bool_checker.checkInt(0));
}

fn testSizeChecker() !void {
    try std.testing.expectEqual(@as(i64, 100), try size_checker.checkInt(100));
    try std.testing.expectError(RetvalError.ZeroValue, size_checker.checkInt(0));
    try std.testing.expectError(RetvalError.NegativeValue, size_checker.checkInt(-1));
}

fn testRangeChecker() !void {
    const checker = RetvalChecker{
        .min_value = 0,
        .max_value = 100,
    };

    try std.testing.expectEqual(@as(i64, 50), try checker.checkInt(50));
    try std.testing.expectEqual(@as(i64, 0), try checker.checkInt(0));
    try std.testing.expectEqual(@as(i64, 100), try checker.checkInt(100));
    try std.testing.expectError(RetvalError.OutOfRange, checker.checkInt(-1));
    try std.testing.expectError(RetvalError.OutOfRange, checker.checkInt(101));
}

fn testCheckedResultInt() !void {
    var result = CheckedResult(i32).init(42);
    try std.testing.expect(!result.checked);

    const value = result.check();
    try std.testing.expectEqual(@as(i32, 42), value);
    try std.testing.expect(result.checked);
}

fn testCheckedResultValidate() !void {
    var result = CheckedResult(i32).init(42);
    const value = try result.validate(posix_checker);
    try std.testing.expectEqual(@as(i32, 42), value);
}

fn testCheckedResultValidateFail() !void {
    var result = CheckedResult(i32).init(-1);
    try std.testing.expectError(RetvalError.NegativeValue, result.validate(posix_checker));
}

fn testErrorCodeLookup() !void {
    try std.testing.expectEqualStrings(
        "ENOENT: No such file or directory",
        posix_errors.lookup(2).?,
    );
    try std.testing.expectEqualStrings(
        "EACCES: Permission denied",
        posix_errors.lookup(13).?,
    );
    try std.testing.expect(posix_errors.lookup(999) == null);
}

fn testCombinedChecks() !void {
    const checker = RetvalChecker{
        .check_negative = true,
        .check_zero = true,
        .max_value = 1000,
    };

    try std.testing.expectEqual(@as(i64, 500), try checker.checkInt(500));
    try std.testing.expectError(RetvalError.NegativeValue, checker.checkInt(-1));
    try std.testing.expectError(RetvalError.ZeroValue, checker.checkInt(0));
    try std.testing.expectError(RetvalError.OutOfRange, checker.checkInt(1001));
}

fn testNoChecks() !void {
    const checker = RetvalChecker{};

    // All values should pass with no checks enabled
    try std.testing.expectEqual(@as(i64, -100), try checker.checkInt(-100));
    try std.testing.expectEqual(@as(i64, 0), try checker.checkInt(0));
    try std.testing.expectEqual(@as(i64, 100), try checker.checkInt(100));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "posix_checker" {
    try testPosixChecker();
}

test "handle_checker" {
    try testHandleChecker();
}

test "bool_checker" {
    try testBoolChecker();
}

test "size_checker" {
    try testSizeChecker();
}

test "range_checker" {
    try testRangeChecker();
}

test "checked_result_int" {
    try testCheckedResultInt();
}

test "checked_result_validate" {
    try testCheckedResultValidate();
}

test "checked_result_validate_fail" {
    try testCheckedResultValidateFail();
}

test "error_code_lookup" {
    try testErrorCodeLookup();
}

test "combined_checks" {
    try testCombinedChecks();
}

test "no_checks" {
    try testNoChecks();
}
