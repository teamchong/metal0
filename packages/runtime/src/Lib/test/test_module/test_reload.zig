//! test.test_module.test_reload - Module reload testing
//! Tests for Python's importlib.reload() functionality
//! Reference: CPython Lib/test/test_importlib/test_reload.py

const std = @import("std");
const importlib = @import("../../importlib.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Module Reload System
// ============================================================================

/// Represents a module's reload state
pub const ReloadState = enum {
    /// Module has not been modified
    unchanged,
    /// Module source has changed
    modified,
    /// Module is currently being reloaded
    reloading,
    /// Module reload completed successfully
    reloaded,
    /// Module reload failed
    failed,
};

/// Module version tracking for reload detection
pub const ModuleVersion = struct {
    name: []const u8,
    source_hash: u64,
    load_time: i64,
    reload_count: usize = 0,

    const Self = @This();

    pub fn init(name: []const u8, source: []const u8) Self {
        return .{
            .name = name,
            .source_hash = std.hash.Wyhash.hash(0, source),
            .load_time = std.time.timestamp(),
        };
    }

    /// Check if source has changed
    pub fn hasChanged(self: *const Self, new_source: []const u8) bool {
        const new_hash = std.hash.Wyhash.hash(0, new_source);
        return new_hash != self.source_hash;
    }

    /// Update version after reload
    pub fn update(self: *Self, source: []const u8) void {
        self.source_hash = std.hash.Wyhash.hash(0, source);
        self.load_time = std.time.timestamp();
        self.reload_count += 1;
    }
};

/// Manages module reloading
pub const ReloadManager = struct {
    modules: std.StringHashMap(ModuleVersion),
    reload_hooks: std.ArrayList(ReloadHook),
    allocator: std.mem.Allocator,
    enabled: bool = true,

    const Self = @This();

    pub const ReloadHook = struct {
        name: []const u8,
        callback: *const fn ([]const u8) void,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = std.StringHashMap(ModuleVersion).init(allocator),
            .reload_hooks = std.ArrayList(ReloadHook){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
        self.reload_hooks.deinit(self.allocator);
    }

    /// Register a module
    pub fn registerModule(self: *Self, name: []const u8, source: []const u8) !void {
        const version = ModuleVersion.init(name, source);
        try self.modules.put(name, version);
    }

    /// Check if a module needs reload
    pub fn needsReload(self: *const Self, name: []const u8, new_source: []const u8) bool {
        if (!self.enabled) return false;
        if (self.modules.get(name)) |version| {
            return version.hasChanged(new_source);
        }
        return true; // New module, needs initial load
    }

    /// Perform module reload
    pub fn reload(self: *Self, name: []const u8, new_source: []const u8) !ReloadResult {
        if (!self.enabled) {
            return .{ .state = .unchanged, .message = "Reload disabled" };
        }

        if (self.modules.getPtr(name)) |version| {
            if (!version.hasChanged(new_source)) {
                return .{ .state = .unchanged, .message = "No changes detected" };
            }

            // Perform reload
            version.update(new_source);

            // Call hooks
            for (self.reload_hooks.items) |hook| {
                if (std.mem.eql(u8, hook.name, name) or std.mem.eql(u8, hook.name, "*")) {
                    hook.callback(name);
                }
            }

            return .{
                .state = .reloaded,
                .message = "Module reloaded successfully",
                .reload_count = version.reload_count,
            };
        }

        // New module registration
        try self.registerModule(name, new_source);
        return .{ .state = .reloaded, .message = "Module loaded for first time" };
    }

    /// Add a reload hook
    pub fn addHook(self: *Self, name: []const u8, callback: *const fn ([]const u8) void) !void {
        try self.reload_hooks.append(self.allocator, .{ .name = name, .callback = callback });
    }

    /// Get module version info
    pub fn getVersion(self: *const Self, name: []const u8) ?ModuleVersion {
        return self.modules.get(name);
    }

    /// Invalidate a module (force reload on next access)
    pub fn invalidate(self: *Self, name: []const u8) void {
        if (self.modules.getPtr(name)) |version| {
            version.source_hash = 0; // Force mismatch
        }
    }

    /// Invalidate all modules
    pub fn invalidateAll(self: *Self) void {
        var it = self.modules.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.source_hash = 0;
        }
    }
};

/// Result of a reload operation
pub const ReloadResult = struct {
    state: ReloadState,
    message: []const u8 = "",
    reload_count: usize = 0,

    pub fn isSuccess(self: ReloadResult) bool {
        return self.state == .reloaded;
    }

    pub fn isUnchanged(self: ReloadResult) bool {
        return self.state == .unchanged;
    }
};

// ============================================================================
// AOT Reload Behavior
// ============================================================================

/// In AOT compilation, true dynamic reload is not possible.
/// This documents the expected behavior.
pub const AOTReloadBehavior = struct {
    /// AOT reload returns the existing module (no source re-parsing)
    pub fn reload(module: *anyopaque) *anyopaque {
        // In AOT, modules are compiled into the binary
        // "Reload" just returns the existing module
        return module;
    }

    /// Check if dynamic reload is available
    pub fn isAvailable() bool {
        // Dynamic reload not available in AOT
        return false;
    }

    /// Get reload limitation message
    pub fn getLimitation() []const u8 {
        return "In AOT compilation, modules are statically compiled. " ++
            "Source changes require recompilation of the binary.";
    }
};

// ============================================================================
// Test Functions
// ============================================================================

/// Test ModuleVersion initialization
pub fn testModuleVersionInit() !void {
    const version = ModuleVersion.init("mymod", "x = 1");
    try std.testing.expectEqualStrings("mymod", version.name);
    try std.testing.expectEqual(@as(usize, 0), version.reload_count);
}

/// Test ModuleVersion change detection
pub fn testModuleVersionChangeDetection() !void {
    var version = ModuleVersion.init("mod", "original");
    try std.testing.expect(!version.hasChanged("original"));
    try std.testing.expect(version.hasChanged("modified"));
}

/// Test ModuleVersion update
pub fn testModuleVersionUpdate() !void {
    var version = ModuleVersion.init("mod", "v1");
    version.update("v2");
    try std.testing.expectEqual(@as(usize, 1), version.reload_count);
    try std.testing.expect(!version.hasChanged("v2"));
}

/// Test ReloadManager initialization
pub fn testReloadManagerInit(allocator: std.mem.Allocator) !void {
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();
    try std.testing.expect(manager.enabled);
}

/// Test ReloadManager register and reload
pub fn testReloadManagerReload(allocator: std.mem.Allocator) !void {
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("test", "version1");
    try std.testing.expect(!manager.needsReload("test", "version1"));
    try std.testing.expect(manager.needsReload("test", "version2"));

    const result = try manager.reload("test", "version2");
    try std.testing.expect(result.isSuccess());
}

/// Test ReloadManager invalidate
pub fn testReloadManagerInvalidate(allocator: std.mem.Allocator) !void {
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "source");
    try std.testing.expect(!manager.needsReload("mod", "source"));

    manager.invalidate("mod");
    try std.testing.expect(manager.needsReload("mod", "source"));
}

