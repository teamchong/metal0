/// getversion - Python Version Information
/// Mirrors cpython/Python/getversion.c
///
/// Returns the Python version string with build information

const std = @import("std");
const builtin = @import("builtin");
const getcompiler = @import("getcompiler.zig");

// ============================================================================
// Version Numbers
// ============================================================================

/// Python version we're compatible with
pub const PY_MAJOR_VERSION: u32 = 3;
pub const PY_MINOR_VERSION: u32 = 13;
pub const PY_MICRO_VERSION: u32 = 0;
pub const PY_RELEASE_LEVEL: []const u8 = "final";
pub const PY_RELEASE_SERIAL: u32 = 0;

/// Version as a single hex number: 0xMMmmpp00
pub const PY_VERSION_HEX: u32 = (PY_MAJOR_VERSION << 24) |
    (PY_MINOR_VERSION << 16) |
    (PY_MICRO_VERSION << 8) |
    0xF0; // 0xF0 = final

// ============================================================================
// Version Strings
// ============================================================================

/// Short version string "3.13.0"
pub const PY_VERSION: []const u8 = comptime std.fmt.comptimePrint(
    "{d}.{d}.{d}",
    .{ PY_MAJOR_VERSION, PY_MINOR_VERSION, PY_MICRO_VERSION },
);

/// Version with release level "3.13.0 (main)"
pub const PY_VERSION_FULL: []const u8 = PY_VERSION ++ " (" ++ PY_RELEASE_LEVEL ++ ")";

// ============================================================================
// Main Functions
// ============================================================================

/// Get the full version string
/// Format: "3.13.0 (main, date, time) \n[Compiler version]"
pub fn getVersion() []const u8 {
    return comptime blk: {
        const compiler = getcompiler.getCompiler();
        break :blk PY_VERSION_FULL ++ "\n" ++ compiler;
    };
}

/// Get just the version number string
pub fn getVersionNumber() []const u8 {
    return PY_VERSION;
}

/// Get major version
pub fn getMajor() u32 {
    return PY_MAJOR_VERSION;
}

/// Get minor version
pub fn getMinor() u32 {
    return PY_MINOR_VERSION;
}

/// Get micro version
pub fn getMicro() u32 {
    return PY_MICRO_VERSION;
}

/// Get version hex
pub fn getVersionHex() u32 {
    return PY_VERSION_HEX;
}

/// Get release level
pub fn getReleaseLevel() []const u8 {
    return PY_RELEASE_LEVEL;
}

/// Get release serial
pub fn getReleaseSerial() u32 {
    return PY_RELEASE_SERIAL;
}

// ============================================================================
// Version Info Tuple (for sys.version_info)
// ============================================================================

/// Release level as enum
pub const ReleaseLevel = enum(u8) {
    alpha = 0xA,
    beta = 0xB,
    candidate = 0xC,
    final = 0xF,
};

/// Version info structure (matches sys.version_info)
pub const VersionInfo = struct {
    major: u32,
    minor: u32,
    micro: u32,
    releaselevel: []const u8,
    serial: u32,

    pub fn format(
        self: VersionInfo,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("sys.version_info(major={d}, minor={d}, micro={d}, releaselevel='{s}', serial={d})", .{
            self.major, self.minor, self.micro, self.releaselevel, self.serial,
        });
    }
};

/// Get version info
pub fn getVersionInfo() VersionInfo {
    return .{
        .major = PY_MAJOR_VERSION,
        .minor = PY_MINOR_VERSION,
        .micro = PY_MICRO_VERSION,
        .releaselevel = PY_RELEASE_LEVEL,
        .serial = PY_RELEASE_SERIAL,
    };
}

// ============================================================================
// Version Comparison
// ============================================================================

/// Compare with a version tuple
pub fn isAtLeast(major: u32, minor: u32, micro: u32) bool {
    if (PY_MAJOR_VERSION > major) return true;
    if (PY_MAJOR_VERSION < major) return false;
    if (PY_MINOR_VERSION > minor) return true;
    if (PY_MINOR_VERSION < minor) return false;
    return PY_MICRO_VERSION >= micro;
}

/// Check if version matches major.minor
pub fn matchesMajorMinor(major: u32, minor: u32) bool {
    return PY_MAJOR_VERSION == major and PY_MINOR_VERSION == minor;
}

/// Check if Python 3.x
pub fn isPython3() bool {
    return PY_MAJOR_VERSION == 3;
}

/// Check specific Python 3.x version
pub fn isPython(major: u32, minor: u32) bool {
    return PY_MAJOR_VERSION == major and PY_MINOR_VERSION == minor;
}

// ============================================================================
// API Version
// ============================================================================

/// Python C API version (for extension modules)
pub const PYTHON_API_VERSION: u32 = 1013;

/// Get API version
pub fn getAPIVersion() u32 {
    return PYTHON_API_VERSION;
}

// ============================================================================
// Build Configuration
// ============================================================================

/// Get build date (compile time)
pub fn getBuildDate() []const u8 {
    // This would ideally use @compileLog or build system
    return "built with Zig";
}

/// Get build time
pub fn getBuildTime() []const u8 {
    return "";
}

/// Get git hash if available
pub fn getGitHash() ?[]const u8 {
    return null;
}

// ============================================================================
// Implementation Version
// ============================================================================

/// Implementation name (like CPython, PyPy, etc.)
pub const IMPLEMENTATION_NAME: []const u8 = "Metal0";

/// Get implementation name
pub fn getImplementationName() []const u8 {
    return IMPLEMENTATION_NAME;
}

/// Get implementation version (our version, not Python's)
pub const METAL0_VERSION: []const u8 = "0.1.0";

pub fn getImplementationVersion() []const u8 {
    return METAL0_VERSION;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "version string" {
    const version = getVersion();
    try std.testing.expect(version.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, version, "3.13") != null);
}

test "version number" {
    const num = getVersionNumber();
    try std.testing.expectEqualStrings("3.13.0", num);
}

test "version components" {
    try std.testing.expectEqual(@as(u32, 3), getMajor());
    try std.testing.expectEqual(@as(u32, 13), getMinor());
    try std.testing.expectEqual(@as(u32, 0), getMicro());
}

test "version hex" {
    const hex = getVersionHex();
    // 3.13.0 final = 0x030D00F0
    try std.testing.expectEqual(@as(u32, 0x030D00F0), hex);
}

test "version info" {
    const info = getVersionInfo();
    try std.testing.expectEqual(@as(u32, 3), info.major);
    try std.testing.expectEqual(@as(u32, 13), info.minor);
    try std.testing.expectEqualStrings("final", info.releaselevel);
}

test "version comparison" {
    try std.testing.expect(isAtLeast(3, 0, 0));
    try std.testing.expect(isAtLeast(3, 12, 0));
    try std.testing.expect(isAtLeast(3, 13, 0));
    try std.testing.expect(!isAtLeast(3, 14, 0));
    try std.testing.expect(!isAtLeast(4, 0, 0));
}

test "python version checks" {
    try std.testing.expect(isPython3());
    try std.testing.expect(isPython(3, 13));
    try std.testing.expect(!isPython(3, 12));
}

test "implementation" {
    try std.testing.expectEqualStrings("Metal0", getImplementationName());
}
