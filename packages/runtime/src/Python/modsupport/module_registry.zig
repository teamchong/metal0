/// module_registry - Extension Module Registry
/// Mirrors parts of cpython/Python/modsupport.c related to module registration
///
/// Provides a registry for tracking loaded extension modules and their state.
/// This is used for module lifecycle management in the runtime.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Extension module registry
pub const ModuleRegistry = struct {
    modules: hashmap_helper.StringHashMap(*anyopaque),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = hashmap_helper.StringHashMap(*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    pub fn register(self: *Self, name: []const u8, module: *anyopaque) !void {
        try self.modules.put(name, module);
    }

    pub fn lookup(self: *Self, name: []const u8) ?*anyopaque {
        return self.modules.get(name);
    }

    pub fn unregister(self: *Self, name: []const u8) void {
        _ = self.modules.remove(name);
    }
};

// Thread-local module registry
threadlocal var module_registry: ?ModuleRegistry = null;

pub fn getModuleRegistry(allocator: std.mem.Allocator) *ModuleRegistry {
    if (module_registry == null) {
        module_registry = ModuleRegistry.init(allocator);
    }
    return &module_registry.?;
}

/// Initialize module support
pub fn init() void {
    // Initialize any global state
}

/// Finalize module support
pub fn fini() void {
    if (module_registry) |*reg| {
        reg.deinit();
        module_registry = null;
    }
}

// Tests
test "module registry" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    var dummy: u8 = 0;
    try registry.register("test_module", &dummy);

    const found = registry.lookup("test_module");
    try std.testing.expect(found != null);

    const not_found = registry.lookup("nonexistent");
    try std.testing.expect(not_found == null);
}