/// Test AOTReloadBehavior
pub fn testAOTReloadBehavior() !void {
    try std.testing.expect(!AOTReloadBehavior.isAvailable());
    const msg = AOTReloadBehavior.getLimitation();
    try std.testing.expect(msg.len > 0);
}

// ============================================================================
// Zig Tests
// ============================================================================

test "ReloadState enum" {
    const state: ReloadState = .reloading;
    try std.testing.expect(state == .reloading);
}

test "ModuleVersion init" {
    const ver = ModuleVersion.init("test", "code");
    try std.testing.expectEqualStrings("test", ver.name);
    try std.testing.expectEqual(@as(usize, 0), ver.reload_count);
}

test "ModuleVersion hasChanged same" {
    const ver = ModuleVersion.init("mod", "code");
    try std.testing.expect(!ver.hasChanged("code"));
}

test "ModuleVersion hasChanged different" {
    const ver = ModuleVersion.init("mod", "code1");
    try std.testing.expect(ver.hasChanged("code2"));
}

test "ModuleVersion update" {
    var ver = ModuleVersion.init("mod", "v1");
    ver.update("v2");
    try std.testing.expectEqual(@as(usize, 1), ver.reload_count);
}

test "ModuleVersion multiple updates" {
    var ver = ModuleVersion.init("mod", "v1");
    ver.update("v2");
    ver.update("v3");
    ver.update("v4");
    try std.testing.expectEqual(@as(usize, 3), ver.reload_count);
}

