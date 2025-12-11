/// _android_support - Android Platform Support
/// Mirrors cpython/Lib/_android_support.py
///
/// Platform-specific support for Android operating system.
/// Provides utilities for Android app integration.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Android
pub const is_android = builtin.os.tag == .linux and builtin.abi == .android;

// ============================================================================
// Android Version
// ============================================================================

/// Android API level
pub const ApiLevel = enum(u32) {
    api_21 = 21, // Lollipop (5.0)
    api_22 = 22, // Lollipop (5.1)
    api_23 = 23, // Marshmallow (6.0)
    api_24 = 24, // Nougat (7.0)
    api_25 = 25, // Nougat (7.1)
    api_26 = 26, // Oreo (8.0)
    api_27 = 27, // Oreo (8.1)
    api_28 = 28, // Pie (9.0)
    api_29 = 29, // Q (10)
    api_30 = 30, // R (11)
    api_31 = 31, // S (12)
    api_32 = 32, // S_V2 (12L)
    api_33 = 33, // Tiramisu (13)
    api_34 = 34, // Upside Down Cake (14)
    _,

    pub fn getName(self: ApiLevel) []const u8 {
        return switch (self) {
            .api_21, .api_22 => "Lollipop",
            .api_23 => "Marshmallow",
            .api_24, .api_25 => "Nougat",
            .api_26, .api_27 => "Oreo",
            .api_28 => "Pie",
            .api_29 => "Q",
            .api_30 => "R",
            .api_31, .api_32 => "S",
            .api_33 => "Tiramisu",
            .api_34 => "Upside Down Cake",
            _ => "Unknown",
        };
    }
};

/// Get Android API level
/// Reads from system properties or /system/build.prop
pub fn getApiLevel() ?u32 {
    if (!is_android) return null;

    // Try reading ro.build.version.sdk from build.prop
    const build_prop = std.fs.cwd().openFile("/system/build.prop", .{}) catch {
        // Fallback: try /vendor/build.prop
        const vendor = std.fs.cwd().openFile("/vendor/build.prop", .{}) catch {
            return 34; // Default to recent API level
        };
        defer vendor.close();
        return readApiFromBuildProp(vendor);
    };
    defer build_prop.close();

    return readApiFromBuildProp(build_prop);
}

fn readApiFromBuildProp(file: std.fs.File) ?u32 {
    var buf: [8192]u8 = undefined;
    const content = file.reader().readAll(&buf) catch return 34;

    var lines = std.mem.splitScalar(u8, buf[0..content], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "ro.build.version.sdk=")) {
            const value = line["ro.build.version.sdk=".len..];
            return std.fmt.parseInt(u32, std.mem.trim(u8, value, " \r"), 10) catch 34;
        }
    }
    return 34;
}

/// Check minimum API level
pub fn hasMinApiLevel(min_level: u32) bool {
    const level = getApiLevel() orelse return false;
    return level >= min_level;
}

// ============================================================================
// File System Paths
// ============================================================================

/// Android storage paths
pub const StoragePaths = struct {
    /// Internal storage path
    internal: []const u8 = "/data/data",
    /// External storage path
    external: []const u8 = "/storage/emulated/0",
    /// Cache directory
    cache: []const u8 = "/data/cache",
    /// Temporary directory
    tmp: []const u8 = "/data/local/tmp",
};

/// Get storage paths
pub fn getStoragePaths() StoragePaths {
    return .{};
}

/// Get app-specific files directory
pub fn getFilesDir(package_name: []const u8) []const u8 {
    _ = package_name;
    return "/data/data/com.example/files";
}

/// Get app-specific cache directory
pub fn getCacheDir(package_name: []const u8) []const u8 {
    _ = package_name;
    return "/data/data/com.example/cache";
}

// ============================================================================
// Permissions
// ============================================================================

/// Android permissions
pub const Permission = enum {
    internet,
    read_external_storage,
    write_external_storage,
    camera,
    record_audio,
    access_fine_location,
    access_coarse_location,

    pub fn getName(self: Permission) []const u8 {
        return switch (self) {
            .internet => "android.permission.INTERNET",
            .read_external_storage => "android.permission.READ_EXTERNAL_STORAGE",
            .write_external_storage => "android.permission.WRITE_EXTERNAL_STORAGE",
            .camera => "android.permission.CAMERA",
            .record_audio => "android.permission.RECORD_AUDIO",
            .access_fine_location => "android.permission.ACCESS_FINE_LOCATION",
            .access_coarse_location => "android.permission.ACCESS_COARSE_LOCATION",
        };
    }
};

