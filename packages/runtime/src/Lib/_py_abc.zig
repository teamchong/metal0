/// _py_abc - Python Abstract Base Classes Implementation
/// Mirrors cpython/Lib/_py_abc.py
///
/// Pure Python implementation of ABC (Abstract Base Class) machinery.
/// Provides ABCMeta metaclass and ABC base class functionality.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const Allocator = std.mem.Allocator;

// ============================================================================
// ABC Registry
// ============================================================================

/// Registry for tracking abstract methods and virtual subclasses
pub const ABCRegistry = struct {
    const Self = @This();

    /// Registered virtual subclasses (type ID -> list of subclass IDs)
    virtual_subclasses: std.AutoHashMap(u64, std.ArrayList(u64)),
    /// Abstract methods cache (type ID -> set of method names)
    abstract_methods: std.AutoHashMap(u64, hashmap_helper.StringHashMap(void)),
    /// Negative cache for isinstance checks
    negative_cache: std.AutoHashMap(u64, std.AutoHashMap(u64, void)),
    /// Cache version counter
    cache_version: u64 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .virtual_subclasses = std.AutoHashMap(u64, std.ArrayList(u64)).init(allocator),
            .abstract_methods = std.AutoHashMap(u64, hashmap_helper.StringHashMap(void)).init(allocator),
            .negative_cache = std.AutoHashMap(u64, std.AutoHashMap(u64, void)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var vs_it = self.virtual_subclasses.valueIterator();
        while (vs_it.next()) |list| {
            list.deinit();
        }
        self.virtual_subclasses.deinit();

        var am_it = self.abstract_methods.valueIterator();
        while (am_it.next()) |set| {
            var s = set;
            s.deinit();
        }
        self.abstract_methods.deinit();

        var nc_it = self.negative_cache.valueIterator();
        while (nc_it.next()) |cache| {
            var c = cache;
            c.deinit();
        }
        self.negative_cache.deinit();
    }

    /// Register a virtual subclass
    pub fn registerVirtualSubclass(self: *Self, abc_id: u64, subclass_id: u64) !void {
        const result = try self.virtual_subclasses.getOrPut(abc_id);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u64).init(self.allocator);
        }
        try result.value_ptr.append(subclass_id);
        self.invalidateCache();
    }

    /// Check if type is a virtual subclass
    pub fn isVirtualSubclass(self: *const Self, abc_id: u64, type_id: u64) bool {
        if (self.virtual_subclasses.get(abc_id)) |subclasses| {
            for (subclasses.items) |id| {
                if (id == type_id) return true;
            }
        }
        return false;
    }

    /// Register abstract methods for a type
    pub fn registerAbstractMethods(self: *Self, type_id: u64, methods: []const []const u8) !void {
        const result = try self.abstract_methods.getOrPut(type_id);
        if (!result.found_existing) {
            result.value_ptr.* = hashmap_helper.StringHashMap(void).init(self.allocator);
        }
        for (methods) |method| {
            try result.value_ptr.put(method, {});
        }
    }

    /// Get abstract methods for a type
    pub fn getAbstractMethods(self: *const Self, type_id: u64) ?*const hashmap_helper.StringHashMap(void) {
        return if (self.abstract_methods.getPtr(type_id)) |ptr| ptr else null;
    }

    /// Invalidate caches (called when hierarchy changes)
    pub fn invalidateCache(self: *Self) void {
        self.cache_version += 1;
        // Clear negative cache
        var it = self.negative_cache.valueIterator();
        while (it.next()) |cache| {
            var c = cache;
            c.clearRetainingCapacity();
        }
    }

    /// Get cache version
    pub fn getCacheVersion(self: *const Self) u64 {
        return self.cache_version;
    }
};

// ============================================================================
// ABCMeta
// ============================================================================

