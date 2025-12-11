/// version - Version Information and Platform Details
/// Python version, implementation, and platform information

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Version Information
// ============================================================================

/// Python version tuple (major, minor, micro, release, serial)
pub const version_info = struct {
    major: u32 = 3,
    minor: u32 = 12,
    micro: u32 = 0,
    releaselevel: []const u8 = "final",
    serial: u32 = 0,

    pub fn toTuple(self: @This()) struct { u32, u32, u32, []const u8, u32 } {
        return .{ self.major, self.minor, self.micro, self.releaselevel, self.serial };
    }
};

/// Version string
pub const version: []const u8 = "3.12.0 (metal0)";

/// Implementation info
pub const implementation = struct {
    name: []const u8 = "metal0",
    version: []const u8 = "0.1.0",
    cache_tag: []const u8 = "metal0-312",
    _multiarch: []const u8 = "",
};

// ============================================================================
// Platform Information
// ============================================================================

/// Platform identifier
pub const platform: []const u8 = switch (builtin.os.tag) {
    .linux => "linux",
    .macos => "darwin",
    .windows => "win32",
    .freebsd => "freebsd",
    .openbsd => "openbsd",
    .netbsd => "netbsd",
    else => "unknown",
};

/// Byte order
pub const byteorder: []const u8 = if (builtin.cpu.arch.endian() == .little) "little" else "big";

/// Maximum integer value for Py_ssize_t
pub const maxsize: i64 = std.math.maxInt(i64);

// ============================================================================
// Float and Number Information
// ============================================================================

/// Float information
pub const float_info = struct {
    max: f64 = std.math.floatMax(f64),
    max_exp: i32 = 1024,
    max_10_exp: i32 = 308,
    min: f64 = std.math.floatMin(f64),
    min_exp: i32 = -1021,
    min_10_exp: i32 = -307,
    dig: i32 = 15,
    mant_dig: i32 = 53,
    epsilon: f64 = std.math.floatEps(f64),
    radix: i32 = 2,
    rounds: i32 = 1, // Round to nearest
};

/// Int info
pub const int_info = struct {
    bits_per_digit: i32 = 30,
    sizeof_digit: i32 = 4,
    default_max_str_digits: i32 = 4300,
    str_digits_check_threshold: i32 = 640,
};

/// Hash info
pub const hash_info = struct {
    width: i32 = 64,
    modulus: i64 = (1 << 61) - 1, // 2^61 - 1 (Mersenne prime)
    inf: i64 = 314159,
    nan: i64 = 0,
    imag: i64 = 1000003,
    algorithm: []const u8 = "siphash24",
    hash_bits: i32 = 64,
    seed_bits: i32 = 128,
};

// ============================================================================
// Tests
// ============================================================================

test "version info" {
    const v = version_info{};
    try std.testing.expectEqual(@as(u32, 3), v.major);
    try std.testing.expectEqual(@as(u32, 12), v.minor);
}
