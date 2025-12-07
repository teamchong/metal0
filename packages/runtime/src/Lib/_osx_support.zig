/// _osx_support - macOS/OS X Platform Support
/// Mirrors cpython/Lib/_osx_support.py
///
/// Platform-specific support for macOS (formerly OS X / Mac OS X).
/// Used by distutils and sysconfig for compiler/SDK configuration.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on macOS
pub const is_macos = builtin.os.tag == .macos;

/// macOS marketing names
pub fn getMacOSName(major: u32, minor: u32) []const u8 {
    if (major >= 14) return "Sonoma";
    if (major >= 13) return "Ventura";
    if (major >= 12) return "Monterey";
    if (major >= 11) return "Big Sur";
    if (major == 10) {
        return switch (minor) {
            15 => "Catalina",
            14 => "Mojave",
            13 => "High Sierra",
            12 => "Sierra",
            11 => "El Capitan",
            10 => "Yosemite",
            9 => "Mavericks",
            else => "Mac OS X",
        };
    }
    return "macOS";
}

// ============================================================================
// macOS Version
// ============================================================================

/// macOS version info
pub const MacOSVersion = struct {
    major: u32,
    minor: u32,
    patch: u32 = 0,

    pub fn getName(self: MacOSVersion) []const u8 {
        return getMacOSName(self.major, self.minor);
    }

    pub fn isAtLeast(self: MacOSVersion, major: u32, minor: u32) bool {
        if (self.major > major) return true;
        if (self.major < major) return false;
        return self.minor >= minor;
    }
};

/// Get macOS version (stub on non-macOS)
pub fn getMacOSVersion() ?MacOSVersion {
    if (!is_macos) return null;
    // Would parse from sysctlbyname("kern.osrelease")
    // Darwin 23.x = macOS 14 (Sonoma)
    return MacOSVersion{ .major = 14, .minor = 0, .patch = 0 };
}

// ============================================================================
// Xcode and SDK
// ============================================================================

/// Xcode installation info
pub const XcodeInfo = struct {
    /// Xcode version
    version: ?[]const u8 = null,
    /// Xcode path
    path: ?[]const u8 = null,
    /// Command line tools path
    clt_path: ?[]const u8 = null,
    /// Selected SDK
    sdk_path: ?[]const u8 = null,
};

/// Get Xcode info (stub)
pub fn getXcodeInfo() XcodeInfo {
    if (!is_macos) return .{};
    return .{
        .path = "/Applications/Xcode.app",
        .clt_path = "/Library/Developer/CommandLineTools",
        .sdk_path = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
    };
}

/// Get SDK version from path
pub fn getSdkVersion(sdk_path: []const u8) ?[]const u8 {
    // Parse version from path like "MacOSX14.0.sdk"
    if (std.mem.indexOf(u8, sdk_path, "MacOSX")) |_| {
        // Would extract version number
        return "14.0";
    }
    return null;
}

/// Get developer directory
pub fn getDeveloperDir() ?[]const u8 {
    if (!is_macos) return null;
    // Would run `xcode-select -p`
    return "/Applications/Xcode.app/Contents/Developer";
}

// ============================================================================
// Compiler Configuration
// ============================================================================

/// Compiler flags for macOS builds
pub const CompilerFlags = struct {
    /// C compiler
    cc: []const u8 = "clang",
    /// C++ compiler
    cxx: []const u8 = "clang++",
    /// Objective-C compiler
    objc: []const u8 = "clang",
    /// Linker
    ld: []const u8 = "clang",
    /// Architecture flags
    arch_flags: []const u8 = "-arch arm64",
    /// SDK flags
    sdk_flags: []const u8 = "",
    /// Deployment target
    deployment_target: []const u8 = "10.15",
};

/// Get compiler configuration
pub fn getCompilerFlags() CompilerFlags {
    var flags = CompilerFlags{};
    if (builtin.cpu.arch == .aarch64) {
        flags.arch_flags = "-arch arm64";
    } else if (builtin.cpu.arch == .x86_64) {
        flags.arch_flags = "-arch x86_64";
    }
    return flags;
}