/// ABCMeta metaclass implementation
pub const ABCMeta = struct {
    const Self = @This();

    /// Type ID
    type_id: u64,
    /// Name
    name: []const u8,
    /// Abstract methods
    abstract_methods: hashmap_helper.StringHashMap(void),
    /// Registry reference
    registry: *ABCRegistry,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, registry: *ABCRegistry, name: []const u8, type_id: u64) Self {
        return Self{
            .allocator = allocator,
            .registry = registry,
            .name = name,
            .type_id = type_id,
            .abstract_methods = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.abstract_methods.deinit();
    }

    /// Register this ABC's abstract methods
    pub fn registerAbstractMethod(self: *Self, method: []const u8) !void {
        try self.abstract_methods.put(method, {});
    }

    /// Check if a method is abstract
    pub fn isAbstractMethod(self: *const Self, method: []const u8) bool {
        return self.abstract_methods.contains(method);
    }

    /// Get all abstract method names
    pub fn getAbstractMethodNames(self: *const Self, allocator: Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        var it = self.abstract_methods.keyIterator();
        while (it.next()) |key| {
            try names.append(key.*);
        }
        return names.toOwnedSlice();
    }

    /// Register a virtual subclass
    pub fn register(self: *Self, subclass_id: u64) !void {
        try self.registry.registerVirtualSubclass(self.type_id, subclass_id);
    }

    /// Check if type is instance of this ABC
    pub fn isInstance(self: *const Self, type_id: u64) bool {
        return self.registry.isVirtualSubclass(self.type_id, type_id);
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if an object has all required abstract methods implemented
pub fn hasAllAbstractMethods(
    abstract_methods: *const hashmap_helper.StringHashMap(void),
    implemented_methods: []const []const u8,
) bool {
    var it = abstract_methods.keyIterator();
    while (it.next()) |abstract| {
        var found = false;
        for (implemented_methods) |impl| {
            if (std.mem.eql(u8, abstract.*, impl)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

/// Get the abstractmethod decorator marker
pub fn abstractmethod(func_name: []const u8) []const u8 {
    // In real implementation, would mark the function
    return func_name;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_registry: ?ABCRegistry = null;

/// Initialize the _py_abc module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global registry
pub fn getRegistry(allocator: Allocator) *ABCRegistry {
    if (global_registry == null) {
        global_registry = ABCRegistry.init(allocator);
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

test "abc registry init" {
    const allocator = std.testing.allocator;
    var registry = ABCRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(u64, 0), registry.cache_version);
}

test "virtual subclass registration" {
    const allocator = std.testing.allocator;
    var registry = ABCRegistry.init(allocator);
    defer registry.deinit();

    try registry.registerVirtualSubclass(1, 100);
    try registry.registerVirtualSubclass(1, 101);

    try std.testing.expect(registry.isVirtualSubclass(1, 100));
    try std.testing.expect(registry.isVirtualSubclass(1, 101));
    try std.testing.expect(!registry.isVirtualSubclass(1, 102));
}

test "abstract methods registration" {
    const allocator = std.testing.allocator;
    var registry = ABCRegistry.init(allocator);
    defer registry.deinit();

    const methods = [_][]const u8{ "method1", "method2" };
    try registry.registerAbstractMethods(1, &methods);

    const registered = registry.getAbstractMethods(1);
    try std.testing.expect(registered != null);
    try std.testing.expect(registered.?.contains("method1"));
    try std.testing.expect(registered.?.contains("method2"));
}

test "cache invalidation" {
    const allocator = std.testing.allocator;
    var registry = ABCRegistry.init(allocator);
    defer registry.deinit();

    const v1 = registry.getCacheVersion();
    registry.invalidateCache();
    const v2 = registry.getCacheVersion();

    try std.testing.expect(v2 > v1);
}

test "has all abstract methods" {
    const allocator = std.testing.allocator;
    var methods = hashmap_helper.StringHashMap(void).init(allocator);
    defer methods.deinit();

    try methods.put("foo", {});
    try methods.put("bar", {});

    const impl1 = [_][]const u8{ "foo", "bar", "baz" };
    try std.testing.expect(hasAllAbstractMethods(&methods, &impl1));

    const impl2 = [_][]const u8{"foo"};
    try std.testing.expect(!hasAllAbstractMethods(&methods, &impl2));
}
