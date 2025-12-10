/// dynload_shlib - Dynamic Loading for Shared Libraries
/// Mirrors cpython/Python/dynload_shlib.c
///
/// Implements dynamic loading for Unix-like systems using dlopen/dlsym.
/// This is the primary dynamic loading mechanism for Linux, BSD, and macOS.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on a Unix-like system that supports shlib loading
pub const is_supported = switch (builtin.os.tag) {
    .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};

// ============================================================================
// Shared Library Handle
// ============================================================================

/// Opaque handle to a loaded shared library
pub const DLHandle = *anyopaque;

/// Shared library loading errors
pub const DLError = error{
    LibraryNotFound,
    SymbolNotFound,
    InvalidHandle,
    LoadFailed,
    VersionMismatch,
    PermissionDenied,
    OutOfMemory,
};

// ============================================================================
// Shared Library Loader
// ============================================================================

/// Shared library loader
pub const SharedLibLoader = struct {
    const Self = @This();

    /// Handle to the loaded library
    handle: ?DLHandle = null,
    /// Path to the library (for error messages)
    path: []const u8 = "",
    /// Last error message
    last_error: ?[]const u8 = null,
    /// Allocator for string storage
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.handle) |_| {
            self.close();
        }
        if (self.last_error) |err| {
            self.allocator.free(err);
        }
    }

    /// Load a shared library
    pub fn load(self: *Self, path: []const u8, flags: LoadFlags) DLError!void {
        if (self.handle != null) {
            self.close();
        }

        self.path = path;

        // Convert flags to platform-specific values
        const mode = flagsToMode(flags);

        // Use dlopen (simulated - would use C interop in real impl)
        self.handle = simulatedDlopen(path, mode) catch |err| {
            self.last_error = try self.allocator.dupe(u8, "Failed to load library");
            return err;
        };
    }

    /// Close the library
    pub fn close(self: *Self) void {
        if (self.handle) |handle| {
            simulatedDlclose(handle);
            self.handle = null;
        }
    }

    /// Get a symbol from the library
    pub fn getSymbol(self: *Self, name: []const u8) DLError!*anyopaque {
        if (self.handle == null) {
            return DLError.InvalidHandle;
        }

        return simulatedDlsym(self.handle.?, name) catch {
            self.last_error = try self.allocator.dupe(u8, "Symbol not found");
            return DLError.SymbolNotFound;
        };
    }

    /// Get the last error message
    pub fn getError(self: *const Self) ?[]const u8 {
        return self.last_error;
    }
};

// ============================================================================
// Load Flags
// ============================================================================

/// Flags for loading shared libraries
pub const LoadFlags = packed struct {
    /// Resolve symbols lazily (RTLD_LAZY)
    lazy: bool = true,
    /// Resolve all symbols immediately (RTLD_NOW)
    now: bool = false,
    /// Make symbols available globally (RTLD_GLOBAL)
    global: bool = false,
    /// Keep symbols local (RTLD_LOCAL)
    local: bool = true,
    /// Don't load library, just check if it exists (RTLD_NOLOAD)
    noload: bool = false,
    /// Don't unload on dlclose (RTLD_NODELETE)
    nodelete: bool = false,
    /// Report errors for objects (RTLD_DEEPBIND)
    deepbind: bool = false,
    /// Reserved
    _reserved: u1 = 0,
};

/// Convert LoadFlags to platform mode integer
fn flagsToMode(flags: LoadFlags) i32 {
    var mode: i32 = 0;

    if (flags.lazy) mode |= 0x0001; // RTLD_LAZY
    if (flags.now) mode |= 0x0002; // RTLD_NOW
    if (flags.global) mode |= 0x0100; // RTLD_GLOBAL
    if (flags.local) mode |= 0x0000; // RTLD_LOCAL (default)
    if (flags.noload) mode |= 0x0004; // RTLD_NOLOAD
    if (flags.nodelete) mode |= 0x1000; // RTLD_NODELETE
    if (flags.deepbind) mode |= 0x0008; // RTLD_DEEPBIND

    return mode;
}

// ============================================================================
// Platform Abstraction using Zig's std.DynLib
// ============================================================================

/// Internal storage for DynLib handles (since we return opaque pointers)
/// We store a mapping from handle pointers to actual DynLib instances
const DynLibStorage = struct {
    const max_libs = 256;
    var libs: [max_libs]?std.DynLib = [_]?std.DynLib{null} ** max_libs;
    var count: usize = 0;

    fn alloc() ?*std.DynLib {
        for (&libs) |*slot| {
            if (slot.* == null) {
                slot.* = std.DynLib{};
                return &(slot.*.?);
            }
        }
        return null;
    }

    fn findByHandle(handle: DLHandle) ?*std.DynLib {
        // Handle is pointer to DynLib slot
        const ptr: *?std.DynLib = @ptrCast(@alignCast(handle));
        if (ptr.* != null) {
            return &(ptr.*.?);
        }
        return null;
    }
};