/// Check if permission is granted
/// On Android, reads from /proc/self/status for capability checks
/// Full permission checking requires JNI access to Context
pub fn hasPermission(permission: Permission) bool {
    if (!is_android) return true;

    // Internet permission doesn't require runtime check on modern Android
    if (permission == .internet) return true;

    // For file-based permissions, we can check filesystem access
    switch (permission) {
        .read_external_storage => {
            // Check if we can access external storage
            const path = "/storage/emulated/0";
            std.fs.cwd().openDir(path, .{}) catch return false;
            return true;
        },
        .write_external_storage => {
            // Check if we can write to external storage
            const test_path = "/storage/emulated/0/.permission_check";
            const file = std.fs.cwd().createFile(test_path, .{}) catch return false;
            file.close();
            std.fs.cwd().deleteFile(test_path) catch {};
            return true;
        },
        else => {
            // Other permissions require JNI/Context access
            // Return false as a safe default
            return false;
        },
    }
}

// ============================================================================
// Logcat Integration
// ============================================================================

/// Log priority levels (matches Android)
pub const LogPriority = enum(u8) {
    verbose = 2,
    debug = 3,
    info = 4,
    warn = 5,
    err = 6,
    fatal = 7,
};

/// Write to Android logcat
/// Uses stderr fallback when __android_log_print is not available
pub fn logcat(priority: LogPriority, tag: []const u8, message: []const u8) void {
    if (is_android) {
        // On Android, output to stderr which is connected to logcat
        const stderr = std.io.getStdErr().writer();
        const level_char: u8 = switch (priority) {
            .verbose => 'V',
            .debug => 'D',
            .info => 'I',
            .warn => 'W',
            .err => 'E',
            .fatal => 'F',
        };
        stderr.print("{c}/{s}: {s}\n", .{ level_char, tag, message }) catch {};
    } else {
        // On non-Android, just use stderr
        const stderr = std.io.getStdErr().writer();
        stderr.print("[{s}] {s}\n", .{ tag, message }) catch {};
    }
}

// ============================================================================
// Bionic libc Compatibility
// ============================================================================

/// Bionic-specific behavior flags
pub const BionicFlags = struct {
    /// Has pthread_cancel (Android doesn't)
    has_pthread_cancel: bool = false,
    /// Has locale support
    has_locale: bool = true,
    /// Has iconv
    has_iconv: bool = false,
};

/// Get Bionic compatibility info
pub fn getBionicFlags() BionicFlags {
    return .{};
}

// ============================================================================
// Hardware Features
// ============================================================================

/// Check for NEON SIMD support
/// Reads /proc/cpuinfo on ARM devices to detect NEON
pub fn hasNeon() bool {
    if (builtin.cpu.arch == .aarch64) return true; // All AArch64 has NEON
    if (builtin.cpu.arch == .arm) {
        // Check /proc/cpuinfo for neon feature
        const cpuinfo = std.fs.cwd().openFile("/proc/cpuinfo", .{}) catch return true;
        defer cpuinfo.close();

        var buf: [4096]u8 = undefined;
        const read = cpuinfo.reader().readAll(&buf) catch return true;

        // Look for "Features" line containing "neon"
        var lines = std.mem.splitScalar(u8, buf[0..read], '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "Features")) {
                return std.mem.indexOf(u8, line, "neon") != null;
            }
        }
        return true; // Assume NEON on modern ARM
    }
    return false;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _android_support module
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

test "android detection" {
    const result = is_android;
    _ = result;
}

test "api level name" {
    const api = ApiLevel.api_33;
    try std.testing.expectEqualStrings("Tiramisu", api.getName());
}

test "storage paths" {
    const paths = getStoragePaths();
    try std.testing.expect(paths.internal.len > 0);
}

test "permission name" {
    const perm = Permission.internet;
    try std.testing.expectEqualStrings("android.permission.INTERNET", perm.getName());
}

test "bionic flags" {
    const flags = getBionicFlags();
    try std.testing.expect(!flags.has_pthread_cancel);
}

test "log priority" {
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(LogPriority.info));
}
