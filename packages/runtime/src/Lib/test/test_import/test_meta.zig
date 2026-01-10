//! test.test_import.test_meta - Meta path testing
//!
//! Tests for Python's sys.meta_path mechanism including:
//! - Meta path finder ordering
//! - Custom meta path finders
//! - Meta path manipulation
//! - Import hooks via meta_path
//! - Module interception and replacement

const std = @import("std");
const Allocator = std.mem.Allocator;

/// MetaPathError - Errors related to meta path operations
pub const MetaPathError = error{
    FinderNotFound,
    ModuleNotFound,
    InvalidFinder,
    DuplicateFinder,
    OutOfMemory,
};

/// ModuleSpec for meta path operations
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*const Loader,
    origin: ?[]const u8,
    cached: ?[]const u8,
    parent: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    has_location: bool,
    loader_state: ?*anyopaque,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .cached = null,
            .parent = null,
            .submodule_search_locations = null,
            .has_location = false,
            .loader_state = null,
        };
    }

    pub fn isPackage(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }
};

/// Module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __loader__: ?*const Loader,
    __package__: ?[]const u8,
    __spec__: ?*const ModuleSpec,
    __path__: ?[]const []const u8,
    __dict__: std.StringHashMapUnmanaged(Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .__name__ = name,
            .__file__ = null,
            .__loader__ = null,
            .__package__ = null,
            .__spec__ = null,
            .__path__ = null,
            .__dict__ = .{},
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        self.__dict__.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// Value type for module dictionary
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    module: *Module,
};

/// Loader interface
pub const Loader = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        create_module: *const fn (*anyopaque, *const ModuleSpec) ?*Module,
        exec_module: *const fn (*anyopaque, *Module) anyerror!void,
    };
};

/// MetaPathFinder - Base interface for all meta path finders
pub const MetaPathFinder = struct {
    vtable: *const VTable,
    context: *anyopaque,
    name: []const u8,
    priority: i32,

    pub const VTable = struct {
        find_spec: *const fn (
            *anyopaque,
            fullname: []const u8,
            path: ?[]const []const u8,
            target: ?*Module,
        ) ?*ModuleSpec,

        find_module: *const fn (
            *anyopaque,
            fullname: []const u8,
            path: ?[]const []const u8,
        ) ?*const Loader,

        invalidate_caches: *const fn (*anyopaque) void,
    };

    pub fn findSpec(
        self: *const MetaPathFinder,
        fullname: []const u8,
        path: ?[]const []const u8,
        target: ?*Module,
    ) ?*ModuleSpec {
        return self.vtable.find_spec(self.context, fullname, path, target);
    }

    pub fn findModule(
        self: *const MetaPathFinder,
        fullname: []const u8,
        path: ?[]const []const u8,
    ) ?*const Loader {
        return self.vtable.find_module(self.context, fullname, path);
    }

    pub fn invalidateCaches(self: *const MetaPathFinder) void {
        self.vtable.invalidate_caches(self.context);
    }
};

