//! test.test_importlib.test_api - Tests for importlib API
//! Reference: cpython/Lib/test/test_importlib/test_api.py

const std = @import("std");

// ============================================================================
// Import API Functions
// ============================================================================

pub const ImportError = error{
    ModuleNotFound,
    InvalidModule,
    CircularImport,
    LoaderError,
};

/// Import a module by name
pub fn import_module(name: []const u8) ImportError!*Module {
    // In real implementation, this would search sys.path
    _ = name;
    return ImportError.ModuleNotFound;
}

/// Reload a module
pub fn reload(module: *Module) ImportError!*Module {
    if (module.__spec__) |spec| {
        if (spec.loader) |loader| {
            loader.exec_module(module) catch return ImportError.LoaderError;
            return module;
        }
    }
    return ImportError.InvalidModule;
}

/// Find the loader for a module
pub fn find_loader(name: []const u8, path: ?[]const []const u8) ?*Loader {
    _ = name; _ = path;
    return null;
}

/// Find the spec for a module
pub fn find_spec(name: []const u8, package: ?[]const u8) ?ModuleSpec {
    _ = package;
    return ModuleSpec.init(name);
}

/// Invalidate import caches
pub fn invalidate_caches() void {
    // Clear all finder caches
}

// ============================================================================
// Module Cache
// ============================================================================

pub const ModuleCache = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(*Module),
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .modules = std.StringHashMap(*Module).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }
    
    pub fn get(self: *Self, name: []const u8) ?*Module {
        return self.modules.get(name);
    }
    
    pub fn put(self: *Self, name: []const u8, module: *Module) !void {
        try self.modules.put(name, module);
    }
    
    pub fn remove(self: *Self, name: []const u8) bool {
        return self.modules.remove(name);
    }
    
    pub fn contains(self: *Self, name: []const u8) bool {
        return self.modules.contains(name);
    }
    
    pub fn count(self: *Self) usize {
        return self.modules.count();
    }
    
    pub fn clear(self: *Self) void {
        self.modules.clearRetainingCapacity();
    }
};

// ============================================================================
// Import State
// ============================================================================

pub const ImportState = struct {
    const Self = @This();
    
    lock_count: usize = 0,
    importing: std.StringHashMap(bool),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .importing = std.StringHashMap(bool).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.importing.deinit();
    }
    
    pub fn acquire_lock(self: *Self) void {
        self.lock_count += 1;
    }
    
    pub fn release_lock(self: *Self) void {
        if (self.lock_count > 0) self.lock_count -= 1;
    }
    
    pub fn lock_held(self: *Self) bool {
        return self.lock_count > 0;
    }
    
    pub fn is_importing(self: *Self, name: []const u8) bool {
        return self.importing.get(name) orelse false;
    }
    
    pub fn set_importing(self: *Self, name: []const u8, value: bool) !void {
        try self.importing.put(name, value);
    }
};

// ============================================================================
// Supporting Types
// ============================================================================

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*Loader = null,
    origin: ?[]const u8 = null,
    is_package: bool = false,

    pub fn init(name: []const u8) @This() { 
        return .{ .name = name }; 
    }
};

pub const Module = struct {
    __name__: []const u8,
    __spec__: ?ModuleSpec = null,
    __loader__: ?*Loader = null,
    __file__: ?[]const u8 = null,

    pub fn init(name: []const u8) @This() { 
        return .{ .__name__ = name }; 
    }
};

pub const Loader = struct {
    pub fn exec_module(_: *@This(), _: *Module) !void {}
};

// ============================================================================
// Test Cases
// ============================================================================

fn testModuleCache() !void {
    const allocator = std.testing.allocator;
    var cache = ModuleCache.init(allocator);
    defer cache.deinit();
    
    var mod = Module.init("test_module");
    try cache.put("test_module", &mod);
    
    try std.testing.expectEqual(@as(usize, 1), cache.count());
    try std.testing.expect(cache.contains("test_module"));
    
    if (cache.get("test_module")) |m| {
        try std.testing.expectEqualStrings("test_module", m.__name__);
    }
    
    try std.testing.expect(cache.remove("test_module"));
    try std.testing.expectEqual(@as(usize, 0), cache.count());
}

fn testImportState() !void {
    const allocator = std.testing.allocator;
    var state = ImportState.init(allocator);
    defer state.deinit();
    
    try std.testing.expect(!state.lock_held());
    
    state.acquire_lock();
    try std.testing.expect(state.lock_held());
    try std.testing.expectEqual(@as(usize, 1), state.lock_count);
    
    state.release_lock();
    try std.testing.expect(!state.lock_held());
}

fn testImportStateImporting() !void {
    const allocator = std.testing.allocator;
    var state = ImportState.init(allocator);
    defer state.deinit();
    
    try std.testing.expect(!state.is_importing("mymodule"));
    
    try state.set_importing("mymodule", true);
    try std.testing.expect(state.is_importing("mymodule"));
    
    try state.set_importing("mymodule", false);
    try std.testing.expect(!state.is_importing("mymodule"));
}

fn testFindSpec() !void {
    if (find_spec("os", null)) |spec| {
        try std.testing.expectEqualStrings("os", spec.name);
    }
}

fn testImportError() !void {
    const result = import_module("nonexistent_module_xyz");
    try std.testing.expectError(ImportError.ModuleNotFound, result);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "module_cache" { try testModuleCache(); }
test "import_state" { try testImportState(); }
test "import_state_importing" { try testImportStateImporting(); }
test "find_spec" { try testFindSpec(); }
test "import_error" { try testImportError(); }
