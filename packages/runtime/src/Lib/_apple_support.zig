/// _apple_support - Apple Platform Support
/// Mirrors cpython/Lib/_apple_support.py
///
/// Shared support utilities for Apple platforms (macOS, iOS, tvOS, watchOS).
/// Provides common functionality used by _osx_support and _ios_support.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on any Apple platform
pub const is_apple = builtin.os.tag == .macos or builtin.os.tag == .ios or
    builtin.os.tag == .tvos or builtin.os.tag == .watchos;

/// Check specific Apple platforms
pub const is_macos = builtin.os.tag == .macos;
pub const is_ios = builtin.os.tag == .ios;
pub const is_tvos = builtin.os.tag == .tvos;
pub const is_watchos = builtin.os.tag == .watchos;

/// Get platform name
pub fn getPlatformName() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "macOS",
        .ios => "iOS",
        .tvos => "tvOS",
        .watchos => "watchOS",
        else => "Unknown",
    };
}

// ============================================================================
// SDK and Version Information
// ============================================================================

/// Apple SDK version
pub const SdkVersion = struct {
    major: u32,
    minor: u32,
    patch: u32 = 0,

    pub fn format(
        self: SdkVersion,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }
};

/// Get minimum deployment target from environment or default
pub fn getDeploymentTarget() ?SdkVersion {
    if (!is_apple) return null;

    // Check environment variables for deployment target
    const env_var = switch (builtin.os.tag) {
        .macos => "MACOSX_DEPLOYMENT_TARGET",
        .ios => "IPHONEOS_DEPLOYMENT_TARGET",
        .tvos => "TVOS_DEPLOYMENT_TARGET",
        .watchos => "WATCHOS_DEPLOYMENT_TARGET",
        else => return null,
    };

    if (std.posix.getenv(env_var)) |target| {
        // Parse version string like "10.15" or "14.0"
        var parts = std.mem.splitScalar(u8, target, '.');
        var version = SdkVersion{ .major = 0, .minor = 0, .patch = 0 };

        if (parts.next()) |major_str| {
            version.major = std.fmt.parseInt(u32, major_str, 10) catch 0;
        }
        if (parts.next()) |minor_str| {
            version.minor = std.fmt.parseInt(u32, minor_str, 10) catch 0;
        }
        if (parts.next()) |patch_str| {
            version.patch = std.fmt.parseInt(u32, patch_str, 10) catch 0;
        }
        return version;
    }

    // Return sensible defaults
    return switch (builtin.os.tag) {
        .macos => SdkVersion{ .major = 10, .minor = 15, .patch = 0 },
        .ios => SdkVersion{ .major = 13, .minor = 0, .patch = 0 },
        .tvos => SdkVersion{ .major = 13, .minor = 0, .patch = 0 },
        .watchos => SdkVersion{ .major = 6, .minor = 0, .patch = 0 },
        else => null,
    };
}

/// Get SDK path from SDKROOT env or common locations
pub fn getSdkPath() ?[]const u8 {
    if (!is_apple) return null;

    // Check SDKROOT environment variable first
    if (std.posix.getenv("SDKROOT")) |sdk| {
        return sdk;
    }

    // Check common SDK paths
    const sdk_paths = switch (builtin.os.tag) {
        .macos => &[_][]const u8{
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk",
        },
        .ios => &[_][]const u8{
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk",
        },
        else => &[_][]const u8{},
    };

    for (sdk_paths) |path| {
        if (std.fs.cwd().access(path, .{})) |_| {
            return path;
        } else |_| {}
    }

    return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
}

// ============================================================================
// Framework Support
// ============================================================================

/// Framework search paths
pub const FrameworkPaths = struct {
    system: []const u8 = "/System/Library/Frameworks",
    library: []const u8 = "/Library/Frameworks",
    user: []const u8 = "~/Library/Frameworks",
};

/// Get framework search paths
pub fn getFrameworkPaths() FrameworkPaths {
    return .{};
}

