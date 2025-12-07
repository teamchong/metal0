/// frozen - Frozen Modules
/// Mirrors cpython/Python/frozen.c
///
/// Support for frozen modules (bytecode compiled into the interpreter).
/// Allows distribution of Python applications as standalone executables.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Frozen Module Types
// ============================================================================

/// Frozen module entry
pub const FrozenModule = struct {
    /// Module name
    name: []const u8,
    /// Marshalled code object (bytecode)
    code: []const u8,
    /// Size of code (negative for package)
    size: i32,
    /// Whether this is a package
    is_package: bool = false,
    /// Original source code (optional, for debugging)
    source: ?[]const u8 = null,
};

/// Frozen module flags
pub const FrozenFlags = packed struct {
    /// Module is essential for bootstrap
    essential: bool = false,
    /// Module is from standard library
    stdlib: bool = false,
    /// Module contains only data
    data_only: bool = false,
    /// Reserved
    _reserved: u5 = 0,
};

// ============================================================================
// Frozen Module Registry
// ============================================================================

/// Registry of frozen modules
pub const FrozenRegistry = struct {
    const Self = @This();

    /// Module entries
    modules: hashmap_helper.StringHashMap(FrozenModule),
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .modules = hashmap_helper.StringHashMap(FrozenModule).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    /// Register a frozen module
    pub fn register(self: *Self, module: FrozenModule) !void {
        try self.modules.put(module.name, module);
    }

    /// Find a frozen module by name
    pub fn find(self: *const Self, name: []const u8) ?FrozenModule {
        return self.modules.get(name);
    }

    /// Check if a module is frozen
    pub fn isFrozen(self: *const Self, name: []const u8) bool {
        return self.modules.contains(name);
    }

    /// Get all frozen module names
    pub fn getNames(self: *const Self, allocator: Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        for (self.modules.keys()) |key| {
            try names.append(key);
        }
        return names.toOwnedSlice();
    }

    /// Remove a frozen module
    pub fn remove(self: *Self, name: []const u8) bool {
        return self.modules.remove(name);
    }
};

// ============================================================================
// Built-in Frozen Modules
// ============================================================================

/// Standard library frozen modules (essential for bootstrap)
pub const stdlib_frozen_modules = [_]FrozenModule{
    .{ .name = "_frozen_importlib", .code = &[_]u8{}, .size = 0 },
    .{ .name = "_frozen_importlib_external", .code = &[_]u8{}, .size = 0 },
    .{ .name = "zipimport", .code = &[_]u8{}, .size = 0 },
};

/// Test frozen modules
pub const test_frozen_modules = [_]FrozenModule{
    .{ .name = "__hello__", .code = &[_]u8{}, .size = 0 },
    .{ .name = "__phello__", .code = &[_]u8{}, .size = 0, .is_package = true },
};

// ============================================================================
// Module Import Interface
// ============================================================================

/// Result of loading a frozen module
pub const FrozenLoadResult = struct {
    /// Code object
    code: ?*anyopaque = null,
    /// Is a package
    is_package: bool = false,
    /// Error message if failed
    error_msg: ?[]const u8 = null,
};

/// Load a frozen module
pub fn loadFrozenModule(registry: *const FrozenRegistry, name: []const u8) FrozenLoadResult {
    const module = registry.find(name) orelse {
        return FrozenLoadResult{ .error_msg = "No such frozen module" };
    };

    // In real implementation, would unmarshal the code object
    return FrozenLoadResult{
        .code = null, // Would be unmarshalled code
        .is_package = module.is_package,
    };
}

/// Get frozen module source (if available)
pub fn getFrozenSource(registry: *const FrozenRegistry, name: []const u8) ?[]const u8 {
    const module = registry.find(name) orelse return null;
    return module.source;
}

// ============================================================================
// Frozen Package Support
// ============================================================================

/// Check if frozen module is a package
pub fn isFrozenPackage(registry: *const FrozenRegistry, name: []const u8) bool {
    const module = registry.find(name) orelse return false;
    return module.is_package or module.size < 0;
}

/// Get frozen package contents (submodules)
pub fn getFrozenPackageContents(
    registry: *const FrozenRegistry,
    package_name: []const u8,
    allocator: Allocator,
) ![][]const u8 {
    var contents = std.ArrayList([]const u8).init(allocator);
    const prefix_len = package_name.len + 1; // "package."

    var it = registry.modules.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name.len > prefix_len and
            std.mem.startsWith(u8, name, package_name) and
            name[package_name.len] == '.')
        {
            // This is a submodule
            const subname = name[prefix_len..];
            // Only direct children (no more dots)
            if (std.mem.indexOf(u8, subname, ".") == null) {
                try contents.append(subname);
            }
        }
    }

    return contents.toOwnedSlice();
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_registry: ?FrozenRegistry = null;

/// Initialize the frozen module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global frozen registry
pub fn getRegistry(allocator: Allocator) !*FrozenRegistry {
    if (global_registry == null) {
        global_registry = FrozenRegistry.init(allocator);

        // Register built-in frozen modules
        for (stdlib_frozen_modules) |module| {
            try global_registry.?.register(module);
        }
    }
    return &global_registry.?;
}

/// Reset module state
pub fn reset() void {
    if (global_registry) |*reg| {
        reg.deinit();
    }
    global_registry = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "frozen module struct" {
    const module = FrozenModule{
        .name = "test",
        .code = "bytecode",
        .size = 8,
        .is_package = false,
    };
    try std.testing.expectEqualStrings("test", module.name);
}

test "frozen registry" {
    const allocator = std.testing.allocator;
    var registry = FrozenRegistry.init(allocator);
    defer registry.deinit();

    const module = FrozenModule{
        .name = "mymodule",
        .code = "",
        .size = 0,
    };
    try registry.register(module);

    try std.testing.expect(registry.isFrozen("mymodule"));
    try std.testing.expect(!registry.isFrozen("notfrozen"));

    const found = registry.find("mymodule");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("mymodule", found.?.name);
}

test "frozen registry get names" {
    const allocator = std.testing.allocator;
    var registry = FrozenRegistry.init(allocator);
    defer registry.deinit();

    try registry.register(.{ .name = "mod1", .code = "", .size = 0 });
    try registry.register(.{ .name = "mod2", .code = "", .size = 0 });

    const names = try registry.getNames(allocator);
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);
}

test "is frozen package" {
    const allocator = std.testing.allocator;
    var registry = FrozenRegistry.init(allocator);
    defer registry.deinit();

    try registry.register(.{ .name = "pkg", .code = "", .size = -1, .is_package = true });
    try registry.register(.{ .name = "mod", .code = "", .size = 10 });

    try std.testing.expect(isFrozenPackage(&registry, "pkg"));
    try std.testing.expect(!isFrozenPackage(&registry, "mod"));
}
