/// dynload_stub - Stub Dynamic Loading Implementation
/// Mirrors cpython/Python/dynload_stub.c
///
/// Provides a no-op implementation for platforms without dynamic loading.
/// Used as fallback when no real dynamic loading is available.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Stub Errors
// ============================================================================

/// Stub loader always returns this error
pub const StubError = error{
    DynamicLoadingNotSupported,
    FeatureNotAvailable,
};

// ============================================================================
// Stub Handle
// ============================================================================

/// Opaque handle (never actually used)
pub const StubHandle = *anyopaque;

// ============================================================================
// Stub Loader
// ============================================================================

/// Stub loader that always fails
pub const StubLoader = struct {
    const Self = @This();

    /// Allocator (unused)
    allocator: Allocator,
    /// Error message
    error_message: []const u8 = "Dynamic loading is not supported on this platform",

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Always fails - dynamic loading not supported
    pub fn load(self: *Self, path: []const u8) StubError!void {
        _ = self;
        _ = path;
        return StubError.DynamicLoadingNotSupported;
    }

    /// Always fails - no library loaded
    pub fn unload(self: *Self) void {
        _ = self;
    }

    /// Always fails - no symbols available
    pub fn getSymbol(self: *Self, name: []const u8) StubError!*anyopaque {
        _ = self;
        _ = name;
        return StubError.DynamicLoadingNotSupported;
    }

    /// Get error message
    pub fn getError(self: *const Self) []const u8 {
        return self.error_message;
    }
};

// ============================================================================
// Python Extension Support (Stub)
// ============================================================================

/// Stub extension suffix
pub const extension_suffix = ".so";

/// PyInit function signature
pub const PyInitFunc = *const fn () callconv(.C) ?*anyopaque;

/// Always fails - can't load extensions
pub fn loadPythonExtension(allocator: Allocator, path: []const u8) StubError!PyInitFunc {
    _ = allocator;
    _ = path;
    return StubError.DynamicLoadingNotSupported;
}

/// Check if dynamic loading is supported
pub fn isSupported() bool {
    return false;
}

/// Get platform support message
pub fn getSupportMessage() []const u8 {
    return "Dynamic loading is not available. Python was built without shared library support.";
}

// ============================================================================
// Compatibility Shims
// ============================================================================

/// Compatibility shim for code expecting dlopen-style API
pub const DLCompat = struct {
    pub fn dlopen(path: []const u8, flags: i32) ?*anyopaque {
        _ = path;
        _ = flags;
        return null;
    }

    pub fn dlclose(handle: ?*anyopaque) i32 {
        _ = handle;
        return -1;
    }

    pub fn dlsym(handle: ?*anyopaque, name: []const u8) ?*anyopaque {
        _ = handle;
        _ = name;
        return null;
    }

    pub fn dlerror() []const u8 {
        return "Dynamic loading not supported";
    }
};

// ============================================================================
// Module Information
// ============================================================================

/// Module info structure
pub const ModuleInfo = struct {
    /// Module name
    name: []const u8 = "dynload_stub",
    /// Module version
    version: []const u8 = "1.0",
    /// Platform support
    supported: bool = false,
    /// Reason for stub
    reason: []const u8 = "Platform does not support dynamic loading",
};

/// Get module info
pub fn getModuleInfo() ModuleInfo {
    return ModuleInfo{};
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the dynload_stub module
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

test "stub loader always fails" {
    const allocator = std.testing.allocator;
    var loader = StubLoader.init(allocator);
    defer loader.deinit();

    try std.testing.expectError(StubError.DynamicLoadingNotSupported, loader.load("libtest.so"));
    try std.testing.expectError(StubError.DynamicLoadingNotSupported, loader.getSymbol("test"));
}

test "is not supported" {
    try std.testing.expect(!isSupported());
}

test "dlcompat returns null" {
    try std.testing.expect(DLCompat.dlopen("test.so", 0) == null);
    try std.testing.expect(DLCompat.dlsym(null, "test") == null);
    try std.testing.expectEqual(@as(i32, -1), DLCompat.dlclose(null));
}

test "error message" {
    const allocator = std.testing.allocator;
    var loader = StubLoader.init(allocator);
    const msg = loader.getError();
    try std.testing.expect(msg.len > 0);
}

test "module info" {
    const info = getModuleInfo();
    try std.testing.expect(!info.supported);
    try std.testing.expectEqualStrings("dynload_stub", info.name);
}