/// Get deployment target from environment
pub fn getDeploymentTarget() []const u8 {
    // Would check MACOSX_DEPLOYMENT_TARGET env var
    return "10.15";
}

// ============================================================================
// Universal Binaries
// ============================================================================

/// Universal binary architectures
pub const UniversalArch = enum {
    x86_64,
    arm64,
    i386, // Legacy
    ppc, // Legacy
    ppc64, // Legacy
};

/// Check if binary is universal
pub fn isUniversalBinary(path: []const u8) bool {
    _ = path;
    // Would check with `lipo -info`
    return false;
}

/// Get architectures in universal binary
pub fn getUniversalArchs(path: []const u8) []const UniversalArch {
    _ = path;
    return &[_]UniversalArch{};
}

// ============================================================================
// Library Paths
// ============================================================================

/// Library search paths
pub const LibraryPaths = struct {
    /// System library path
    system: []const u8 = "/usr/lib",
    /// Local library path
    local: []const u8 = "/usr/local/lib",
    /// Homebrew library path (Apple Silicon)
    homebrew_arm: []const u8 = "/opt/homebrew/lib",
    /// Homebrew library path (Intel)
    homebrew_intel: []const u8 = "/usr/local/lib",
};

/// Get library paths
pub fn getLibraryPaths() LibraryPaths {
    return .{};
}

/// Get Homebrew prefix
pub fn getHomebrewPrefix() []const u8 {
    if (builtin.cpu.arch == .aarch64) {
        return "/opt/homebrew";
    }
    return "/usr/local";
}

// ============================================================================
// System Integrity Protection
// ============================================================================

/// Check if SIP is enabled (stub)
pub fn isSIPEnabled() bool {
    if (!is_macos) return false;
    // Would check via csrutil status
    return true;
}

/// Check if running with reduced SIP
pub fn hasReducedSIP() bool {
    return false;
}

// ============================================================================
// Gatekeeper
// ============================================================================

/// Gatekeeper status
pub const GatekeeperStatus = enum {
    enabled,
    disabled,
    developer_id,
    unknown,
};

/// Get Gatekeeper status (stub)
pub fn getGatekeeperStatus() GatekeeperStatus {
    if (!is_macos) return .unknown;
    return .enabled;
}

// ============================================================================
// Bundle Support
// ============================================================================

/// App bundle info
pub const BundleInfo = struct {
    /// Bundle identifier
    identifier: ?[]const u8 = null,
    /// Bundle name
    name: ?[]const u8 = null,
    /// Bundle version
    version: ?[]const u8 = null,
    /// Minimum OS version
    min_os_version: ?[]const u8 = null,
};

/// Get bundle info (stub)
pub fn getBundleInfo(bundle_path: []const u8) BundleInfo {
    _ = bundle_path;
    return .{};
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _osx_support module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "macos detection" {
    const result = is_macos;
    _ = result;
}

test "macos name" {
    try std.testing.expectEqualStrings("Sonoma", getMacOSName(14, 0));
    try std.testing.expectEqualStrings("Ventura", getMacOSName(13, 0));
    try std.testing.expectEqualStrings("Catalina", getMacOSName(10, 15));
}

test "macos version" {
    const ver = MacOSVersion{ .major = 14, .minor = 0 };
    try std.testing.expect(ver.isAtLeast(13, 0));
    try std.testing.expect(ver.isAtLeast(14, 0));
    try std.testing.expect(!ver.isAtLeast(15, 0));
    try std.testing.expectEqualStrings("Sonoma", ver.getName());
}

test "compiler flags" {
    const flags = getCompilerFlags();
    try std.testing.expectEqualStrings("clang", flags.cc);
}

test "homebrew prefix" {
    const prefix = getHomebrewPrefix();
    try std.testing.expect(prefix.len > 0);
}

test "library paths" {
    const paths = getLibraryPaths();
    try std.testing.expectEqualStrings("/usr/lib", paths.system);
}

test "xcode info" {
    const info = getXcodeInfo();
    _ = info;
}

test "gatekeeper status" {
    const status = getGatekeeperStatus();
    _ = status;
}