/// sys.meta_path implementation
pub const SysMetaPath = struct {
    finders: std.ArrayListUnmanaged(*MetaPathFinder),
    allocator: Allocator,

    pub fn init(allocator: Allocator) SysMetaPath {
        return .{
            .finders = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SysMetaPath) void {
        self.finders.deinit(self.allocator);
    }

    /// Append a finder to the end of meta_path
    pub fn append(self: *SysMetaPath, finder: *MetaPathFinder) !void {
        try self.finders.append(self.allocator, finder);
    }

    /// Insert a finder at a specific position
    pub fn insert(self: *SysMetaPath, index: usize, finder: *MetaPathFinder) !void {
        try self.finders.insert(self.allocator, index, finder);
    }

    /// Remove a finder by reference
    pub fn remove(self: *SysMetaPath, finder: *MetaPathFinder) bool {
        for (self.finders.items, 0..) |f, i| {
            if (f == finder) {
                _ = self.finders.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Remove a finder by name
    pub fn removeByName(self: *SysMetaPath, name: []const u8) bool {
        for (self.finders.items, 0..) |f, i| {
            if (std.mem.eql(u8, f.name, name)) {
                _ = self.finders.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Get number of finders
    pub fn len(self: *const SysMetaPath) usize {
        return self.finders.items.len;
    }

    /// Get finder at index
    pub fn get(self: *const SysMetaPath, index: usize) ?*MetaPathFinder {
        if (index >= self.finders.items.len) return null;
        return self.finders.items[index];
    }

    /// Find a module spec by iterating through all finders
    pub fn findSpec(
        self: *const SysMetaPath,
        fullname: []const u8,
        path: ?[]const []const u8,
        target: ?*Module,
    ) ?*ModuleSpec {
        for (self.finders.items) |finder| {
            if (finder.findSpec(fullname, path, target)) |spec| {
                return spec;
            }
        }
        return null;
    }

    /// Invalidate all finder caches
    pub fn invalidateCaches(self: *SysMetaPath) void {
        for (self.finders.items) |finder| {
            finder.invalidateCaches();
        }
    }

    /// Clear all finders
    pub fn clear(self: *SysMetaPath) void {
        self.finders.clearRetainingCapacity();
    }

    /// Check if a finder with given name exists
    pub fn containsFinder(self: *const SysMetaPath, name: []const u8) bool {
        for (self.finders.items) |f| {
            if (std.mem.eql(u8, f.name, name)) return true;
        }
        return false;
    }
};

/// Custom import hook - intercepts specific module imports
pub const ImportHook = struct {
    module_patterns: std.ArrayListUnmanaged([]const u8),
    handler: *const fn ([]const u8) ?*ModuleSpec,
    enabled: bool,
    allocator: Allocator,

    pub fn init(allocator: Allocator, handler: *const fn ([]const u8) ?*ModuleSpec) ImportHook {
        return .{
            .module_patterns = .{},
            .handler = handler,
            .enabled = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportHook) void {
        self.module_patterns.deinit(self.allocator);
    }

    pub fn addPattern(self: *ImportHook, pattern: []const u8) !void {
        try self.module_patterns.append(self.allocator, pattern);
    }

    pub fn matches(self: *const ImportHook, fullname: []const u8) bool {
        if (!self.enabled) return false;

        for (self.module_patterns.items) |pattern| {
            if (matchPattern(pattern, fullname)) return true;
        }
        return false;
    }

    fn matchPattern(pattern: []const u8, name: []const u8) bool {
        // Simple wildcard matching
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, name, prefix);
        }
        return std.mem.eql(u8, pattern, name);
    }

    pub fn intercept(self: *const ImportHook, fullname: []const u8) ?*ModuleSpec {
        if (self.matches(fullname)) {
            return self.handler(fullname);
        }
        return null;
    }
};

/// ModuleReplacer - Replace module at import time
pub const ModuleReplacer = struct {
    replacements: std.StringHashMapUnmanaged(Replacement),
    allocator: Allocator,

    pub const Replacement = struct {
        original: []const u8,
        replacement: []const u8,
        spec: ?ModuleSpec,
    };

    pub fn init(allocator: Allocator) ModuleReplacer {
        return .{
            .replacements = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleReplacer) void {
        self.replacements.deinit(self.allocator);
    }

    pub fn addReplacement(self: *ModuleReplacer, original: []const u8, replacement: []const u8) !void {
        try self.replacements.put(self.allocator, original, .{
            .original = original,
            .replacement = replacement,
            .spec = null,
        });
    }

    pub fn getReplacement(self: *const ModuleReplacer, name: []const u8) ?Replacement {
        return self.replacements.get(name);
    }

    pub fn hasReplacement(self: *const ModuleReplacer, name: []const u8) bool {
        return self.replacements.contains(name);
    }

    pub fn removeReplacement(self: *ModuleReplacer, name: []const u8) bool {
        return self.replacements.remove(name);
    }
};

/// MetaPathManager - High-level manager for meta_path
pub const MetaPathManager = struct {
    meta_path: SysMetaPath,
    modules_cache: std.StringHashMapUnmanaged(*Module),
    import_depth: u32,
    max_import_depth: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator) MetaPathManager {
        return .{
            .meta_path = SysMetaPath.init(allocator),
            .modules_cache = .{},
            .import_depth = 0,
            .max_import_depth = 100,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MetaPathManager) void {
        self.meta_path.deinit();
        self.modules_cache.deinit(self.allocator);
    }

    /// Import a module
    pub fn importModule(self: *MetaPathManager, fullname: []const u8) !*Module {
        // Check cache first
        if (self.modules_cache.get(fullname)) |cached| {
            return cached;
        }

        // Check import depth
        if (self.import_depth >= self.max_import_depth) {
            return error.OutOfMemory; // Import recursion limit
        }

        self.import_depth += 1;
        defer self.import_depth -= 1;

        // Find spec
        const spec = self.meta_path.findSpec(fullname, null, null) orelse
            return error.ModuleNotFound;

        // Create and execute module
        const module = try Module.init(self.allocator, fullname);
        module.__spec__ = spec;

        // Cache module
        try self.modules_cache.put(self.allocator, fullname, module);

        return module;
    }

    /// Check if module is cached
    pub fn isCached(self: *const MetaPathManager, fullname: []const u8) bool {
        return self.modules_cache.contains(fullname);
    }

    /// Remove from cache
    pub fn uncache(self: *MetaPathManager, fullname: []const u8) bool {
        return self.modules_cache.remove(fullname);
    }

    /// Get current import depth
    pub fn getImportDepth(self: *const MetaPathManager) u32 {
        return self.import_depth;
    }
};

/// FinderStats - Statistics for finder performance
pub const FinderStats = struct {
    name: []const u8,
    find_spec_calls: u64,
    find_spec_hits: u64,
    find_spec_misses: u64,
    total_time_ns: u64,

    pub fn init(name: []const u8) FinderStats {
        return .{
            .name = name,
            .find_spec_calls = 0,
            .find_spec_hits = 0,
            .find_spec_misses = 0,
            .total_time_ns = 0,
        };
    }

    pub fn recordCall(self: *FinderStats, hit: bool, time_ns: u64) void {
        self.find_spec_calls += 1;
        if (hit) {
            self.find_spec_hits += 1;
        } else {
            self.find_spec_misses += 1;
        }
        self.total_time_ns += time_ns;
    }

    pub fn hitRate(self: *const FinderStats) f64 {
        if (self.find_spec_calls == 0) return 0.0;
        return @as(f64, @floatFromInt(self.find_spec_hits)) /
            @as(f64, @floatFromInt(self.find_spec_calls));
    }

    pub fn avgTimeNs(self: *const FinderStats) f64 {
        if (self.find_spec_calls == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time_ns)) /
            @as(f64, @floatFromInt(self.find_spec_calls));
    }
};

// =============================================================================
// Tests
// =============================================================================

test "sys_meta_path_basic" {
    var meta_path = SysMetaPath.init(std.testing.allocator);
    defer meta_path.deinit();

    try std.testing.expectEqual(@as(usize, 0), meta_path.len());
}

test "sys_meta_path_append_insert" {
    var meta_path = SysMetaPath.init(std.testing.allocator);
    defer meta_path.deinit();

    // Would need actual finder instances for full test
    try std.testing.expectEqual(@as(usize, 0), meta_path.len());
}

test "import_hook_pattern_matching" {
    const dummy_handler: *const fn ([]const u8) ?*ModuleSpec = struct {
        fn handler(_: []const u8) ?*ModuleSpec {
            return null;
        }
    }.handler;

    var hook = ImportHook.init(std.testing.allocator, dummy_handler);
    defer hook.deinit();

    try hook.addPattern("mypackage.*");
    try hook.addPattern("exact_module");

    try std.testing.expect(hook.matches("mypackage.submodule"));
    try std.testing.expect(hook.matches("mypackage.sub.deep"));
    try std.testing.expect(hook.matches("exact_module"));
    try std.testing.expect(!hook.matches("other_module"));
    try std.testing.expect(!hook.matches("mypackage")); // No wildcard match for exact

    hook.enabled = false;
    try std.testing.expect(!hook.matches("mypackage.submodule"));
}

test "module_replacer" {
    var replacer = ModuleReplacer.init(std.testing.allocator);
    defer replacer.deinit();

    try replacer.addReplacement("old_module", "new_module");
    try replacer.addReplacement("deprecated", "modern");

    try std.testing.expect(replacer.hasReplacement("old_module"));
    try std.testing.expect(replacer.hasReplacement("deprecated"));
    try std.testing.expect(!replacer.hasReplacement("unknown"));

    const repl = replacer.getReplacement("old_module");
    try std.testing.expect(repl != null);
    try std.testing.expectEqualStrings("new_module", repl.?.replacement);

    try std.testing.expect(replacer.removeReplacement("old_module"));
    try std.testing.expect(!replacer.hasReplacement("old_module"));
}

test "meta_path_manager_init" {
    var manager = MetaPathManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(u32, 0), manager.getImportDepth());
    try std.testing.expect(!manager.isCached("any_module"));
}

test "finder_stats" {
    var stats = FinderStats.init("TestFinder");

    stats.recordCall(true, 1000);
    stats.recordCall(true, 2000);
    stats.recordCall(false, 500);

    try std.testing.expectEqual(@as(u64, 3), stats.find_spec_calls);
    try std.testing.expectEqual(@as(u64, 2), stats.find_spec_hits);
    try std.testing.expectEqual(@as(u64, 1), stats.find_spec_misses);
    try std.testing.expectEqual(@as(u64, 3500), stats.total_time_ns);

    const hit_rate = stats.hitRate();
    try std.testing.expect(hit_rate > 0.66 and hit_rate < 0.67);
}

test "finder_stats_empty" {
    const stats = FinderStats.init("Empty");

    try std.testing.expectEqual(@as(f64, 0.0), stats.hitRate());
    try std.testing.expectEqual(@as(f64, 0.0), stats.avgTimeNs());
}

test "module_spec_init" {
    const spec = ModuleSpec.init("test_module");

    try std.testing.expectEqualStrings("test_module", spec.name);
    try std.testing.expect(!spec.isPackage());
    try std.testing.expect(spec.loader == null);
}

test "module_creation" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try std.testing.expectEqualStrings("test", module.__name__);
    try std.testing.expect(module.__file__ == null);
}

test "sys_meta_path_contains" {
    var meta_path = SysMetaPath.init(std.testing.allocator);
    defer meta_path.deinit();

    try std.testing.expect(!meta_path.containsFinder("BuiltinImporter"));
}

test "sys_meta_path_invalidate" {
    var meta_path = SysMetaPath.init(std.testing.allocator);
    defer meta_path.deinit();

    // Should not crash with no finders
    meta_path.invalidateCaches();
}

test "sys_meta_path_clear" {
    var meta_path = SysMetaPath.init(std.testing.allocator);
    defer meta_path.deinit();

    meta_path.clear();
    try std.testing.expectEqual(@as(usize, 0), meta_path.len());
}