test "ReloadManager init" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();
    try std.testing.expect(manager.enabled);
}

test "ReloadManager registerModule" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mymod", "source");
    try std.testing.expect(manager.getVersion("mymod") != null);
}

test "ReloadManager needsReload new module" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try std.testing.expect(manager.needsReload("unknown", "any"));
}

test "ReloadManager needsReload unchanged" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "source");
    try std.testing.expect(!manager.needsReload("mod", "source"));
}

test "ReloadManager needsReload changed" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "source1");
    try std.testing.expect(manager.needsReload("mod", "source2"));
}

test "ReloadManager reload success" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "v1");
    const result = try manager.reload("mod", "v2");
    try std.testing.expect(result.isSuccess());
}

test "ReloadManager reload unchanged" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "same");
    const result = try manager.reload("mod", "same");
    try std.testing.expect(result.isUnchanged());
}

test "ReloadManager invalidate" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("mod", "src");
    manager.invalidate("mod");
    try std.testing.expect(manager.needsReload("mod", "src"));
}

test "ReloadManager invalidateAll" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("a", "a_src");
    try manager.registerModule("b", "b_src");
    manager.invalidateAll();
    try std.testing.expect(manager.needsReload("a", "a_src"));
    try std.testing.expect(manager.needsReload("b", "b_src"));
}

test "ReloadManager disabled" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();
    manager.enabled = false;

    try manager.registerModule("mod", "v1");
    try std.testing.expect(!manager.needsReload("mod", "v2"));
}

test "ReloadResult isSuccess" {
    const success = ReloadResult{ .state = .reloaded };
    try std.testing.expect(success.isSuccess());

    const fail = ReloadResult{ .state = .failed };
    try std.testing.expect(!fail.isSuccess());
}

test "ReloadResult isUnchanged" {
    const unchanged = ReloadResult{ .state = .unchanged };
    try std.testing.expect(unchanged.isUnchanged());

    const changed = ReloadResult{ .state = .reloaded };
    try std.testing.expect(!changed.isUnchanged());
}

test "AOTReloadBehavior isAvailable" {
    try std.testing.expect(!AOTReloadBehavior.isAvailable());
}

test "AOTReloadBehavior getLimitation" {
    const msg = AOTReloadBehavior.getLimitation();
    try std.testing.expect(msg.len > 0);
}

test "AOTReloadBehavior reload returns same" {
    var dummy: u8 = 42;
    const result = AOTReloadBehavior.reload(&dummy);
    try std.testing.expect(@intFromPtr(result) == @intFromPtr(&dummy));
}

test "getVersion existing" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    try manager.registerModule("test", "code");
    const ver = manager.getVersion("test");
    try std.testing.expect(ver != null);
    try std.testing.expectEqualStrings("test", ver.?.name);
}

test "getVersion nonexistent" {
    const allocator = std.testing.allocator;
    var manager = ReloadManager.init(allocator);
    defer manager.deinit();

    const ver = manager.getVersion("nonexistent");
    try std.testing.expect(ver == null);
}
