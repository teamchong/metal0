//! test.test_import.test_reload - Module reload testing
//!
//! Tests for Python's module reloading functionality including:
//! - importlib.reload()
//! - Module state preservation/reset
//! - Reloader callbacks
//! - Hot reload support
//! - Dependency tracking for reload

const std = @import("std");
const Allocator = std.mem.Allocator;

/// ReloadError - Errors related to module reloading
pub const ReloadError = error{
    ModuleNotLoaded,
    ReloadFailed,
    CircularReload,
    SourceNotFound,
    CompilationError,
    OutOfMemory,
};

/// ReloadResult - Result of a reload operation
pub const ReloadResult = struct {
    success: bool,
    module: ?*Module,
    error_message: ?[]const u8,
    reload_time_ns: u64,
    attributes_changed: u32,
    attributes_added: u32,
    attributes_removed: u32,

    pub fn ok(module: *Module, time_ns: u64) ReloadResult {
        return .{
            .success = true,
            .module = module,
            .error_message = null,
            .reload_time_ns = time_ns,
            .attributes_changed = 0,
            .attributes_added = 0,
            .attributes_removed = 0,
        };
    }

    pub fn err(message: []const u8) ReloadResult {
        return .{
            .success = false,
            .module = null,
            .error_message = message,
            .reload_time_ns = 0,
            .attributes_changed = 0,
            .attributes_added = 0,
            .attributes_removed = 0,
        };
    }
};

/// Module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __loader__: ?*anyopaque,
    __package__: ?[]const u8,
    __spec__: ?*ModuleSpec,
    __dict__: std.StringHashMapUnmanaged(Value),
    __cached__: ?[]const u8,
    load_time: i64,
    reload_count: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .__name__ = name,
            .__file__ = null,
            .__loader__ = null,
            .__package__ = null,
            .__spec__ = null,
            .__dict__ = .{},
            .__cached__ = null,
            .load_time = std.time.milliTimestamp(),
            .reload_count = 0,
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        self.__dict__.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setAttr(self: *Module, name: []const u8, value: Value) !void {
        try self.__dict__.put(self.allocator, name, value);
    }

    pub fn getAttr(self: *const Module, name: []const u8) ?Value {
        return self.__dict__.get(name);
    }

    pub fn delAttr(self: *Module, name: []const u8) bool {
        return self.__dict__.remove(name);
    }

    pub fn hasAttr(self: *const Module, name: []const u8) bool {
        return self.__dict__.contains(name);
    }

    pub fn getAttrCount(self: *const Module) usize {
        return self.__dict__.count();
    }

    /// Clear all attributes except special ones
    pub fn clearAttributes(self: *Module) void {
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.__dict__.keyIterator();
        while (iter.next()) |key| {
            // Keep special attributes
            if (!std.mem.startsWith(u8, key.*, "__")) {
                to_remove.append(key.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            _ = self.__dict__.remove(key);
        }
    }

    /// Mark as reloaded
    pub fn markReloaded(self: *Module) void {
        self.reload_count += 1;
        self.load_time = std.time.milliTimestamp();
    }
};

/// ModuleSpec for reload
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*anyopaque,
    origin: ?[]const u8,
    cached: ?[]const u8,
    parent: ?[]const u8,
    has_location: bool,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .cached = null,
            .parent = null,
            .has_location = false,
        };
    }
};

/// Value type
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    function: *anyopaque,
    class: *anyopaque,
    module: *Module,
};

