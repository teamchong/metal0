//! test.test_doctest.test_part7 - Fixtures implementation
//! setUp, tearDown, and fixture support for doctests.
const std = @import("std");

/// Fixture lifecycle phase
pub const FixturePhase = enum {
    setup,
    teardown,
    before_each,
    after_each,
};

/// Fixture function type
pub const FixtureFn = *const fn (ctx: *FixtureContext) anyerror!void;

/// Context passed to fixture functions
pub const FixtureContext = struct {
    allocator: std.mem.Allocator,
    globals: std.StringHashMap([]const u8),
    temp_files: std.ArrayList([]const u8),
    test_name: []const u8,
    phase: FixturePhase,

    pub fn init(allocator: std.mem.Allocator, test_name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .globals = std.StringHashMap([]const u8).init(allocator),
            .temp_files = std.ArrayList([]const u8).init(allocator),
            .test_name = test_name,
            .phase = .setup,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.globals.deinit();
        self.temp_files.deinit();
    }

    /// Set a global variable for the test
    pub fn setGlobal(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.globals.put(name, value);
    }

    /// Get a global variable
    pub fn getGlobal(self: @This(), name: []const u8) ?[]const u8 {
        return self.globals.get(name);
    }

    /// Register a temp file for cleanup
    pub fn registerTempFile(self: *@This(), path: []const u8) !void {
        try self.temp_files.append(path);
    }

    /// Clean up all registered temp files
    pub fn cleanupTempFiles(self: *@This()) void {
        for (self.temp_files.items) |_| {
            // In real impl, would delete files
        }
        self.temp_files.clearRetainingCapacity();
    }
};

/// Fixture registry for managing test fixtures
pub const FixtureRegistry = struct {
    allocator: std.mem.Allocator,
    setup_fns: std.ArrayList(FixtureFn),
    teardown_fns: std.ArrayList(FixtureFn),
    before_each_fns: std.ArrayList(FixtureFn),
    after_each_fns: std.ArrayList(FixtureFn),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .setup_fns = std.ArrayList(FixtureFn).init(allocator),
            .teardown_fns = std.ArrayList(FixtureFn).init(allocator),
            .before_each_fns = std.ArrayList(FixtureFn).init(allocator),
            .after_each_fns = std.ArrayList(FixtureFn).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.setup_fns.deinit();
        self.teardown_fns.deinit();
        self.before_each_fns.deinit();
        self.after_each_fns.deinit();
    }

    pub fn addSetUp(self: *@This(), func: FixtureFn) !void {
        try self.setup_fns.append(func);
    }

    pub fn addTearDown(self: *@This(), func: FixtureFn) !void {
        try self.teardown_fns.append(func);
    }

    pub fn addBeforeEach(self: *@This(), func: FixtureFn) !void {
        try self.before_each_fns.append(func);
    }

    pub fn addAfterEach(self: *@This(), func: FixtureFn) !void {
        try self.after_each_fns.append(func);
    }

    pub fn runSetUp(self: @This(), ctx: *FixtureContext) !void {
        ctx.phase = .setup;
        for (self.setup_fns.items) |func| {
            try func(ctx);
        }
    }

    pub fn runTearDown(self: @This(), ctx: *FixtureContext) !void {
        ctx.phase = .teardown;
        for (self.teardown_fns.items) |func| {
            try func(ctx);
        }
    }

    pub fn runBeforeEach(self: @This(), ctx: *FixtureContext) !void {
        ctx.phase = .before_each;
        for (self.before_each_fns.items) |func| {
            try func(ctx);
        }
    }

    pub fn runAfterEach(self: @This(), ctx: *FixtureContext) !void {
        ctx.phase = .after_each;
        for (self.after_each_fns.items) |func| {
            try func(ctx);
        }
    }
};

/// Fixture scope (when fixtures are created/destroyed)
pub const FixtureScope = enum {
    /// Created once per module
    module,
    /// Created once per class
    class,
    /// Created once per function
    function,
    /// Created for each example
    example,
};

/// Named fixture definition
pub const FixtureDefinition = struct {
    name: []const u8,
    scope: FixtureScope,
    setup_fn: ?FixtureFn,
    teardown_fn: ?FixtureFn,
    dependencies: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .name = name,
            .scope = .function,
            .setup_fn = null,
            .teardown_fn = null,
            .dependencies = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.dependencies.deinit();
    }

    pub fn addDependency(self: *@This(), dep_name: []const u8) !void {
        try self.dependencies.append(dep_name);
    }

    pub fn hasDependencies(self: @This()) bool {
        return self.dependencies.items.len > 0;
    }
};

