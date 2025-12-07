/// importdl - Dynamic Import Loading
/// Mirrors cpython/Python/importdl.c
///
/// Provides the interface for dynamically loading extension modules.
/// This module abstracts the platform-specific dynamic loading mechanisms.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Import Errors
// ============================================================================

/// Errors that can occur during module import
pub const ImportError = error{
    ModuleNotFound,
    InitFunctionNotFound,
    InitFailed,
    InvalidModule,
    LoadError,
    VersionMismatch,
    OutOfMemory,
};

// ============================================================================
// Module Specification
// ============================================================================

/// Extension module specification
pub const ModuleSpec = struct {
    /// Module name (fully qualified)
    name: []const u8,
    /// File path to the shared library
    path: []const u8,
    /// Package name (if module is part of a package)
    package: ?[]const u8 = null,
    /// Module origin (file path or builtin)
    origin: ?[]const u8 = null,
    /// Whether module is a package
    is_package: bool = false,
    /// Submodule search locations
    submodule_search_locations: ?[][]const u8 = null,
};

// ============================================================================
// Module Definition
// ============================================================================

/// Module definition from extension
pub const ModuleDef = struct {
    /// Module name
    name: []const u8 = "",
    /// Module docstring
    doc: ?[]const u8 = null,
    /// Module size (-1 for module-level state)
    size: i64 = -1,
    /// Module methods
    methods: ?*anyopaque = null,
    /// Slot definitions
    slots: ?*anyopaque = null,
    /// Traverse function for GC
    traverse: ?*anyopaque = null,
    /// Clear function for GC
    clear: ?*anyopaque = null,
    /// Free function
    free: ?*anyopaque = null,
};

/// Module init function signature
pub const PyModInitFunc = *const fn () callconv(.C) ?*anyopaque;

// ============================================================================
// Extension Loader
// ============================================================================

/// Extension module loader
pub const ExtensionLoader = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Loaded modules cache
    loaded_modules: hashmap_helper.StringHashMap(*LoadedModule),
    /// Search paths for extensions
    search_paths: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .loaded_modules = hashmap_helper.StringHashMap(*LoadedModule).init(allocator),
            .search_paths = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.loaded_modules.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.loaded_modules.deinit();

        for (self.search_paths.items) |path| {
            self.allocator.free(path);
        }
        self.search_paths.deinit();
    }

    /// Add a search path
    pub fn addSearchPath(self: *Self, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        try self.search_paths.append(owned);
    }

    /// Load an extension module
    pub fn loadModule(self: *Self, spec: ModuleSpec) ImportError!*LoadedModule {
        // Check if already loaded
        if (self.loaded_modules.get(spec.name)) |module| {
            return module;
        }

        // Find the module file
        const path = try self.findModuleFile(spec);

        // Load the shared library
        const module = try self.allocator.create(LoadedModule);
        errdefer self.allocator.destroy(module);

        module.* = LoadedModule.init(self.allocator, spec.name, path);
        try module.load();

        // Cache the loaded module
        try self.loaded_modules.put(spec.name, module);

        return module;
    }

    /// Find module file in search paths
    fn findModuleFile(self: *Self, spec: ModuleSpec) ImportError![]const u8 {
        // If path is provided, use it directly
        if (spec.path.len > 0) {
            return spec.path;
        }

        // Search in paths
        for (self.search_paths.items) |_| {
            // Would construct full path and check if file exists
        }

        return ImportError.ModuleNotFound;
    }

    /// Unload a module
    pub fn unloadModule(self: *Self, name: []const u8) void {
        if (self.loaded_modules.fetchSwapRemove(name)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    /// Check if module is loaded
    pub fn isLoaded(self: *const Self, name: []const u8) bool {
        return self.loaded_modules.contains(name);
    }
};

// ============================================================================
// Loaded Module
// ============================================================================

/// A loaded extension module
pub const LoadedModule = struct {
    const Self = @This();

    /// Module name
    name: []const u8,
    /// Module file path
    path: []const u8,
    /// Handle to loaded library
    handle: ?*anyopaque = null,
    /// Module definition
    def: ?ModuleDef = null,
    /// Module object (PyObject*)
    module_obj: ?*anyopaque = null,
    /// Init function
    init_func: ?PyModInitFunc = null,
    /// Is initialized
    initialized: bool = false,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, path: []const u8) Self {
        return Self{
            .name = name,
            .path = path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Would unload the library
        self.handle = null;
        self.initialized = false;
    }

    /// Load the module
    pub fn load(self: *Self) ImportError!void {
        // Simulate loading
        self.handle = @as(*anyopaque, @ptrFromInt(@intFromPtr(self.path.ptr)));

        // Find init function
        const init_name = try self.getInitFunctionName();
        _ = init_name;

        // Would call dlsym/GetProcAddress here
        self.init_func = null; // Simulated
    }

    /// Get the PyInit function name
    fn getInitFunctionName(self: *const Self) ![]const u8 {
        _ = self;
        return "PyInit_module";
    }

    /// Initialize the module
    pub fn initialize(self: *Self) ImportError!*anyopaque {
        if (self.initialized) {
            return self.module_obj orelse return ImportError.InitFailed;
        }

        if (self.init_func) |init_fn| {
            self.module_obj = init_fn();
            if (self.module_obj == null) {
                return ImportError.InitFailed;
            }
        } else {
            return ImportError.InitFunctionNotFound;
        }

        self.initialized = true;
        return self.module_obj.?;
    }

    /// Get module attribute
    pub fn getAttribute(self: *const Self, name: []const u8) ?*anyopaque {
        _ = self;
        _ = name;
        return null;
    }
};

// ============================================================================
// Extension Suffixes
// ============================================================================

/// Get extension file suffixes for current platform
pub fn getExtensionSuffixes() []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{ ".pyd", ".dll" },
        .macos => &[_][]const u8{ ".cpython-313-darwin.so", ".abi3.so", ".dylib", ".so" },
        .linux => &[_][]const u8{ ".cpython-313-x86_64-linux-gnu.so", ".abi3.so", ".so" },
        else => &[_][]const u8{".so"},
    };
}

