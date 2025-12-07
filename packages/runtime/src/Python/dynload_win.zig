/// dynload_win - Dynamic Loading for Windows
/// Mirrors cpython/Python/dynload_win.c
///
/// Implements dynamic loading for Windows using LoadLibrary/GetProcAddress.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Windows
pub const is_supported = builtin.os.tag == .windows;

// ============================================================================
// Windows Handle Types
// ============================================================================

/// Handle to a loaded DLL
pub const HMODULE = *anyopaque;

/// DLL loading errors
pub const DLLError = error{
    ModuleNotFound,
    ProcedureNotFound,
    InvalidHandle,
    LoadFailed,
    AccessDenied,
    DependencyMissing,
    OutOfMemory,
};

// ============================================================================
// Windows DLL Loader
// ============================================================================

/// Windows DLL loader
pub const WindowsDLLLoader = struct {
    const Self = @This();

    /// Handle to the loaded DLL
    handle: ?HMODULE = null,
    /// Path to the DLL
    path: []const u8 = "",
    /// Last Windows error code
    last_error_code: u32 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.handle) |_| {
            self.free();
        }
    }

    /// Load a DLL
    pub fn load(self: *Self, path: []const u8, flags: LoadFlags) DLLError!void {
        if (self.handle != null) {
            self.free();
        }

        self.path = path;

        // Convert to Windows flags
        const win_flags = flagsToWin32(flags);

        // Simulate LoadLibraryExW
        self.handle = simulatedLoadLibrary(path, win_flags) catch |err| {
            self.last_error_code = 126; // ERROR_MOD_NOT_FOUND
            return err;
        };
    }

    /// Free the DLL
    pub fn free(self: *Self) void {
        if (self.handle) |handle| {
            simulatedFreeLibrary(handle);
            self.handle = null;
        }
    }

    /// Get a procedure address
    pub fn getProcAddress(self: *Self, name: []const u8) DLLError!*anyopaque {
        if (self.handle == null) {
            return DLLError.InvalidHandle;
        }

        return simulatedGetProcAddress(self.handle.?, name) catch {
            self.last_error_code = 127; // ERROR_PROC_NOT_FOUND
            return DLLError.ProcedureNotFound;
        };
    }

    /// Get last error code
    pub fn getLastError(self: *const Self) u32 {
        return self.last_error_code;
    }

    /// Format error message
    pub fn formatError(self: *const Self, allocator: Allocator) ![]const u8 {
        return switch (self.last_error_code) {
            126 => try allocator.dupe(u8, "The specified module could not be found"),
            127 => try allocator.dupe(u8, "The specified procedure could not be found"),
            5 => try allocator.dupe(u8, "Access denied"),
            else => try std.fmt.allocPrint(allocator, "Windows error {d}", .{self.last_error_code}),
        };
    }
};

// ============================================================================
// Load Flags
// ============================================================================

/// Flags for loading DLLs
pub const LoadFlags = packed struct {
    /// Don't resolve DLL references (DONT_RESOLVE_DLL_REFERENCES)
    dont_resolve_refs: bool = false,
    /// Load as data file (LOAD_LIBRARY_AS_DATAFILE)
    as_datafile: bool = false,
    /// Use altered search path (LOAD_WITH_ALTERED_SEARCH_PATH)
    altered_search_path: bool = false,
    /// Ignore code authz level (LOAD_IGNORE_CODE_AUTHZ_LEVEL)
    ignore_code_authz: bool = false,
    /// Load as image resource (LOAD_LIBRARY_AS_IMAGE_RESOURCE)
    as_image_resource: bool = false,
    /// Search for DLL in application directory first (LOAD_LIBRARY_SEARCH_APPLICATION_DIR)
    search_app_dir: bool = false,
    /// Search default directories (LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)
    search_default_dirs: bool = true,
    /// Reserved
    _reserved: u1 = 0,
};

