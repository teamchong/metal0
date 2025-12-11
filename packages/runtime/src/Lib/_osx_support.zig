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

/// Get macOS version by parsing kern.osrelease via sysctl
pub fn getMacOSVersion() ?MacOSVersion {
    if (!is_macos) return null;

    // Use std.c.sysctl to get kern.osrelease
    // Darwin kernel version maps to macOS: Darwin 23.x = macOS 14, 22.x = 13, etc.
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;

    // CTL_KERN = 1, KERN_OSRELEASE = 2
    var mib = [_]c_int{ 1, 2 };
    if (std.c.sysctl(&mib, mib.len, &buf, &len, null, 0) != 0) {
        // Fallback to default
        return MacOSVersion{ .major = 14, .minor = 0, .patch = 0 };
    }

    // Parse "23.1.0" format (Darwin version)
    const release = buf[0..len];
    var darwin_major: u32 = 0;
    var darwin_minor: u32 = 0;
    var darwin_patch: u32 = 0;

    var parts = std.mem.splitScalar(u8, release, '.');
    if (parts.next()) |major_str| {
        darwin_major = std.fmt.parseInt(u32, major_str, 10) catch 0;
    }
    if (parts.next()) |minor_str| {
        darwin_minor = std.fmt.parseInt(u32, minor_str, 10) catch 0;
    }
    if (parts.next()) |patch_str| {
        // Trim null terminator if present
        const trimmed = std.mem.trimRight(u8, patch_str, &[_]u8{0});
        darwin_patch = std.fmt.parseInt(u32, trimmed, 10) catch 0;
    }

    // Convert Darwin version to macOS version
    // Darwin 24 = macOS 15, Darwin 23 = macOS 14, Darwin 22 = macOS 13, etc.
    const macos_major: u32 = if (darwin_major >= 20) darwin_major - 9 else 10;
    const macos_minor: u32 = if (darwin_major >= 20) darwin_minor else darwin_major - 4;

    return MacOSVersion{
        .major = macos_major,
        .minor = macos_minor,
        .patch = darwin_patch,
    };
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

/// Get SDK version from path by parsing "MacOSX14.0.sdk" format
pub fn getSdkVersion(sdk_path: []const u8) ?[]const u8 {
    // Parse version from path like "/path/to/MacOSX14.0.sdk"
    const macosx_prefix = "MacOSX";
    if (std.mem.indexOf(u8, sdk_path, macosx_prefix)) |start| {
        const version_start = start + macosx_prefix.len;
        if (version_start >= sdk_path.len) return null;

        // Find end of version (at ".sdk")
        const remaining = sdk_path[version_start..];
        if (std.mem.indexOf(u8, remaining, ".sdk")) |end| {
            if (end > 0) {
                // Return pointer to static buffer for common versions
                const version = remaining[0..end];
                // Validate it looks like a version number
                for (version) |c| {
                    if (c != '.' and (c < '0' or c > '9')) return null;
                }
                return version;
            }
        }
    }
    return null;
}

/// Get developer directory from DEVELOPER_DIR env or xcode-select
pub fn getDeveloperDir() ?[]const u8 {
    if (!is_macos) return null;

    // Check DEVELOPER_DIR environment variable first
    if (std.posix.getenv("DEVELOPER_DIR")) |dir| {
        return dir;
    }

    // Check common paths
    const common_paths = [_][]const u8{
        "/Applications/Xcode.app/Contents/Developer",
        "/Library/Developer/CommandLineTools",
    };

    for (common_paths) |path| {
        if (std.fs.cwd().access(path, .{})) |_| {
            return path;
        } else |_| {}
    }

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

/// Get deployment target from MACOSX_DEPLOYMENT_TARGET environment variable
pub fn getDeploymentTarget() []const u8 {
    // Check MACOSX_DEPLOYMENT_TARGET env var
    if (std.posix.getenv("MACOSX_DEPLOYMENT_TARGET")) |target| {
        return target;
    }
    // Default to 10.15 Catalina (reasonable modern baseline)
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

/// Check if binary is universal by reading Mach-O header
pub fn isUniversalBinary(path: []const u8) bool {
    if (!is_macos) return false;

    // Open file and read magic number
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();

    var magic: [4]u8 = undefined;
    _ = file.read(&magic) catch return false;

    // FAT_MAGIC (0xcafebabe) or FAT_MAGIC_64 (0xcafebabf) indicates universal binary
    // Note: These are big-endian
    if (magic[0] == 0xca and magic[1] == 0xfe and magic[2] == 0xba and (magic[3] == 0xbe or magic[3] == 0xbf)) {
        return true;
    }

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

/// Check if SIP is enabled by checking for protected paths
pub fn isSIPEnabled() bool {
    if (!is_macos) return false;

    // SIP protects /System, /usr (except /usr/local), /bin, /sbin
    // If we can't write to these, SIP is likely enabled
    // We check by trying to access a known SIP-protected location

    // Check if /System/Library is read-only (SIP indicator)
    // A simpler check: if running on macOS 10.11+, SIP exists
    // We assume SIP is enabled by default as disabling requires recovery mode

    // Check for rootless boot arg (would indicate SIP disabled)
    // This is a simplified check - real implementation would use csr_check()
    if (std.fs.cwd().access("/System/Library/CoreServices", .{ .mode = .write_only })) |_| {
        // If we can write to /System, SIP is disabled
        return false;
    } else |_| {
        // Can't write = SIP enabled (normal case)
        return true;
    }
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
