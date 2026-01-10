//! test.test_ctypes.test_dlerror - Tests for dynamic loader errors
//! Reference: cpython/Lib/test/test_ctypes/test_dlerror.py
//!
//! Tests for dlopen/dlsym error handling including error messages,
//! library loading failures, and symbol resolution errors.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// DL Error Handling
// ============================================================================

/// Error types for dynamic loading
pub const DLError = error{
    LibraryNotFound,
    SymbolNotFound,
    InvalidHandle,
    VersionMismatch,
    DependencyError,
    PermissionDenied,
    UnknownError,
};

/// Dynamic loader error state
pub const DLErrorState = struct {
    const Self = @This();

    last_error: ?[]const u8 = null,
    error_code: ?DLError = null,

    pub fn setError(self: *Self, code: DLError, message: []const u8) void {
        self.error_code = code;
        self.last_error = message;
    }

    pub fn clearError(self: *Self) void {
        self.error_code = null;
        self.last_error = null;
    }

    pub fn getError(self: *const Self) ?[]const u8 {
        return self.last_error;
    }

    pub fn hasError(self: *const Self) bool {
        return self.error_code != null;
    }
};

/// Thread-local error state (simulated)
pub var dl_error_state = DLErrorState{};

/// Get the last error message (like dlerror())
pub fn dlerror() ?[]const u8 {
    const err = dl_error_state.getError();
    dl_error_state.clearError();
    return err;
}

// ============================================================================
// Mock DL Functions
// ============================================================================

/// Mock library handle
pub const DLHandle = struct {
    name: []const u8,
    valid: bool = true,
};

/// Mock dlopen - load a library
pub fn dlopen(path: []const u8, mode: u32) ?*DLHandle {
    _ = mode;

    // Simulate various error conditions
    if (std.mem.eql(u8, path, "nonexistent.so")) {
        dl_error_state.setError(.LibraryNotFound, "nonexistent.so: cannot open shared object file: No such file or directory");
        return null;
    }

    if (std.mem.eql(u8, path, "noperm.so")) {
        dl_error_state.setError(.PermissionDenied, "noperm.so: Permission denied");
        return null;
    }

    if (std.mem.eql(u8, path, "broken.so")) {
        dl_error_state.setError(.DependencyError, "broken.so: undefined symbol: missing_func");
        return null;
    }

    // Return a valid handle for known libraries
    const handle = std.testing.allocator.create(DLHandle) catch return null;
    handle.* = .{ .name = path };
    return handle;
}

/// Mock dlclose - close a library
pub fn dlclose(handle: *DLHandle) i32 {
    if (!handle.valid) {
        dl_error_state.setError(.InvalidHandle, "Invalid library handle");
        return -1;
    }

    handle.valid = false;
    std.testing.allocator.destroy(handle);
    return 0;
}

/// Mock dlsym - find a symbol
pub fn dlsym(handle: *DLHandle, symbol: []const u8) ?*anyopaque {
    if (!handle.valid) {
        dl_error_state.setError(.InvalidHandle, "Invalid library handle");
        return null;
    }

    // Known symbols
    if (std.mem.eql(u8, symbol, "printf")) {
        return @ptrFromInt(0x1000); // Mock address
    }
    if (std.mem.eql(u8, symbol, "malloc")) {
        return @ptrFromInt(0x2000);
    }
    if (std.mem.eql(u8, symbol, "free")) {
        return @ptrFromInt(0x3000);
    }

    // Unknown symbol
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s}: undefined symbol: {s}", .{ handle.name, symbol }) catch "Symbol not found";
    dl_error_state.setError(.SymbolNotFound, msg);
    return null;
}

// ============================================================================
// RTLD Flags
// ============================================================================

pub const RTLD_LAZY = 0x0001;
pub const RTLD_NOW = 0x0002;
pub const RTLD_GLOBAL = 0x0100;
pub const RTLD_LOCAL = 0x0000;
pub const RTLD_NODELETE = 0x1000;
pub const RTLD_NOLOAD = 0x0004;
pub const RTLD_DEEPBIND = 0x0008;

// ============================================================================
// Error Message Formatting
// ============================================================================

/// Format an error message for library loading
pub fn formatLoadError(path: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "cannot load library '{s}'", .{path}) catch "Error formatting message";
}