/// Convert LoadFlags to Windows DWORD
fn flagsToWin32(flags: LoadFlags) u32 {
    var win_flags: u32 = 0;

    if (flags.dont_resolve_refs) win_flags |= 0x00000001; // DONT_RESOLVE_DLL_REFERENCES
    if (flags.as_datafile) win_flags |= 0x00000002; // LOAD_LIBRARY_AS_DATAFILE
    if (flags.altered_search_path) win_flags |= 0x00000008; // LOAD_WITH_ALTERED_SEARCH_PATH
    if (flags.ignore_code_authz) win_flags |= 0x00000010; // LOAD_IGNORE_CODE_AUTHZ_LEVEL
    if (flags.as_image_resource) win_flags |= 0x00000020; // LOAD_LIBRARY_AS_IMAGE_RESOURCE
    if (flags.search_app_dir) win_flags |= 0x00000200; // LOAD_LIBRARY_SEARCH_APPLICATION_DIR
    if (flags.search_default_dirs) win_flags |= 0x00001000; // LOAD_LIBRARY_SEARCH_DEFAULT_DIRS

    return win_flags;
}

// ============================================================================
// Platform Simulation
// ============================================================================

/// Simulated LoadLibraryExW
fn simulatedLoadLibrary(path: []const u8, flags: u32) DLLError!HMODULE {
    _ = flags;
    if (std.mem.eql(u8, path, "")) {
        return DLLError.ModuleNotFound;
    }
    return @as(*anyopaque, @ptrFromInt(@intFromPtr(path.ptr)));
}

/// Simulated FreeLibrary
fn simulatedFreeLibrary(handle: HMODULE) void {
    _ = handle;
}

/// Simulated GetProcAddress
fn simulatedGetProcAddress(handle: HMODULE, name: []const u8) DLLError!*anyopaque {
    _ = handle;
    if (std.mem.eql(u8, name, "")) {
        return DLLError.ProcedureNotFound;
    }
    return @as(*anyopaque, @ptrFromInt(@intFromPtr(name.ptr)));
}

// ============================================================================
// Python Extension Support
// ============================================================================

/// Python extension DLL suffix
pub const extension_suffix = ".pyd";

/// Get versioned extension suffix
pub fn getVersionedSuffix(major: u32, minor: u32) [32]u8 {
    var buf: [32]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, ".cp{d}{d}-win_amd64.pyd", .{ major, minor }) catch {
        @memcpy(buf[0..4], ".pyd");
        return buf;
    };
    _ = len;
    return buf;
}

/// PyInit function signature for Windows
pub const PyInitFunc = *const fn () callconv(.C) ?*anyopaque;

/// Load Python extension module
pub fn loadPythonExtension(allocator: Allocator, path: []const u8) DLLError!PyInitFunc {
    var loader = WindowsDLLLoader.init(allocator);
    defer loader.deinit();

    try loader.load(path, .{});

    const func = try loader.getProcAddress("PyInit_module");
    return @ptrCast(func);
}

// ============================================================================
// DLL Search Order
// ============================================================================

/// DLL search order configuration
pub const SearchOrder = struct {
    /// Search application directory first
    app_dir_first: bool = true,
    /// Search system directory
    system_dir: bool = true,
    /// Search Windows directory
    windows_dir: bool = true,
    /// Search current directory
    current_dir: bool = false,
    /// Search PATH
    path_dirs: bool = true,
};

/// Get standard DLL directories
pub fn getStandardDirectories(allocator: Allocator) !std.ArrayList([]const u8) {
    var dirs = std.ArrayList([]const u8).init(allocator);

    // System32 (would query actual path on Windows)
    try dirs.append("C:\\Windows\\System32");
    // Windows directory
    try dirs.append("C:\\Windows");
    // Current directory (if enabled)
    try dirs.append(".");

    return dirs;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the dynload_win module
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

test "load flags to win32" {
    const flags = LoadFlags{ .altered_search_path = true };
    const win_flags = flagsToWin32(flags);
    try std.testing.expect(win_flags != 0);
}

test "windows dll loader init" {
    const allocator = std.testing.allocator;
    var loader = WindowsDLLLoader.init(allocator);
    defer loader.deinit();

    try std.testing.expect(loader.handle == null);
}

test "extension suffix" {
    try std.testing.expectEqualStrings(".pyd", extension_suffix);
}

test "error formatting" {
    const allocator = std.testing.allocator;
    var loader = WindowsDLLLoader.init(allocator);
    loader.last_error_code = 126;

    const msg = try loader.formatError(allocator);
    defer allocator.free(msg);

    try std.testing.expect(msg.len > 0);
}