/// Open a shared library using Zig's cross-platform DynLib
fn simulatedDlopen(path: []const u8, mode: i32) DLError!DLHandle {
    _ = mode; // DynLib doesn't support mode flags directly

    if (path.len == 0) {
        return DLError.LibraryNotFound;
    }

    // Allocate a DynLib slot
    const lib_slot = DynLibStorage.alloc() orelse return DLError.LibraryNotFound;

    // Convert path to null-terminated string for Zig's DynLib
    var path_buf: [4096]u8 = undefined;
    if (path.len >= path_buf.len) return DLError.LibraryNotFound;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    lib_slot.* = std.DynLib.open(path_buf[0..path.len :0]) catch {
        return DLError.LibraryNotFound;
    };

    // Return pointer to the slot as handle
    return @ptrCast(lib_slot);
}

/// Close a shared library
fn simulatedDlclose(handle: DLHandle) void {
    if (DynLibStorage.findByHandle(handle)) |lib| {
        lib.close();
        // Mark slot as free
        const slot: *?std.DynLib = @ptrCast(@alignCast(handle));
        slot.* = null;
    }
}

/// Lookup a symbol in a shared library
fn simulatedDlsym(handle: DLHandle, name: []const u8) DLError!*anyopaque {
    if (name.len == 0) {
        return DLError.SymbolNotFound;
    }

    const lib = DynLibStorage.findByHandle(handle) orelse return DLError.SymbolNotFound;

    // Convert name to null-terminated string
    var name_buf: [256]u8 = undefined;
    if (name.len >= name_buf.len) return DLError.SymbolNotFound;
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;

    const symbol = lib.lookup(*anyopaque, name_buf[0..name.len :0]) orelse {
        return DLError.SymbolNotFound;
    };

    return symbol;
}

// ============================================================================
// Extension Module Loading
// ============================================================================

/// Extension module suffix based on platform
pub const extension_suffix = switch (builtin.os.tag) {
    .linux => ".so",
    .macos => ".dylib",
    .windows => ".pyd",
    .freebsd, .netbsd, .openbsd => ".so",
    else => ".so",
};

/// Python extension module suffix (includes ABI tag)
pub fn getPythonExtensionSuffix() []const u8 {
    return ".cpython-313-darwin.so"; // Example for macOS Python 3.13
}

/// Module initialization function signature
pub const PyModInitFunc = *const fn () callconv(.C) ?*anyopaque;

/// Load a Python extension module
pub fn loadExtensionModule(allocator: Allocator, path: []const u8) DLError!PyModInitFunc {
    var loader = SharedLibLoader.init(allocator);
    defer loader.deinit();

    try loader.load(path, .{ .now = true, .local = true });

    // Look for PyInit_<modname> function
    const init_func = try loader.getSymbol("PyInit_module");
    return @ptrCast(init_func);
}

// ============================================================================
// Search Path Handling
// ============================================================================

/// Library search paths
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

    /// Add a search path
    pub fn addPath(self: *Self, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        try self.paths.append(owned);
    }

    /// Add paths from environment variable (e.g., LD_LIBRARY_PATH)
    pub fn addFromEnv(self: *Self, env_name: []const u8) !void {
        const env_value = std.process.getEnvVarOwned(self.allocator, env_name) catch {
            return; // Environment variable not set
        };
        defer self.allocator.free(env_value);

        var it = std.mem.splitScalar(u8, env_value, ':');
        while (it.next()) |path| {
            if (path.len > 0) {
                try self.addPath(path);
            }
        }
    }

    /// Find a library in the search paths
    pub fn findLibrary(self: *const Self, name: []const u8) ?[]const u8 {
        for (self.paths.items) |dir| {
            // Would construct full path and check if file exists
            _ = dir;
        }
        _ = name;
        return null;
    }
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;
var default_search_paths: ?SearchPaths = null;

/// Initialize the dynload_shlib module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Initialize search paths
pub fn initSearchPaths(allocator: Allocator) !*SearchPaths {
    if (default_search_paths == null) {
        default_search_paths = SearchPaths.init(allocator);

        // Add standard paths
        try default_search_paths.?.addPath("/usr/lib");
        try default_search_paths.?.addPath("/usr/local/lib");

        // Add LD_LIBRARY_PATH
        try default_search_paths.?.addFromEnv("LD_LIBRARY_PATH");

        // On macOS, also check DYLD_LIBRARY_PATH
        if (builtin.os.tag == .macos) {
            try default_search_paths.?.addFromEnv("DYLD_LIBRARY_PATH");
        }
    }
    return &default_search_paths.?;
}

/// Reset module state
pub fn reset() void {
    if (default_search_paths) |*paths| {
        paths.deinit();
    }
    default_search_paths = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "load flags" {
    const flags = LoadFlags{ .lazy = true, .global = true };
    const mode = flagsToMode(flags);
    try std.testing.expect(mode != 0);
}

test "shared lib loader init" {
    const allocator = std.testing.allocator;
    var loader = SharedLibLoader.init(allocator);
    defer loader.deinit();

    try std.testing.expect(loader.handle == null);
}

test "search paths" {
    const allocator = std.testing.allocator;
    var paths = SearchPaths.init(allocator);
    defer paths.deinit();

    try paths.addPath("/usr/lib");
    try paths.addPath("/usr/local/lib");

    try std.testing.expectEqual(@as(usize, 2), paths.paths.items.len);
}

test "extension suffix" {
    try std.testing.expect(extension_suffix.len > 0);
}
