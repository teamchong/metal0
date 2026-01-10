//! test.test_ctypes.test_loading - Tests for library loading
//! Reference: cpython/Lib/test/test_ctypes/test_loading.py
//!
//! Tests for dynamic library loading in ctypes including CDLL,
//! WinDLL, and different loading modes.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// Library Loader
// ============================================================================

/// Loading mode flags
pub const LoadMode = struct {
    pub const RTLD_LAZY: u32 = 0x0001;
    pub const RTLD_NOW: u32 = 0x0002;
    pub const RTLD_GLOBAL: u32 = 0x0100;
    pub const RTLD_LOCAL: u32 = 0x0000;
};

/// Library handle
pub const LibraryHandle = struct {
    const Self = @This();

    name: []const u8,
    path: ?[]const u8 = null,
    mode: u32 = LoadMode.RTLD_LAZY,
    loaded: bool = false,
    symbols: std.StringHashMapUnmanaged(*anyopaque) = .{},

    pub fn init(name: []const u8) Self {
        return .{ .name = name };
    }

    pub fn load(self: *Self) !void {
        // Mock loading - in real impl would use dlopen
        self.loaded = true;
    }

    pub fn unload(self: *Self) void {
        self.loaded = false;
        self.symbols = .{};
    }

    pub fn getSymbol(self: *const Self, name: []const u8) ?*anyopaque {
        _ = self;
        _ = name;
        // Mock symbol lookup
        return null;
    }

    pub fn isLoaded(self: *const Self) bool {
        return self.loaded;
    }
};

// ============================================================================
// CDLL - C Dynamic Link Library
// ============================================================================

pub const CDLL = struct {
    const Self = @This();

    handle: LibraryHandle,

    pub fn init(name: []const u8) Self {
        return .{ .handle = LibraryHandle.init(name) };
    }

    pub fn initWithMode(name: []const u8, mode: u32) Self {
        var self = Self.init(name);
        self.handle.mode = mode;
        return self;
    }

    pub fn load(self: *Self) !void {
        try self.handle.load();
    }

    pub fn unload(self: *Self) void {
        self.handle.unload();
    }

    pub fn getSymbol(self: *const Self, name: []const u8) ?*anyopaque {
        return self.handle.getSymbol(name);
    }

    pub fn isLoaded(self: *const Self) bool {
        return self.handle.isLoaded();
    }
};

/// Windows DLL (stdcall convention)
pub const WinDLL = CDLL;

/// OLE DLL
pub const OleDLL = CDLL;

/// Python DLL
pub const PyDLL = CDLL;

// ============================================================================
// Library Path Resolution
// ============================================================================

/// Resolve library path based on platform
pub fn resolveLibraryPath(name: []const u8) []const u8 {
    // Return platform-appropriate path
    if (_support.is_windows()) {
        if (std.mem.endsWith(u8, name, ".dll")) {
            return name;
        }
        // Would append .dll
        return name;
    } else if (_support.is_macos()) {
        if (std.mem.endsWith(u8, name, ".dylib")) {
            return name;
        }
        // Would prepend lib and append .dylib
        return name;
    } else {
        if (std.mem.endsWith(u8, name, ".so")) {
            return name;
        }
        // Would prepend lib and append .so
        return name;
    }
}

/// Get standard library paths
pub fn getLibraryPaths() []const []const u8 {
    return _support.get_libc_path()[0..0]; // Mock return
}

// ============================================================================
// Library Info
// ============================================================================

pub const LibraryInfo = struct {
    name: []const u8,
    path: []const u8,
    base_address: usize = 0,
    size: usize = 0,
    is_system: bool = false,
};

/// Get information about a loaded library
pub fn getLibraryInfo(name: []const u8) ?LibraryInfo {
    if (std.mem.eql(u8, name, "libc")) {
        return .{
            .name = "libc",
            .path = _support.get_libc_path(),
            .is_system = true,
        };
    }
    return null;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testCDLLInit() !void {
    const lib = CDLL.init("test");
    try std.testing.expectEqualStrings("test", lib.handle.name);
    try std.testing.expect(!lib.isLoaded());
}

fn testCDLLInitWithMode() !void {
    const lib = CDLL.initWithMode("test", LoadMode.RTLD_NOW | LoadMode.RTLD_GLOBAL);
    try std.testing.expectEqual(LoadMode.RTLD_NOW | LoadMode.RTLD_GLOBAL, lib.handle.mode);
}

fn testCDLLLoad() !void {
    var lib = CDLL.init("test");
    try std.testing.expect(!lib.isLoaded());

    try lib.load();
    try std.testing.expect(lib.isLoaded());

    lib.unload();
    try std.testing.expect(!lib.isLoaded());
}

fn testLibraryHandle() !void {
    var handle = LibraryHandle.init("libtest.so");
    try std.testing.expectEqual(LoadMode.RTLD_LAZY, handle.mode);
    try std.testing.expect(!handle.isLoaded());
}

fn testLoadModeFlags() !void {
    try std.testing.expect(LoadMode.RTLD_LAZY != LoadMode.RTLD_NOW);
    try std.testing.expect((LoadMode.RTLD_LAZY | LoadMode.RTLD_GLOBAL) > LoadMode.RTLD_LAZY);
}

fn testResolveLibraryPath() !void {
    const path = resolveLibraryPath("test");
    try std.testing.expect(path.len > 0);
}

fn testGetLibraryInfo() !void {
    const info = getLibraryInfo("libc");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("libc", info.?.name);
    try std.testing.expect(info.?.is_system);
}

fn testGetLibraryInfoMissing() !void {
    const info = getLibraryInfo("nonexistent");
    try std.testing.expect(info == null);
}

fn testWinDLL() !void {
    const lib = WinDLL.init("kernel32");
    try std.testing.expectEqualStrings("kernel32", lib.handle.name);
}

fn testOleDLL() !void {
    const lib = OleDLL.init("ole32");
    try std.testing.expectEqualStrings("ole32", lib.handle.name);
}

fn testPyDLL() !void {
    const lib = PyDLL.init("python");
    try std.testing.expectEqualStrings("python", lib.handle.name);
}

fn testGetSymbolNull() !void {
    const lib = CDLL.init("test");
    const sym = lib.getSymbol("nonexistent");
    try std.testing.expect(sym == null);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "cdll_init" {
    try testCDLLInit();
}

test "cdll_init_with_mode" {
    try testCDLLInitWithMode();
}

test "cdll_load" {
    try testCDLLLoad();
}

test "library_handle" {
    try testLibraryHandle();
}

test "load_mode_flags" {
    try testLoadModeFlags();
}

test "resolve_library_path" {
    try testResolveLibraryPath();
}

test "get_library_info" {
    try testGetLibraryInfo();
}

test "get_library_info_missing" {
    try testGetLibraryInfoMissing();
}

test "windll" {
    try testWinDLL();
}

test "oledll" {
    try testOleDLL();
}

test "pydll" {
    try testPyDLL();
}

test "get_symbol_null" {
    try testGetSymbolNull();
}
