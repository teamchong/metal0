//! test.test_module.test_api - Module API testing
//! Tests for Python's module API (import_module, reload, find_spec)
//! Reference: CPython Lib/test/test_importlib/test_api.py

const std = @import("std");
const importlib = @import("../../importlib.zig");
const machinery = @import("../../importlib/machinery.zig");

// ============================================================================
// Types from importlib
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;
pub const ImportError = importlib.ImportError;

// ============================================================================
// Import Module API
// ============================================================================

/// Result of import_module operation
pub const ImportResult = struct {
    name: []const u8,
    success: bool,
    module: ?*anyopaque = null,
    error_msg: ?[]const u8 = null,
    spec: ?ModuleSpec = null,

    pub fn isSuccess(self: ImportResult) bool {
        return self.success;
    }

    pub fn hasModule(self: ImportResult) bool {
        return self.module != null;
    }
};

/// Mock import_module function for testing
pub fn importModule(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) ImportResult {
    _ = allocator;

    // Check for builtin modules
    if (machinery.BuiltinImporter.findSpec(name, null, null)) |spec| {
        return .{
            .name = name,
            .success = true,
            .spec = spec,
        };
    }

    // Handle relative imports
    if (name.len > 0 and name[0] == '.') {
        if (package == null) {
            return .{
                .name = name,
                .success = false,
                .error_msg = "attempted relative import with no known parent package",
            };
        }
    }

    // Default: module not found
    return .{
        .name = name,
        .success = false,
        .error_msg = "No module named",
    };
}

/// Import a submodule from a package
pub fn importSubmodule(allocator: std.mem.Allocator, package_name: []const u8, submodule_name: []const u8) ImportResult {
    _ = allocator;
    // Build full module name
    var full_name: [256]u8 = undefined;
    const full_len = std.fmt.bufPrint(&full_name, "{s}.{s}", .{ package_name, submodule_name }) catch {
        return .{
            .name = submodule_name,
            .success = false,
            .error_msg = "Module name too long",
        };
    };

    return importModule(std.heap.page_allocator, full_len, package_name);
}

// ============================================================================
// Find Spec API
// ============================================================================

/// Find module specification without importing
pub fn findSpec(allocator: std.mem.Allocator, name: []const u8, path: ?[]const []const u8, target: ?*anyopaque) ?ModuleSpec {
    _ = allocator;
    _ = path;
    _ = target;

    // Check builtin modules first
    if (machinery.BuiltinImporter.findSpec(name, null, null)) |spec| {
        return spec;
    }

    // Check frozen modules
    if (machinery.FrozenImporter.findSpec(name, null, null)) |spec| {
        return spec;
    }

    return null;
}

/// Find loader for module
pub fn findLoader(allocator: std.mem.Allocator, name: []const u8, path: ?[]const []const u8) ?*anyopaque {
    _ = allocator;
    _ = name;
    _ = path;
    return null;
}

// ============================================================================
// Module Cache (sys.modules simulation)
// ============================================================================