/// Globs (global namespace) manager for doctest execution
pub const GlobsManager = struct {
    allocator: std.mem.Allocator,
    globs: std.StringHashMap([]const u8),
    extra_globs: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .globs = std.StringHashMap([]const u8).init(allocator),
            .extra_globs = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.globs.deinit();
        self.extra_globs.deinit();
    }

    pub fn setGlob(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.globs.put(name, value);
    }

    pub fn setExtraGlob(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.extra_globs.put(name, value);
    }

    pub fn getGlob(self: @This(), name: []const u8) ?[]const u8 {
        return self.extra_globs.get(name) orelse self.globs.get(name);
    }

    pub fn copy(self: @This(), allocator: std.mem.Allocator) !GlobsManager {
        var new_globs = GlobsManager.init(allocator);

        var iter = self.globs.iterator();
        while (iter.next()) |entry| {
            try new_globs.setGlob(entry.key_ptr.*, entry.value_ptr.*);
        }

        var extra_iter = self.extra_globs.iterator();
        while (extra_iter.next()) |entry| {
            try new_globs.setExtraGlob(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_globs;
    }

    pub fn clear(self: *@This()) void {
        self.globs.clearRetainingCapacity();
        self.extra_globs.clearRetainingCapacity();
    }
};

/// Output capture for test isolation
pub const OutputCapture = struct {
    stdout_buffer: std.ArrayList(u8),
    stderr_buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    capturing: bool = false,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .stdout_buffer = std.ArrayList(u8).init(allocator),
            .stderr_buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.stdout_buffer.deinit();
        self.stderr_buffer.deinit();
    }

    pub fn startCapture(self: *@This()) void {
        self.capturing = true;
        self.stdout_buffer.clearRetainingCapacity();
        self.stderr_buffer.clearRetainingCapacity();
    }

    pub fn stopCapture(self: *@This()) void {
        self.capturing = false;
    }

    pub fn writeStdout(self: *@This(), data: []const u8) !void {
        if (self.capturing) {
            try self.stdout_buffer.appendSlice(data);
        }
    }

    pub fn writeStderr(self: *@This(), data: []const u8) !void {
        if (self.capturing) {
            try self.stderr_buffer.appendSlice(data);
        }
    }

    pub fn getStdout(self: @This()) []const u8 {
        return self.stdout_buffer.items;
    }

    pub fn getStderr(self: @This()) []const u8 {
        return self.stderr_buffer.items;
    }

    pub fn getCombined(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        var combined = std.ArrayList(u8).init(allocator);
        try combined.appendSlice(self.stdout_buffer.items);
        try combined.appendSlice(self.stderr_buffer.items);
        return combined.toOwnedSlice();
    }
};

/// Test isolation - manage state between tests
pub const TestIsolation = struct {
    globs_manager: GlobsManager,
    output_capture: OutputCapture,
    fixture_registry: FixtureRegistry,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .globs_manager = GlobsManager.init(allocator),
            .output_capture = OutputCapture.init(allocator),
            .fixture_registry = FixtureRegistry.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.globs_manager.deinit();
        self.output_capture.deinit();
        self.fixture_registry.deinit();
    }

    pub fn setupTest(self: *@This(), ctx: *FixtureContext) !void {
        try self.fixture_registry.runSetUp(ctx);
        self.output_capture.startCapture();
    }

    pub fn teardownTest(self: *@This(), ctx: *FixtureContext) !void {
        self.output_capture.stopCapture();
        try self.fixture_registry.runTearDown(ctx);
    }

    pub fn beforeExample(self: *@This(), ctx: *FixtureContext) !void {
        try self.fixture_registry.runBeforeEach(ctx);
    }

    pub fn afterExample(self: *@This(), ctx: *FixtureContext) !void {
        try self.fixture_registry.runAfterEach(ctx);
    }
};

// ============================================================================
// Example fixture functions for testing
// ============================================================================

fn setupDatabase(ctx: *FixtureContext) !void {
    try ctx.setGlobal("db_connected", "true");
}

fn teardownDatabase(ctx: *FixtureContext) !void {
    try ctx.setGlobal("db_connected", "false");
}

fn createTempDir(ctx: *FixtureContext) !void {
    try ctx.registerTempFile("/tmp/doctest_temp");
}

fn cleanupTempDir(ctx: *FixtureContext) !void {
    ctx.cleanupTempFiles();
}

// ============================================================================
// Tests
// ============================================================================

test "FixtureContext_init" {
    var ctx = FixtureContext.init(std.testing.allocator, "test_example");
    defer ctx.deinit();

    try std.testing.expectEqualStrings("test_example", ctx.test_name);
    try std.testing.expectEqual(FixturePhase.setup, ctx.phase);
}

test "FixtureContext_globals" {
    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try ctx.setGlobal("x", "42");
    try std.testing.expectEqualStrings("42", ctx.getGlobal("x").?);
    try std.testing.expect(ctx.getGlobal("y") == null);
}

test "FixtureContext_tempFiles" {
    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try ctx.registerTempFile("/tmp/test1.txt");
    try ctx.registerTempFile("/tmp/test2.txt");

    try std.testing.expectEqual(@as(usize, 2), ctx.temp_files.items.len);

    ctx.cleanupTempFiles();
    try std.testing.expectEqual(@as(usize, 0), ctx.temp_files.items.len);
}

test "FixtureRegistry_init" {
    var registry = FixtureRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.setup_fns.items.len);
}

