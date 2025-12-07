/// dynload_hpux - Dynamic Loading for HP-UX
/// Mirrors cpython/Python/dynload_hpux.c
///
/// Implements dynamic loading for HP-UX using shl_load/shl_findsym.
/// HP-UX uses a different dynamic loading API than standard Unix dlopen.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// HP-UX dynamic loading is only supported on HP-UX
pub const is_supported = false; // HP-UX not supported by Zig currently

// ============================================================================
// HP-UX Handle Types
// ============================================================================

/// Handle to a loaded shared library
pub const ShlHandle = *anyopaque;

/// HP-UX dynamic loading errors
pub const ShlError = error{
    LoadFailed,
    SymbolNotFound,
    InvalidHandle,
    PermissionDenied,
    FileNotFound,
    InvalidFormat,
};

// ============================================================================
// HP-UX Binding Types
// ============================================================================

/// Symbol binding types
pub const BindType = enum(i32) {
    /// Immediate binding (BIND_IMMEDIATE)
    immediate = 0,
    /// Deferred binding (BIND_DEFERRED)
    deferred = 1,
    /// Bind only referenced symbols
    first = 2,
    /// Don't bind if not referenced
    nonfatal = 4,
    /// Verbose error messages
    verbose = 8,
};

/// Symbol types for shl_findsym
pub const SymType = enum(i16) {
    /// Code/function symbol (TYPE_PROCEDURE)
    procedure = 0,
    /// Data symbol (TYPE_DATA)
    data = 1,
    /// Undefined (any type)
    undefined = -1,
};

// ============================================================================
// HP-UX Loader
// ============================================================================

/// HP-UX shared library loader
pub const HpuxLoader = struct {
    const Self = @This();

    /// Handle to loaded library
    handle: ?ShlHandle = null,
    /// Path to library
    path: []const u8 = "",
    /// Errno from last operation
    last_errno: i32 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.handle) |_| {
            self.unload();
        }
    }

    /// Load a shared library using shl_load
    pub fn load(self: *Self, path: []const u8, bind_type: BindType) ShlError!void {
        if (self.handle != null) {
            self.unload();
        }

        self.path = path;

        // Simulate shl_load
        self.handle = simulatedShlLoad(path, @intFromEnum(bind_type)) catch |err| {
            self.last_errno = -1;
            return err;
        };
    }

    /// Unload the library
    pub fn unload(self: *Self) void {
        if (self.handle) |handle| {
            simulatedShlUnload(handle);
            self.handle = null;
        }
    }

    /// Find a symbol using shl_findsym
    pub fn findSymbol(self: *Self, name: []const u8, sym_type: SymType) ShlError!*anyopaque {
        if (self.handle == null) {
            return ShlError.InvalidHandle;
        }

        return simulatedShlFindsym(self.handle.?, name, sym_type) catch {
            self.last_errno = -1;
            return ShlError.SymbolNotFound;
        };
    }

    /// Get symbol info
    pub fn getSymbolInfo(self: *Self, name: []const u8) ShlError!SymbolInfo {
        if (self.handle == null) {
            return ShlError.InvalidHandle;
        }

        const addr = try self.findSymbol(name, .undefined);
        return SymbolInfo{
            .name = name,
            .address = addr,
            .type = .undefined,
            .size = 0,
        };
    }
};

/// Symbol information
pub const SymbolInfo = struct {
    name: []const u8,
    address: *anyopaque,
    type: SymType,
    size: usize,
};

// ============================================================================
// Platform Simulation
// ============================================================================

/// Simulated shl_load
fn simulatedShlLoad(path: []const u8, flags: i32) ShlError!ShlHandle {
    _ = flags;
    if (std.mem.eql(u8, path, "")) {
        return ShlError.FileNotFound;
    }
    return @as(*anyopaque, @ptrFromInt(@intFromPtr(path.ptr)));
}

/// Simulated shl_unload
fn simulatedShlUnload(handle: ShlHandle) void {
    _ = handle;
}

/// Simulated shl_findsym
fn simulatedShlFindsym(handle: ShlHandle, name: []const u8, sym_type: SymType) ShlError!*anyopaque {
    _ = handle;
    _ = sym_type;
    if (std.mem.eql(u8, name, "")) {
        return ShlError.SymbolNotFound;
    }
    return @as(*anyopaque, @ptrFromInt(@intFromPtr(name.ptr)));
}

// ============================================================================
// Python Extension Support
// ============================================================================

/// HP-UX shared library suffix
pub const extension_suffix = ".sl";

/// PyInit function for HP-UX
pub const PyInitFunc = *const fn () callconv(.C) ?*anyopaque;

/// Load Python extension module
pub fn loadPythonExtension(allocator: Allocator, path: []const u8) ShlError!PyInitFunc {
    var loader = HpuxLoader.init(allocator);
    defer loader.deinit();

    try loader.load(path, .immediate);

    const func = try loader.findSymbol("PyInit_module", .procedure);
    return @ptrCast(func);
}

// ============================================================================
// Library Search Paths
// ============================================================================

/// HP-UX library search paths
pub const SearchPaths = struct {
    const Self = @This();

    paths: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .paths = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit();
    }

    /// Add search path
    pub fn addPath(self: *Self, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        try self.paths.append(owned);
    }

    /// Add paths from SHLIB_PATH
    pub fn addFromShlibPath(self: *Self) !void {
        const shlib_path = std.process.getEnvVarOwned(self.allocator, "SHLIB_PATH") catch {
            return;
        };
        defer self.allocator.free(shlib_path);

        var it = std.mem.splitScalar(u8, shlib_path, ':');
        while (it.next()) |path| {
            if (path.len > 0) {
                try self.addPath(path);
            }
        }
    }

    /// Initialize with default HP-UX paths
    pub fn initDefaults(allocator: Allocator) !Self {
        var self = Self.init(allocator);

        // Standard HP-UX library paths
        try self.addPath("/usr/lib");
        try self.addPath("/usr/local/lib");
        try self.addPath("/opt/lib");

        // Add SHLIB_PATH
        try self.addFromShlibPath();

        return self;
    }
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the dynload_hpux module
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

test "bind types" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(BindType.immediate));
    try std.testing.expectEqual(@as(i32, 1), @intFromEnum(BindType.deferred));
}

test "sym types" {
    try std.testing.expectEqual(@as(i16, 0), @intFromEnum(SymType.procedure));
    try std.testing.expectEqual(@as(i16, 1), @intFromEnum(SymType.data));
}

test "hpux loader init" {
    const allocator = std.testing.allocator;
    var loader = HpuxLoader.init(allocator);
    defer loader.deinit();

    try std.testing.expect(loader.handle == null);
}

test "search paths" {
    const allocator = std.testing.allocator;
    var paths = SearchPaths.init(allocator);
    defer paths.deinit();

    try paths.addPath("/usr/lib");
    try std.testing.expectEqual(@as(usize, 1), paths.paths.items.len);
}

test "extension suffix" {
    try std.testing.expectEqualStrings(".sl", extension_suffix);
}