/// Simulates sys.modules for testing
pub const ModuleCache = struct {
    modules: std.StringHashMap(*anyopaque),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = std.StringHashMap(*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    /// Get a cached module
    pub fn get(self: *const Self, name: []const u8) ?*anyopaque {
        return self.modules.get(name);
    }

    /// Cache a module
    pub fn put(self: *Self, name: []const u8, module: *anyopaque) !void {
        try self.modules.put(name, module);
    }

    /// Remove a module from cache
    pub fn remove(self: *Self, name: []const u8) bool {
        return self.modules.remove(name);
    }

    /// Check if module is cached
    pub fn contains(self: *const Self, name: []const u8) bool {
        return self.modules.contains(name);
    }

    /// Clear all cached modules
    pub fn clear(self: *Self) void {
        self.modules.clearRetainingCapacity();
    }

    /// Get number of cached modules
    pub fn count(self: *const Self) usize {
        return self.modules.count();
    }
};

// ============================================================================
// API Error Types
// ============================================================================

/// Error types for import operations
pub const ModuleError = error{
    ModuleNotFound,
    ImportFailed,
    CircularImport,
    InvalidName,
    RelativeImportNoPackage,
    LoaderNotFound,
    ExecFailed,
};

/// Error details for debugging
pub const ErrorInfo = struct {
    error_type: ModuleError,
    module_name: []const u8,
    message: []const u8,
    cause: ?[]const u8 = null,

    pub fn format(self: ErrorInfo, writer: anytype) !void {
        try writer.print("{s}: {s}", .{ @errorName(self.error_type), self.message });
        if (self.cause) |cause| {
            try writer.print(" (caused by: {s})", .{cause});
        }
    }
};

// ============================================================================
// Invalidate Caches API
// ============================================================================

/// Invalidate all module caches
pub fn invalidateCaches() void {
    // In a real implementation, this would call invalidate_caches on all finders
    machinery.BuiltinImporter.invalidateCaches();
    machinery.FrozenImporter.invalidateCaches();
}

// ============================================================================
// Test Functions
// ============================================================================

/// Test importModule for builtin
pub fn testImportModuleBuiltin(allocator: std.mem.Allocator) !void {
    const result = importModule(allocator, "sys", null);
    try std.testing.expect(result.isSuccess());
}

/// Test importModule not found
pub fn testImportModuleNotFound(allocator: std.mem.Allocator) !void {
    const result = importModule(allocator, "nonexistent_module_xyz123", null);
    try std.testing.expect(!result.isSuccess());
}

/// Test findSpec for builtin
pub fn testFindSpecBuiltin(allocator: std.mem.Allocator) !void {
    const spec = findSpec(allocator, "sys", null, null);
    try std.testing.expect(spec != null);
}

/// Test findSpec not found
pub fn testFindSpecNotFound(allocator: std.mem.Allocator) !void {
    const spec = findSpec(allocator, "xyz_no_such_module", null, null);
    try std.testing.expect(spec == null);
}

/// Test ModuleCache
pub fn testModuleCache(allocator: std.mem.Allocator) !void {
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var dummy: u8 = 42;
    try cache.put("cached_mod", &dummy);
    try std.testing.expect(cache.contains("cached_mod"));
    try std.testing.expect(cache.get("cached_mod") != null);
}

/// Test relative import error
pub fn testRelativeImportError(allocator: std.mem.Allocator) !void {
    const result = importModule(allocator, ".submodule", null);
    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(result.error_msg != null);
}

// ============================================================================
// Zig Tests
// ============================================================================

test "ImportResult isSuccess true" {
    const result = ImportResult{ .name = "test", .success = true };
    try std.testing.expect(result.isSuccess());
}

test "ImportResult isSuccess false" {
    const result = ImportResult{ .name = "test", .success = false };
    try std.testing.expect(!result.isSuccess());
}

test "ImportResult hasModule true" {
    var dummy: u8 = 0;
    const result = ImportResult{ .name = "test", .success = true, .module = &dummy };
    try std.testing.expect(result.hasModule());
}

test "ImportResult hasModule false" {
    const result = ImportResult{ .name = "test", .success = true, .module = null };
    try std.testing.expect(!result.hasModule());
}

test "importModule builtin sys" {
    const allocator = std.testing.allocator;
    const result = importModule(allocator, "sys", null);
    try std.testing.expect(result.isSuccess());
}

test "importModule builtin builtins" {
    const allocator = std.testing.allocator;
    const result = importModule(allocator, "builtins", null);
    try std.testing.expect(result.isSuccess());
}

test "importModule not found" {
    const allocator = std.testing.allocator;
    const result = importModule(allocator, "definitely_not_a_real_module", null);
    try std.testing.expect(!result.isSuccess());
}

test "importModule relative no package" {
    const allocator = std.testing.allocator;
    const result = importModule(allocator, ".relative", null);
    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(result.error_msg != null);
}

test "findSpec builtin" {
    const allocator = std.testing.allocator;
    const spec = findSpec(allocator, "sys", null, null);
    try std.testing.expect(spec != null);
    try std.testing.expectEqualStrings("sys", spec.?.name);
}

test "findSpec builtins" {
    const allocator = std.testing.allocator;
    const spec = findSpec(allocator, "builtins", null, null);
    try std.testing.expect(spec != null);
}

test "findSpec not found" {
    const allocator = std.testing.allocator;
    const spec = findSpec(allocator, "xyz_not_real", null, null);
    try std.testing.expect(spec == null);
}

test "findLoader returns null" {
    const allocator = std.testing.allocator;
    const loader = findLoader(allocator, "any", null);
    try std.testing.expect(loader == null);
}

test "ModuleCache init" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();
    try std.testing.expectEqual(@as(usize, 0), cache.count());
}

test "ModuleCache put and get" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var dummy: u8 = 1;
    try cache.put("mod", &dummy);
    const got = cache.get("mod");
    try std.testing.expect(got != null);
}

test "ModuleCache contains true" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var dummy: u8 = 1;
    try cache.put("exists", &dummy);
    try std.testing.expect(cache.contains("exists"));
}

test "ModuleCache contains false" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();
    try std.testing.expect(!cache.contains("missing"));
}

test "ModuleCache remove existing" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var dummy: u8 = 1;
    try cache.put("to_remove", &dummy);
    try std.testing.expect(cache.remove("to_remove"));
    try std.testing.expect(!cache.contains("to_remove"));
}

test "ModuleCache remove nonexistent" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();
    try std.testing.expect(!cache.remove("not_there"));
}

test "ModuleCache clear" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var d1: u8 = 1;
    var d2: u8 = 2;
    try cache.put("a", &d1);
    try cache.put("b", &d2);
    cache.clear();
    try std.testing.expectEqual(@as(usize, 0), cache.count());
}

test "ModuleCache count" {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();

    var d1: u8 = 1;
    var d2: u8 = 2;
    var d3: u8 = 3;
    try cache.put("a", &d1);
    try cache.put("b", &d2);
    try cache.put("c", &d3);
    try std.testing.expectEqual(@as(usize, 3), cache.count());
}

test "ModuleError enum" {
    const err: ModuleError = .ModuleNotFound;
    try std.testing.expect(err == .ModuleNotFound);
}

test "ErrorInfo struct" {
    const info = ErrorInfo{
        .error_type = .ModuleNotFound,
        .module_name = "missing",
        .message = "Module not found",
    };
    try std.testing.expectEqualStrings("missing", info.module_name);
}

test "invalidateCaches does not crash" {
    invalidateCaches();
    // Should complete without error
}

test "importSubmodule" {
    const allocator = std.testing.allocator;
    const result = importSubmodule(allocator, "os", "path");
    // os.path likely not found in our mock, but should not crash
    _ = result;
}
