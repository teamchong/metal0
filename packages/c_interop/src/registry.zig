// C Library Mapping Registry
// Central registry of all available library mappings
// Used for ctypes-style FFI to call real C libraries

const std = @import("std");
const mapper = @import("mapper.zig");
const detection = @import("detection.zig");

// Re-export public APIs
pub const ImportContext = detection.ImportContext;
pub const MappingRegistry = mapper.MappingRegistry;
pub const FunctionMapping = mapper.FunctionMapping;

/// Global registry containing all available mappings
pub var global_registry: ?*mapper.MappingRegistry = null;

/// Initialize the global registry with all known mappings
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    // Empty for now - mappings will be added via ctypes/cffi at runtime
    const all_mappings = [_]*const mapper.CLibraryMapping{};

    const registry = try allocator.create(mapper.MappingRegistry);
    registry.* = mapper.MappingRegistry.init(allocator, &all_mappings);
    global_registry = registry;
}

/// Cleanup the global registry
pub fn deinitGlobalRegistry(allocator: std.mem.Allocator) void {
    if (global_registry) |registry| {
        allocator.destroy(registry);
        global_registry = null;
    }
}

/// Get the global registry (must be initialized first)
pub fn getGlobalRegistry() !*mapper.MappingRegistry {
    return global_registry orelse error.RegistryNotInitialized;
}

/// Check if a package is supported
pub fn isPackageSupported(package_name: []const u8) bool {
    if (global_registry) |registry| {
        return registry.findByPackage(package_name) != null;
    }
    return false;
}

/// Get all supported package names
pub fn getSupportedPackages(allocator: std.mem.Allocator) ![]const []const u8 {
    const registry = try getGlobalRegistry();

    var packages = std.ArrayList([]const u8).init(allocator);
    defer packages.deinit();

    for (registry.mappings) |mapping| {
        try packages.append(mapping.package_name);
    }

    return packages.toOwnedSlice();
}