test "FixtureRegistry_addSetUp" {
    var registry = FixtureRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.addSetUp(setupDatabase);
    try std.testing.expectEqual(@as(usize, 1), registry.setup_fns.items.len);
}

test "FixtureRegistry_runSetUp" {
    var registry = FixtureRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.addSetUp(setupDatabase);

    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try registry.runSetUp(&ctx);

    try std.testing.expectEqualStrings("true", ctx.getGlobal("db_connected").?);
}

test "FixtureRegistry_runTearDown" {
    var registry = FixtureRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.addTearDown(teardownDatabase);

    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try ctx.setGlobal("db_connected", "true");
    try registry.runTearDown(&ctx);

    try std.testing.expectEqualStrings("false", ctx.getGlobal("db_connected").?);
}

test "FixtureRegistry_beforeAfterEach" {
    var registry = FixtureRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.addBeforeEach(createTempDir);
    try registry.addAfterEach(cleanupTempDir);

    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try registry.runBeforeEach(&ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.temp_files.items.len);

    try registry.runAfterEach(&ctx);
    try std.testing.expectEqual(@as(usize, 0), ctx.temp_files.items.len);
}

test "FixtureDefinition_init" {
    var def = FixtureDefinition.init(std.testing.allocator, "my_fixture");
    defer def.deinit();

    try std.testing.expectEqualStrings("my_fixture", def.name);
    try std.testing.expectEqual(FixtureScope.function, def.scope);
}

test "FixtureDefinition_dependencies" {
    var def = FixtureDefinition.init(std.testing.allocator, "fixture");
    defer def.deinit();

    try std.testing.expect(!def.hasDependencies());

    try def.addDependency("other_fixture");
    try std.testing.expect(def.hasDependencies());
}

test "GlobsManager_init" {
    var gm = GlobsManager.init(std.testing.allocator);
    defer gm.deinit();

    try std.testing.expect(gm.getGlob("any") == null);
}

test "GlobsManager_setAndGet" {
    var gm = GlobsManager.init(std.testing.allocator);
    defer gm.deinit();

    try gm.setGlob("x", "1");
    try gm.setExtraGlob("y", "2");

    try std.testing.expectEqualStrings("1", gm.getGlob("x").?);
    try std.testing.expectEqualStrings("2", gm.getGlob("y").?);
}

test "GlobsManager_extraOverridesBase" {
    var gm = GlobsManager.init(std.testing.allocator);
    defer gm.deinit();

    try gm.setGlob("x", "base");
    try gm.setExtraGlob("x", "extra");

    try std.testing.expectEqualStrings("extra", gm.getGlob("x").?);
}

test "GlobsManager_copy" {
    var gm = GlobsManager.init(std.testing.allocator);
    defer gm.deinit();

    try gm.setGlob("x", "1");

    var copy = try gm.copy(std.testing.allocator);
    defer copy.deinit();

    try std.testing.expectEqualStrings("1", copy.getGlob("x").?);
}

test "OutputCapture_init" {
    var capture = OutputCapture.init(std.testing.allocator);
    defer capture.deinit();

    try std.testing.expect(!capture.capturing);
}

test "OutputCapture_capture" {
    var capture = OutputCapture.init(std.testing.allocator);
    defer capture.deinit();

    capture.startCapture();
    try std.testing.expect(capture.capturing);

    try capture.writeStdout("hello ");
    try capture.writeStdout("world");

    capture.stopCapture();

    try std.testing.expectEqualStrings("hello world", capture.getStdout());
}

test "OutputCapture_stderr" {
    var capture = OutputCapture.init(std.testing.allocator);
    defer capture.deinit();

    capture.startCapture();
    try capture.writeStderr("error message");
    capture.stopCapture();

    try std.testing.expectEqualStrings("error message", capture.getStderr());
}

test "OutputCapture_getCombined" {
    var capture = OutputCapture.init(std.testing.allocator);
    defer capture.deinit();

    capture.startCapture();
    try capture.writeStdout("out ");
    try capture.writeStderr("err");
    capture.stopCapture();

    const combined = try capture.getCombined(std.testing.allocator);
    defer std.testing.allocator.free(combined);

    try std.testing.expectEqualStrings("out err", combined);
}

test "TestIsolation_init" {
    var isolation = TestIsolation.init(std.testing.allocator);
    defer isolation.deinit();

    try std.testing.expect(!isolation.output_capture.capturing);
}

test "TestIsolation_setupAndTeardown" {
    var isolation = TestIsolation.init(std.testing.allocator);
    defer isolation.deinit();

    try isolation.fixture_registry.addSetUp(setupDatabase);
    try isolation.fixture_registry.addTearDown(teardownDatabase);

    var ctx = FixtureContext.init(std.testing.allocator, "test");
    defer ctx.deinit();

    try isolation.setupTest(&ctx);
    try std.testing.expect(isolation.output_capture.capturing);
    try std.testing.expectEqualStrings("true", ctx.getGlobal("db_connected").?);

    try isolation.teardownTest(&ctx);
    try std.testing.expect(!isolation.output_capture.capturing);
    try std.testing.expectEqualStrings("false", ctx.getGlobal("db_connected").?);
}