/// ModuleReloader - Handles module reloading
pub const ModuleReloader = struct {
    modules: std.StringHashMapUnmanaged(*Module),
    reload_callbacks: std.ArrayListUnmanaged(ReloadCallback),
    dependency_graph: std.StringHashMapUnmanaged(Dependencies),
    allocator: Allocator,

    pub const ReloadCallback = struct {
        callback: *const fn (*Module, ReloadPhase) void,
        phase: ReloadPhase,
    };

    pub const ReloadPhase = enum {
        before_reload,
        after_reload,
        on_error,
    };

    pub const Dependencies = struct {
        dependents: std.ArrayListUnmanaged([]const u8),
    };

    pub fn init(allocator: Allocator) ModuleReloader {
        return .{
            .modules = .{},
            .reload_callbacks = .{},
            .dependency_graph = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleReloader) void {
        self.modules.deinit(self.allocator);
        self.reload_callbacks.deinit(self.allocator);

        var iter = self.dependency_graph.valueIterator();
        while (iter.next()) |deps| {
            deps.dependents.deinit(self.allocator);
        }
        self.dependency_graph.deinit(self.allocator);
    }

    /// Register a module
    pub fn registerModule(self: *ModuleReloader, module: *Module) !void {
        try self.modules.put(self.allocator, module.__name__, module);
    }

    /// Get a registered module
    pub fn getModule(self: *const ModuleReloader, name: []const u8) ?*Module {
        return self.modules.get(name);
    }

    /// Register a reload callback
    pub fn addCallback(self: *ModuleReloader, callback: *const fn (*Module, ReloadPhase) void, phase: ReloadPhase) !void {
        try self.reload_callbacks.append(self.allocator, .{
            .callback = callback,
            .phase = phase,
        });
    }

    /// Reload a module
    pub fn reload(self: *ModuleReloader, name: []const u8) ReloadError!ReloadResult {
        const module = self.modules.get(name) orelse return error.ModuleNotLoaded;

        const start_time = std.time.nanoTimestamp();

        // Call before_reload callbacks
        for (self.reload_callbacks.items) |cb| {
            if (cb.phase == .before_reload) {
                cb.callback(module, .before_reload);
            }
        }

        // Perform reload
        // In real implementation, would re-execute module code
        module.markReloaded();

        const end_time = std.time.nanoTimestamp();

        // Call after_reload callbacks
        for (self.reload_callbacks.items) |cb| {
            if (cb.phase == .after_reload) {
                cb.callback(module, .after_reload);
            }
        }

        return ReloadResult.ok(module, @intCast(end_time - start_time));
    }

    /// Reload a module and all its dependents
    pub fn reloadWithDependents(self: *ModuleReloader, name: []const u8, allocator: Allocator) ![]ReloadResult {
        var results = std.ArrayList(ReloadResult).init(allocator);

        // Reload the module itself
        const result = self.reload(name) catch |e| {
            try results.append(ReloadResult.err(@errorName(e)));
            return results.toOwnedSlice();
        };
        try results.append(result);

        // Reload dependents
        if (self.dependency_graph.get(name)) |deps| {
            for (deps.dependents.items) |dep| {
                const dep_result = self.reload(dep) catch |e| {
                    try results.append(ReloadResult.err(@errorName(e)));
                    continue;
                };
                try results.append(dep_result);
            }
        }

        return results.toOwnedSlice();
    }

    /// Register a dependency
    pub fn addDependency(self: *ModuleReloader, module: []const u8, depends_on: []const u8) !void {
        if (self.dependency_graph.getPtr(depends_on)) |deps| {
            try deps.dependents.append(self.allocator, module);
        } else {
            var new_deps = Dependencies{ .dependents = .{} };
            try new_deps.dependents.append(self.allocator, module);
            try self.dependency_graph.put(self.allocator, depends_on, new_deps);
        }
    }

    /// Get all modules that depend on a given module
    pub fn getDependents(self: *const ModuleReloader, name: []const u8, allocator: Allocator) ![][]const u8 {
        if (self.dependency_graph.get(name)) |deps| {
            const result = try allocator.alloc([]const u8, deps.dependents.items.len);
            @memcpy(result, deps.dependents.items);
            return result;
        }
        return &[_][]const u8{};
    }
};

/// HotReloader - Watches for file changes and reloads
pub const HotReloader = struct {
    reloader: *ModuleReloader,
    watch_paths: std.StringHashMapUnmanaged(WatchInfo),
    enabled: bool,
    poll_interval_ms: u32,
    allocator: Allocator,

    pub const WatchInfo = struct {
        module_name: []const u8,
        last_mtime: i64,
        last_size: u64,
    };

    pub fn init(allocator: Allocator, reloader: *ModuleReloader) HotReloader {
        return .{
            .reloader = reloader,
            .watch_paths = .{},
            .enabled = false,
            .poll_interval_ms = 1000,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HotReloader) void {
        self.watch_paths.deinit(self.allocator);
    }

    /// Watch a file for changes
    pub fn watch(self: *HotReloader, path: []const u8, module_name: []const u8) !void {
        try self.watch_paths.put(self.allocator, path, .{
            .module_name = module_name,
            .last_mtime = std.time.milliTimestamp(),
            .last_size = 0,
        });
    }

    /// Stop watching a file
    pub fn unwatch(self: *HotReloader, path: []const u8) bool {
        return self.watch_paths.remove(path);
    }

    /// Check for changes (would be called periodically)
    pub fn checkForChanges(self: *HotReloader) ![][]const u8 {
        var changed = std.ArrayList([]const u8).init(self.allocator);

        var iter = self.watch_paths.iterator();
        while (iter.next()) |entry| {
            // In real implementation, would check file mtime
            // For testing, just return empty
            _ = entry;
        }

        return changed.toOwnedSlice();
    }

    /// Enable hot reloading
    pub fn enable(self: *HotReloader) void {
        self.enabled = true;
    }

    /// Disable hot reloading
    pub fn disable(self: *HotReloader) void {
        self.enabled = false;
    }

    /// Set poll interval
    pub fn setPollInterval(self: *HotReloader, interval_ms: u32) void {
        self.poll_interval_ms = interval_ms;
    }
};

/// ReloadHistory - Tracks reload history for debugging
pub const ReloadHistory = struct {
    entries: std.ArrayListUnmanaged(HistoryEntry),
    max_entries: usize,
    allocator: Allocator,

    pub const HistoryEntry = struct {
        module_name: []const u8,
        timestamp: i64,
        success: bool,
        duration_ns: u64,
        trigger: ReloadTrigger,
    };

    pub const ReloadTrigger = enum {
        manual,
        file_change,
        dependency,
        api_call,
    };

    pub fn init(allocator: Allocator, max_entries: usize) ReloadHistory {
        return .{
            .entries = .{},
            .max_entries = max_entries,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ReloadHistory) void {
        self.entries.deinit(self.allocator);
    }

    pub fn record(self: *ReloadHistory, entry: HistoryEntry) !void {
        // Remove oldest if at capacity
        if (self.entries.items.len >= self.max_entries) {
            _ = self.entries.orderedRemove(0);
        }
        try self.entries.append(self.allocator, entry);
    }

    pub fn getLastReload(self: *const ReloadHistory, module_name: []const u8) ?HistoryEntry {
        var iter = std.mem.reverseIterator(self.entries.items);
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.module_name, module_name)) {
                return entry;
            }
        }
        return null;
    }

    pub fn getReloadCount(self: *const ReloadHistory, module_name: []const u8) usize {
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.module_name, module_name)) {
                count += 1;
            }
        }
        return count;
    }

    pub fn clear(self: *ReloadHistory) void {
        self.entries.clearRetainingCapacity();
    }
};