/// Check if framework exists in standard locations
pub fn hasFramework(name: []const u8) bool {
    if (!is_apple) return false;

    // Check common framework paths
    const framework_dirs = [_][]const u8{
        "/System/Library/Frameworks",
        "/Library/Frameworks",
    };

    var path_buf: [512]u8 = undefined;
    for (framework_dirs) |dir| {
        const framework_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.framework", .{ dir, name }) catch continue;
        if (std.fs.cwd().access(framework_path, .{})) |_| {
            return true;
        } else |_| {}
    }

    return false;
}

/// Common Apple frameworks
pub const Framework = enum {
    Foundation,
    CoreFoundation,
    Security,
    SystemConfiguration,
    CoreServices,
    ApplicationServices,
    AppKit, // macOS only
    UIKit, // iOS/tvOS only
    WatchKit, // watchOS only

    pub fn getName(self: Framework) []const u8 {
        return @tagName(self);
    }

    pub fn isAvailable(self: Framework) bool {
        return switch (self) {
            .AppKit => is_macos,
            .UIKit => is_ios or is_tvos,
            .WatchKit => is_watchos,
            else => is_apple,
        };
    }
};

// ============================================================================
// Code Signing
// ============================================================================

/// Code signing info
pub const CodeSignInfo = struct {
    /// Is code signed
    is_signed: bool = false,
    /// Team identifier
    team_id: ?[]const u8 = null,
    /// Bundle identifier
    bundle_id: ?[]const u8 = null,
    /// Entitlements present
    has_entitlements: bool = false,
};

/// Get code signing information (stub)
pub fn getCodeSignInfo() CodeSignInfo {
    return .{};
}

/// Check if running in sandbox
pub fn isSandboxed() bool {
    if (!is_apple) return false;
    // Would check sandbox entitlements
    return false;
}

// ============================================================================
// Architecture Support
// ============================================================================

/// Apple Silicon detection
pub fn isAppleSilicon() bool {
    return builtin.cpu.arch == .aarch64 and is_apple;
}

/// Check if running under Rosetta 2
pub fn isRosetta() bool {
    if (!is_macos) return false;
    // Would check sysctl.proc_translated
    return false;
}

/// Get architecture name (Apple style)
pub fn getArchName() []const u8 {
    return switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        .x86 => "i386",
        else => @tagName(builtin.cpu.arch),
    };
}

// ============================================================================
// Compiler Detection
// ============================================================================

/// Clang compiler info
pub const ClangInfo = struct {
    version: ?[]const u8 = null,
    is_apple_clang: bool = false,
    supports_objc_arc: bool = true,
};

/// Get Apple Clang info
pub fn getClangInfo() ClangInfo {
    return .{
        .is_apple_clang = is_apple,
        .supports_objc_arc = true,
    };
}

// ============================================================================
// System Paths
// ============================================================================

/// Standard Apple paths
pub const ApplePaths = struct {
    /// Applications folder
    applications: []const u8 = "/Applications",
    /// Library folder
    library: []const u8 = "/Library",
    /// System folder
    system: []const u8 = "/System",
    /// User home template
    users: []const u8 = "/Users",
};

/// Get Apple system paths
pub fn getApplePaths() ApplePaths {
    return .{};
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _apple_support module
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

test "apple detection" {
    const result = is_apple;
    _ = result;
}

test "platform name" {
    const name = getPlatformName();
    try std.testing.expect(name.len > 0);
}

test "framework paths" {
    const paths = getFrameworkPaths();
    try std.testing.expect(paths.system.len > 0);
}

test "framework availability" {
    const foundation = Framework.Foundation;
    try std.testing.expectEqualStrings("Foundation", foundation.getName());
}

test "arch name" {
    const arch = getArchName();
    try std.testing.expect(arch.len > 0);
}

test "clang info" {
    const info = getClangInfo();
    try std.testing.expect(info.supports_objc_arc);
}

test "apple paths" {
    const paths = getApplePaths();
    try std.testing.expectEqualStrings("/Applications", paths.applications);
}

test "sdk version format" {
    const ver = SdkVersion{ .major = 14, .minor = 0, .patch = 0 };
    var buf: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{}", .{ver}) catch unreachable;
    try std.testing.expectEqualStrings("14.0.0", formatted);
}
