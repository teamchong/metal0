/// sys module - System-specific parameters and functions
/// CPython Reference: https://docs.python.org/3.12/library/sys.html
const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform / Version Information
// ============================================================================

/// Comptime platform detection (zero runtime cost)
pub const platform = switch (builtin.os.tag) {
    .macos => "darwin",
    .linux => "linux",
    .windows => "win32",
    else => "unknown",
};

/// Version info tuple (3, 12, 0)
pub const VersionInfo = struct {
    major: i32,
    minor: i32,
    micro: i32,
    releaselevel: []const u8 = "final",
    serial: i32 = 0,
};

pub const version_info = VersionInfo{
    .major = 3,
    .minor = 12,
    .micro = 0,
};

/// Python version string (like "3.12.0 (metal0)")
pub const version: []const u8 = "3.12.0 (metal0 - Ahead-of-Time Compiled Python)";

/// Implementation name
pub const implementation = struct {
    pub const name: []const u8 = "metal0";
    pub const version = version_info;
    pub const cache_tag: []const u8 = "metal0-312";
};

/// Byte order
pub const byteorder: []const u8 = if (builtin.cpu.arch.endian() == .little) "little" else "big";

// ============================================================================
// Command Line Arguments
// ============================================================================

/// Command-line arguments (set at startup)
pub var argv: [][]const u8 = &.{};

/// Path to the executable
pub var executable: []const u8 = "";

// ============================================================================
// Size Limits
// ============================================================================

/// Maximum size of various types
pub const maxsize: i64 = std.math.maxInt(i64);

/// Float information
pub const float_info = struct {
    pub const max: f64 = std.math.floatMax(f64);
    pub const min: f64 = std.math.floatMin(f64);
    pub const epsilon: f64 = std.math.floatEps(f64);
    pub const dig: i32 = 15;
    pub const mant_dig: i32 = 53;
    pub const max_exp: i32 = 1024;
    pub const min_exp: i32 = -1021;
    pub const max_10_exp: i32 = 308;
    pub const min_10_exp: i32 = -307;
    pub const radix: i32 = 2;
    pub const rounds: i32 = 1;
};

/// Int information
pub const int_info = struct {
    pub const bits_per_digit: i32 = 30;
    pub const sizeof_digit: i32 = 4;
    pub const default_max_str_digits: i32 = 4300;
    pub const str_digits_check_threshold: i32 = 640;
};

/// Hash information
pub const hash_info = struct {
    pub const width: i32 = 64;
    pub const modulus: i64 = (1 << 61) - 1;
    pub const inf: i64 = 314159;
    pub const nan: i64 = 0;
    pub const imag: i64 = 1000003;
    pub const algorithm: []const u8 = "siphash24";
    pub const hash_bits: i32 = 64;
    pub const seed_bits: i32 = 128;
};

// ============================================================================
// Exit / Control Functions
// ============================================================================

/// Exit the program with given code
pub fn exit(code: i32) noreturn {
    std.posix.exit(@intCast(code));
}

/// Recursion limit (Python compatibility - no effect in compiled code)
var recursion_limit: i64 = 1000;

pub fn getrecursionlimit() i64 {
    return recursion_limit;
}

pub fn setrecursionlimit(limit: i64) void {
    recursion_limit = limit;
}

// ============================================================================
// Integer String Conversion Limit (Python 3.11+ security feature)
// ============================================================================

/// Integer string conversion limit (0 = disabled, default = 4300)
/// This is a Python 3.11+ security feature to limit DoS attacks via huge int<->str conversions
var int_max_str_digits: i64 = 4300;

/// Get the current limit for integer string conversion
pub fn get_int_max_str_digits(_: std.mem.Allocator) !i64 {
    return int_max_str_digits;
}

/// Set the limit for integer string conversion (0 = disabled)
pub fn set_int_max_str_digits(_: std.mem.Allocator, n: i64) !i64 {
    int_max_str_digits = n;
    return n;
}

// ============================================================================
// Path / Modules (Stubs - static compilation)
// ============================================================================

/// Module search path (stub for compatibility)
pub var path: [][]const u8 = &.{};

/// Loaded modules (stub for compatibility)
pub var modules: ?*anyopaque = null;

// ============================================================================
// Standard I/O (Stubs - use runtime.builtins for actual I/O)
// ============================================================================

/// Standard input (stub)
pub const stdin = struct {
    pub fn read(_: []u8) !usize {
        return 0;
    }
};

/// Standard output (stub)
pub const stdout = struct {
    pub fn write(data: []const u8) !usize {
        const writer = std.io.getStdOut().writer();
        try writer.writeAll(data);
        return data.len;
    }
    pub fn flush() !void {}
};

/// Standard error (stub)
pub const stderr = struct {
    pub fn write(data: []const u8) !usize {
        const writer = std.io.getStdErr().writer();
        try writer.writeAll(data);
        return data.len;
    }
    pub fn flush() !void {}
};

// ============================================================================
// Intentional Stubs (Not applicable to AOT compilation)
// ============================================================================

/// Get reference count - NOT APPLICABLE (no reference counting in AOT)
pub fn getrefcount(_: anytype) i64 {
    return 1; // Always return 1 for compatibility
}

/// Intern a string - NOT APPLICABLE (static compilation)
pub fn intern(s: []const u8) []const u8 {
    return s; // Return as-is
}

/// Get size of object in bytes
pub fn getsizeof(_: anytype) i64 {
    return 0; // Size not trackable at runtime in AOT
}