/// ReloadPolicy - Controls reload behavior
pub const ReloadPolicy = struct {
    /// Allow reloading of C extensions
    allow_extension_reload: bool,

    /// Clear __dict__ before reload
    clear_dict_on_reload: bool,

    /// Preserve classes across reloads
    preserve_classes: bool,

    /// Maximum reload depth for dependencies
    max_dependency_depth: u32,

    /// Timeout for reload operation (ms)
    reload_timeout_ms: u32,

    pub fn default() ReloadPolicy {
        return .{
            .allow_extension_reload = false,
            .clear_dict_on_reload = false,
            .preserve_classes = true,
            .max_dependency_depth = 10,
            .reload_timeout_ms = 5000,
        };
    }

    pub fn strict() ReloadPolicy {
        return .{
            .allow_extension_reload = false,
            .clear_dict_on_reload = true,
            .preserve_classes = false,
            .max_dependency_depth = 5,
            .reload_timeout_ms = 1000,
        };
    }

    pub fn lenient() ReloadPolicy {
        return .{
            .allow_extension_reload = true,
            .clear_dict_on_reload = false,
            .preserve_classes = true,
            .max_dependency_depth = 20,
            .reload_timeout_ms = 30000,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "module_creation" {
    const module = try Module.init(std.testing.allocator, "test_module");
    defer module.deinit();

    try std.testing.expectEqualStrings("test_module", module.__name__);
    try std.testing.expectEqual(@as(u32, 0), module.reload_count);
}

test "module_attributes" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try module.setAttr("foo", .{ .integer = 42 });
    try module.setAttr("bar", .{ .string = "hello" });

    try std.testing.expect(module.hasAttr("foo"));
    try std.testing.expectEqual(@as(usize, 2), module.getAttrCount());

    try std.testing.expect(module.delAttr("foo"));
    try std.testing.expect(!module.hasAttr("foo"));
}

test "module_reload_mark" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try std.testing.expectEqual(@as(u32, 0), module.reload_count);

    module.markReloaded();
    try std.testing.expectEqual(@as(u32, 1), module.reload_count);

    module.markReloaded();
    try std.testing.expectEqual(@as(u32, 2), module.reload_count);
}

test "module_reloader_basic" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    const module = try Module.init(std.testing.allocator, "mymodule");
    defer module.deinit();

    try reloader.registerModule(module);

    const found = reloader.getModule("mymodule");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("mymodule", found.?.__name__);
}

test "module_reloader_reload" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    const module = try Module.init(std.testing.allocator, "mymodule");
    defer module.deinit();

    try reloader.registerModule(module);

    const result = try reloader.reload("mymodule");
    try std.testing.expect(result.success);
    try std.testing.expect(result.module != null);
    try std.testing.expectEqual(@as(u32, 1), module.reload_count);
}