/// Format an error message for symbol lookup
pub fn formatSymbolError(lib: []const u8, symbol: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "symbol '{s}' not found in '{s}'", .{ symbol, lib }) catch "Error formatting message";
}

// ============================================================================
// Test Cases
// ============================================================================

fn testDlopenSuccess() !void {
    const handle = dlopen("libc.so", RTLD_LAZY);
    try std.testing.expect(handle != null);

    if (handle) |h| {
        _ = dlclose(h);
    }

    try std.testing.expect(dlerror() == null);
}

fn testDlopenNotFound() !void {
    const handle = dlopen("nonexistent.so", RTLD_LAZY);
    try std.testing.expect(handle == null);

    const err = dlerror();
    try std.testing.expect(err != null);
    try std.testing.expect(std.mem.indexOf(u8, err.?, "No such file") != null);
}

fn testDlopenPermissionDenied() !void {
    const handle = dlopen("noperm.so", RTLD_LAZY);
    try std.testing.expect(handle == null);

    const err = dlerror();
    try std.testing.expect(err != null);
    try std.testing.expect(std.mem.indexOf(u8, err.?, "Permission denied") != null);
}

fn testDlopenDependencyError() !void {
    const handle = dlopen("broken.so", RTLD_LAZY);
    try std.testing.expect(handle == null);

    const err = dlerror();
    try std.testing.expect(err != null);
    try std.testing.expect(std.mem.indexOf(u8, err.?, "undefined symbol") != null);
}

fn testDlsymSuccess() !void {
    const handle = dlopen("libc.so", RTLD_LAZY);
    try std.testing.expect(handle != null);

    if (handle) |h| {
        const sym = dlsym(h, "printf");
        try std.testing.expect(sym != null);
        try std.testing.expect(dlerror() == null);

        _ = dlclose(h);
    }
}

fn testDlsymNotFound() !void {
    const handle = dlopen("libc.so", RTLD_LAZY);
    try std.testing.expect(handle != null);

    if (handle) |h| {
        const sym = dlsym(h, "nonexistent_function");
        try std.testing.expect(sym == null);

        const err = dlerror();
        try std.testing.expect(err != null);
        try std.testing.expect(std.mem.indexOf(u8, err.?, "undefined symbol") != null);

        _ = dlclose(h);
    }
}

fn testDlerrorClears() !void {
    _ = dlopen("nonexistent.so", RTLD_LAZY);

    // First call returns error
    const err1 = dlerror();
    try std.testing.expect(err1 != null);

    // Second call returns null (cleared)
    const err2 = dlerror();
    try std.testing.expect(err2 == null);
}

fn testRtldFlags() !void {
    // Test that flags are defined correctly
    try std.testing.expect(RTLD_LAZY != RTLD_NOW);
    try std.testing.expect((RTLD_LAZY | RTLD_GLOBAL) != RTLD_LAZY);
}

fn testFormatLoadError() !void {
    var buf: [256]u8 = undefined;
    const msg = formatLoadError("test.so", &buf);
    try std.testing.expect(std.mem.indexOf(u8, msg, "test.so") != null);
}

fn testFormatSymbolError() !void {
    var buf: [256]u8 = undefined;
    const msg = formatSymbolError("test.so", "func", &buf);
    try std.testing.expect(std.mem.indexOf(u8, msg, "func") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "test.so") != null);
}

fn testErrorState() !void {
    var state = DLErrorState{};

    try std.testing.expect(!state.hasError());

    state.setError(.SymbolNotFound, "test error");
    try std.testing.expect(state.hasError());
    try std.testing.expectEqualStrings("test error", state.getError().?);

    state.clearError();
    try std.testing.expect(!state.hasError());
    try std.testing.expect(state.getError() == null);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "dlopen_success" {
    try testDlopenSuccess();
}

test "dlopen_not_found" {
    try testDlopenNotFound();
}

test "dlopen_permission_denied" {
    try testDlopenPermissionDenied();
}

test "dlopen_dependency_error" {
    try testDlopenDependencyError();
}

test "dlsym_success" {
    try testDlsymSuccess();
}

test "dlsym_not_found" {
    try testDlsymNotFound();
}

test "dlerror_clears" {
    try testDlerrorClears();
}

test "rtld_flags" {
    try testRtldFlags();
}

test "format_load_error" {
    try testFormatLoadError();
}

test "format_symbol_error" {
    try testFormatSymbolError();
}

test "error_state" {
    try testErrorState();
}
