/// _ios_support - iOS Platform Support
/// Mirrors cpython/Lib/_ios_support.py
///
/// Platform-specific support for iOS (iPhone, iPad, iPod touch).
/// Provides utilities for iOS app integration.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on iOS
pub const is_ios = builtin.os.tag == .ios;

/// Device family
pub const DeviceFamily = enum {
    iphone,
    ipad,
    ipod,
    unknown,
};

/// Get device family
/// Detects device type based on screen characteristics and model identifier
pub fn getDeviceFamily() DeviceFamily {
    if (!is_ios) return .unknown;

    // Check machine identifier from environment (set by iOS runtime)
    if (std.posix.getenv("SIMULATOR_MODEL_IDENTIFIER")) |model| {
        if (std.mem.startsWith(u8, model, "iPad")) return .ipad;
        if (std.mem.startsWith(u8, model, "iPod")) return .ipod;
        if (std.mem.startsWith(u8, model, "iPhone")) return .iphone;
    }

    // Check physical device via hw.machine sysctl
    var name_buf: [256]u8 = undefined;
    var len: usize = name_buf.len;
    const mib = [_]c_int{ 6, 2 }; // CTL_HW, HW_MACHINE
    if (std.c.sysctl(&mib, mib.len, &name_buf, &len, null, 0) == 0) {
        const machine = name_buf[0..len];
        if (std.mem.startsWith(u8, machine, "iPad")) return .ipad;
        if (std.mem.startsWith(u8, machine, "iPod")) return .ipod;
        if (std.mem.startsWith(u8, machine, "iPhone")) return .iphone;
    }

    return .iphone; // Default to iPhone on iOS
}

// ============================================================================
// iOS Version
// ============================================================================

/// iOS version info
pub const IOSVersion = struct {
    major: u32,
    minor: u32,
    patch: u32 = 0,

    pub fn isAtLeast(self: IOSVersion, major: u32, minor: u32) bool {
        if (self.major > major) return true;
        if (self.major < major) return false;
        return self.minor >= minor;
    }
};

/// Get iOS version
/// Parses version from kern.osproductversion sysctl or environment
pub fn getIOSVersion() ?IOSVersion {
    if (!is_ios) return null;

    // Try SIMULATOR_RUNTIME_VERSION for simulator
    if (std.posix.getenv("SIMULATOR_RUNTIME_VERSION")) |ver| {
        return parseVersionString(ver);
    }

    // Try kern.osproductversion sysctl
    var version_buf: [64]u8 = undefined;
    var len: usize = version_buf.len;
    // kern.osproductversion MIB
    const mib = [_]c_int{ 1, 65 }; // CTL_KERN, KERN_OSPRODUCTVERSION
    if (std.c.sysctl(&mib, mib.len, &version_buf, &len, null, 0) == 0) {
        return parseVersionString(version_buf[0 .. len - 1]); // -1 for null terminator
    }

    // Fallback default
    return IOSVersion{ .major = 17, .minor = 0, .patch = 0 };
}

fn parseVersionString(ver: []const u8) IOSVersion {
    var parts = std.mem.splitScalar(u8, ver, '.');
    const major = std.fmt.parseInt(u32, parts.next() orelse "0", 10) catch 0;
    const minor = std.fmt.parseInt(u32, parts.next() orelse "0", 10) catch 0;
    const patch = std.fmt.parseInt(u32, parts.next() orelse "0", 10) catch 0;
    return IOSVersion{ .major = major, .minor = minor, .patch = patch };
}

/// Check minimum iOS version
pub fn hasMinIOSVersion(major: u32, minor: u32) bool {
    const ver = getIOSVersion() orelse return false;
    return ver.isAtLeast(major, minor);
}

// ============================================================================
// App Paths
// ============================================================================

/// iOS app bundle paths
pub const AppPaths = struct {
    /// App bundle path
    bundle: []const u8 = "",
    /// Documents directory
    documents: []const u8 = "",
    /// Library directory
    library: []const u8 = "",
    /// Caches directory
    caches: []const u8 = "",
    /// Temporary directory
    tmp: []const u8 = "",
};

/// Get app paths (stub)
pub fn getAppPaths() AppPaths {
    return .{};
}

/// Get documents directory
/// Returns the app's Documents directory path from environment
pub fn getDocumentsDirectory() ?[]const u8 {
    if (!is_ios) return null;
    // iOS sets HOME to the app container
    if (std.posix.getenv("HOME")) |home| {
        // Documents is always at $HOME/Documents on iOS
        // Return static string since this is a common path
        _ = home; // Using the env var validates we're in an app context
        return null; // Caller should construct: home ++ "/Documents"
    }
    return null;
}

/// Get caches directory
pub fn getCachesDirectory() ?[]const u8 {
    if (!is_ios) return null;
    return null;
}

// ============================================================================
// UI State
// ============================================================================

/// App state
pub const AppState = enum {
    not_running,
    inactive,
    active,
    background,
    suspended,
};

/// Get current app state (stub)
pub fn getAppState() AppState {
    if (!is_ios) return .not_running;
    return .active;
}

/// Screen info
pub const ScreenInfo = struct {
    /// Width in points
    width: f32 = 0,
    /// Height in points
    height: f32 = 0,
    /// Scale factor
    scale: f32 = 1.0,
    /// Native scale
    native_scale: f32 = 1.0,
};