test "module_reloader_not_loaded" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    const result = reloader.reload("nonexistent");
    try std.testing.expectError(error.ModuleNotLoaded, result);
}

test "reload_result" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    const ok_result = ReloadResult.ok(module, 1000);
    try std.testing.expect(ok_result.success);
    try std.testing.expectEqual(@as(u64, 1000), ok_result.reload_time_ns);

    const err_result = ReloadResult.err("test error");
    try std.testing.expect(!err_result.success);
    try std.testing.expectEqualStrings("test error", err_result.error_message.?);
}

test "hot_reloader_watch" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    var hot_reloader = HotReloader.init(std.testing.allocator, &reloader);
    defer hot_reloader.deinit();

    try hot_reloader.watch("/path/to/module.py", "mymodule");

    try std.testing.expect(!hot_reloader.enabled);
    hot_reloader.enable();
    try std.testing.expect(hot_reloader.enabled);

    try std.testing.expect(hot_reloader.unwatch("/path/to/module.py"));
    try std.testing.expect(!hot_reloader.unwatch("/nonexistent"));
}

test "hot_reloader_interval" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    var hot_reloader = HotReloader.init(std.testing.allocator, &reloader);
    defer hot_reloader.deinit();

    try std.testing.expectEqual(@as(u32, 1000), hot_reloader.poll_interval_ms);

    hot_reloader.setPollInterval(500);
    try std.testing.expectEqual(@as(u32, 500), hot_reloader.poll_interval_ms);
}

test "reload_history" {
    var history = ReloadHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    try history.record(.{
        .module_name = "mod1",
        .timestamp = 1000,
        .success = true,
        .duration_ns = 500,
        .trigger = .manual,
    });

    try history.record(.{
        .module_name = "mod2",
        .timestamp = 2000,
        .success = false,
        .duration_ns = 100,
        .trigger = .file_change,
    });

    try std.testing.expectEqual(@as(usize, 1), history.getReloadCount("mod1"));
    try std.testing.expectEqual(@as(usize, 1), history.getReloadCount("mod2"));
    try std.testing.expectEqual(@as(usize, 0), history.getReloadCount("mod3"));

    const last_mod1 = history.getLastReload("mod1");
    try std.testing.expect(last_mod1 != null);
    try std.testing.expect(last_mod1.?.success);
}

test "reload_history_capacity" {
    var history = ReloadHistory.init(std.testing.allocator, 3);
    defer history.deinit();

    try history.record(.{ .module_name = "m1", .timestamp = 1, .success = true, .duration_ns = 0, .trigger = .manual });
    try history.record(.{ .module_name = "m2", .timestamp = 2, .success = true, .duration_ns = 0, .trigger = .manual });
    try history.record(.{ .module_name = "m3", .timestamp = 3, .success = true, .duration_ns = 0, .trigger = .manual });
    try history.record(.{ .module_name = "m4", .timestamp = 4, .success = true, .duration_ns = 0, .trigger = .manual });

    try std.testing.expectEqual(@as(usize, 3), history.entries.items.len);
    // m1 should be removed
    try std.testing.expect(history.getLastReload("m1") == null);
}

test "reload_policy_default" {
    const policy = ReloadPolicy.default();

    try std.testing.expect(!policy.allow_extension_reload);
    try std.testing.expect(!policy.clear_dict_on_reload);
    try std.testing.expect(policy.preserve_classes);
    try std.testing.expectEqual(@as(u32, 10), policy.max_dependency_depth);
}

test "reload_policy_strict" {
    const policy = ReloadPolicy.strict();

    try std.testing.expect(policy.clear_dict_on_reload);
    try std.testing.expect(!policy.preserve_classes);
    try std.testing.expectEqual(@as(u32, 1000), policy.reload_timeout_ms);
}

test "reload_policy_lenient" {
    const policy = ReloadPolicy.lenient();

    try std.testing.expect(policy.allow_extension_reload);
    try std.testing.expectEqual(@as(u32, 20), policy.max_dependency_depth);
    try std.testing.expectEqual(@as(u32, 30000), policy.reload_timeout_ms);
}

test "module_reloader_dependencies" {
    var reloader = ModuleReloader.init(std.testing.allocator);
    defer reloader.deinit();

    try reloader.addDependency("consumer", "provider");

    const deps = try reloader.getDependents("provider", std.testing.allocator);
    defer std.testing.allocator.free(deps);

    try std.testing.expectEqual(@as(usize, 1), deps.len);
    try std.testing.expectEqualStrings("consumer", deps[0]);
}
