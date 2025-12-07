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

/// Get device family (stub)
pub fn getDeviceFamily() DeviceFamily {
    if (!is_ios) return .unknown;
    // Would check UIDevice.current.userInterfaceIdiom
    return .iphone;
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

/// Get iOS version (stub on non-iOS)
pub fn getIOSVersion() ?IOSVersion {
    if (!is_ios) return null;
    // Would parse UIDevice.current.systemVersion
    return IOSVersion{ .major = 17, .minor = 0, .patch = 0 };
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
pub fn getDocumentsDirectory() ?[]const u8 {
    if (!is_ios) return null;
    // Would use NSSearchPathForDirectoriesInDomains
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

/// Get main screen info (stub)
pub fn getMainScreenInfo() ScreenInfo {
    if (!is_ios) return .{};
    // Would query UIScreen.main
    return .{
        .width = 390,
        .height = 844,
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

/// Check if background mode is enabled (stub)
pub fn hasBackgroundMode(mode: BackgroundMode) bool {
    _ = mode;
    if (!is_ios) return false;
    // Would check Info.plist UIBackgroundModes
    return false;
}

// ============================================================================
// URL Schemes
// ============================================================================

/// Check if URL scheme can be opened (stub)
pub fn canOpenURL(scheme: []const u8) bool {
    _ = scheme;
    if (!is_ios) return false;
    // Would call UIApplication.canOpenURL
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