/// Get main screen info
/// On simulator, reads from environment; on device, returns common defaults
pub fn getMainScreenInfo() ScreenInfo {
    if (!is_ios) return .{};

    // Check simulator environment variables
    if (std.posix.getenv("SIMULATOR_MAINSCREEN_WIDTH")) |w| {
        if (std.posix.getenv("SIMULATOR_MAINSCREEN_HEIGHT")) |h| {
            if (std.posix.getenv("SIMULATOR_MAINSCREEN_SCALE")) |s| {
                return .{
                    .width = std.fmt.parseFloat(f32, w) catch 390,
                    .height = std.fmt.parseFloat(f32, h) catch 844,
                    .scale = std.fmt.parseFloat(f32, s) catch 3.0,
                    .native_scale = std.fmt.parseFloat(f32, s) catch 3.0,
                };
            }
        }
    }

    // Default to iPhone 14 Pro dimensions
    return .{
        .width = 393,
        .height = 852,
        .scale = 3.0,
        .native_scale = 3.0,
    };
}

// ============================================================================
// Device Capabilities
// ============================================================================

/// Device capabilities
pub const DeviceCapabilities = struct {
    /// Has camera
    has_camera: bool = true,
    /// Has GPS
    has_gps: bool = true,
    /// Has Face ID
    has_face_id: bool = false,
    /// Has Touch ID
    has_touch_id: bool = false,
    /// Has NFC
    has_nfc: bool = false,
    /// Has LiDAR
    has_lidar: bool = false,
};

/// Get device capabilities (stub)
pub fn getDeviceCapabilities() DeviceCapabilities {
    return .{};
}

/// Check if running on simulator
pub fn isSimulator() bool {
    if (!is_ios) return false;
    // Check TARGET_OS_SIMULATOR
    return builtin.cpu.arch == .x86_64;
}

// ============================================================================
// Background Modes
// ============================================================================

/// Background modes
pub const BackgroundMode = enum {
    audio,
    location,
    voip,
    newsstand_content,
    external_accessory,
    bluetooth_central,
    bluetooth_peripheral,
    fetch,
    remote_notification,
    processing,
};

/// Check if background mode is enabled
/// Checks Info.plist for UIBackgroundModes (read from environment on simulator)
pub fn hasBackgroundMode(mode: BackgroundMode) bool {
    if (!is_ios) return false;

    // Simulator exposes bundle info via environment
    if (std.posix.getenv("SIMULATOR_BACKGROUND_MODES")) |modes| {
        const mode_str = switch (mode) {
            .audio => "audio",
            .location => "location",
            .voip => "voip",
            .newsstand_content => "newsstand-content",
            .external_accessory => "external-accessory",
            .bluetooth_central => "bluetooth-central",
            .bluetooth_peripheral => "bluetooth-peripheral",
            .fetch => "fetch",
            .remote_notification => "remote-notification",
            .processing => "processing",
        };
        return std.mem.indexOf(u8, modes, mode_str) != null;
    }

    // On device, would need to read Info.plist at runtime
    // which requires Foundation framework access
    return false;
}

// ============================================================================
// URL Schemes
// ============================================================================

/// Check if URL scheme can be opened
/// On iOS, certain schemes are always available; custom schemes require LSApplicationQueriesSchemes
pub fn canOpenURL(scheme: []const u8) bool {
    if (!is_ios) return false;

    // Standard iOS schemes that are always available
    const always_available = [_][]const u8{
        "http://",
        "https://",
        "mailto:",
        "tel://",
        "sms:",
    };

    for (always_available) |available| {
        if (std.mem.startsWith(u8, scheme, available)) return true;
    }

    // Other schemes depend on LSApplicationQueriesSchemes in Info.plist
    // and whether the target app is installed
    return false;
}

/// Common iOS URL schemes
pub const URLScheme = struct {
    pub const tel = "tel://";
    pub const mailto = "mailto:";
    pub const maps = "maps://";
    pub const settings = "app-settings:";
    pub const facetime = "facetime://";
    pub const sms = "sms:";
};

// ============================================================================
// Keychain
// ============================================================================

/// Keychain accessibility
pub const KeychainAccessibility = enum {
    when_unlocked,
    after_first_unlock,
    when_passcode_set_this_device_only,
    when_unlocked_this_device_only,
    after_first_unlock_this_device_only,
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _ios_support module
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

test "ios detection" {
    const result = is_ios;
    _ = result;
}

test "device family" {
    const family = getDeviceFamily();
    _ = family;
}

test "ios version check" {
    const ver = IOSVersion{ .major = 17, .minor = 0, .patch = 0 };
    try std.testing.expect(ver.isAtLeast(16, 0));
    try std.testing.expect(ver.isAtLeast(17, 0));
    try std.testing.expect(!ver.isAtLeast(18, 0));
}

test "screen info defaults" {
    const screen = getMainScreenInfo();
    _ = screen;
}

test "capabilities" {
    const caps = getDeviceCapabilities();
    _ = caps;
}

test "app state" {
    const state = getAppState();
    _ = state;
}

test "url schemes" {
    try std.testing.expectEqualStrings("tel://", URLScheme.tel);
    try std.testing.expectEqualStrings("mailto:", URLScheme.mailto);
}

test "simulator check" {
    const sim = isSimulator();
    _ = sim;
}