/// Get the primary extension suffix
pub fn getPrimaryExtensionSuffix() []const u8 {
    return switch (builtin.os.tag) {
        .windows => ".pyd",
        .macos => ".so",
        .linux => ".so",
        else => ".so",
    };
}

// ============================================================================
// Multi-phase Initialization
// ============================================================================

/// Module slot types (PEP 489)
pub const ModuleSlot = enum(i32) {
    /// Slot for module creation function
    create = 1,
    /// Slot for module exec function
    exec = 2,
    /// Indicates GIL not needed
    gil_not_used = 3,
};

/// Module slot definition
pub const ModuleSlotDef = struct {
    slot: ModuleSlot,
    value: *anyopaque,
};

/// Check if module supports multi-phase init
pub fn supportsMultiPhaseInit(def: *const ModuleDef) bool {
    return def.slots != null;
}

// ============================================================================
// Module State
// ============================================================================

/// Per-interpreter module state
pub const ModuleState = struct {
    /// Module definition
    def: *ModuleDef,
    /// Module state data
    state: ?*anyopaque = null,
    /// State size
    size: usize = 0,
};

/// Get module state
pub fn getModuleState(module: *anyopaque) ?*anyopaque {
    _ = module;
    return null;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;
var global_loader: ?ExtensionLoader = null;

/// Initialize the importdl module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global extension loader
pub fn getLoader(allocator: Allocator) *ExtensionLoader {
    if (global_loader == null) {
        global_loader = ExtensionLoader.init(allocator);
    }
    return &global_loader.?;
}

/// Reset module state
pub fn reset() void {
    if (global_loader) |*loader| {
        loader.deinit();
    }
    global_loader = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "module spec" {
    const spec = ModuleSpec{
        .name = "test",
        .path = "/usr/lib/python/test.so",
    };
    try std.testing.expectEqualStrings("test", spec.name);
}

test "extension loader init" {
    const allocator = std.testing.allocator;
    var loader = ExtensionLoader.init(allocator);
    defer loader.deinit();

    try std.testing.expect(loader.loaded_modules.count() == 0);
}

test "search paths" {
    const allocator = std.testing.allocator;
    var loader = ExtensionLoader.init(allocator);
    defer loader.deinit();

    try loader.addSearchPath("/usr/lib/python3.13/lib-dynload");
    try std.testing.expectEqual(@as(usize, 1), loader.search_paths.items.len);
}

test "extension suffixes" {
    const suffixes = getExtensionSuffixes();
    try std.testing.expect(suffixes.len > 0);
}

test "loaded module" {
    const allocator = std.testing.allocator;
    var module = LoadedModule.init(allocator, "test", "/path/to/test.so");
    defer module.deinit();

    try std.testing.expect(!module.initialized);
}

test "module slot types" {
    try std.testing.expectEqual(@as(i32, 1), @intFromEnum(ModuleSlot.create));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(ModuleSlot.exec));
}
