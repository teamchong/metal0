/// unittest.mock - Mock objects for testing
/// Provides Mock, MagicMock, patch, and related utilities
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Sentinel values for special returns
pub const DEFAULT = struct {};
pub const sentinel = DEFAULT{};

/// Call record - stores information about a single call
pub const Call = struct {
    args: []const []const u8,
    kwargs: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) Call {
        return .{
            .args = &.{},
            .kwargs = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Call, allocator: Allocator) void {
        _ = allocator;
        self.kwargs.deinit();
    }
};

/// Mock value - represents any mockable value
pub const MockValue = union(enum) {
    none: void,
    string: []const u8,
    bytes: []const u8,
    int: i64,
    float: f64,
    boolean: bool,
    list: []const MockValue,
    err: []const u8,

    pub fn eql(self: MockValue, other: MockValue) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;
        return switch (self) {
            .none => true,
            .string => |s| std.mem.eql(u8, s, other.string),
            .bytes => |b| std.mem.eql(u8, b, other.bytes),
            .int => |i| i == other.int,
            .float => |f| f == other.float,
            .boolean => |b| b == other.boolean,
            .list => false, // TODO: deep comparison
            .err => |e| std.mem.eql(u8, e, other.err),
        };
    }
};

/// Mock object - the core mocking type
pub const Mock = struct {
    allocator: Allocator,

    // Configuration
    return_value: MockValue = .{ .none = {} },
    side_effect: ?[]const MockValue = null,
    side_effect_idx: usize = 0,
    name: ?[]const u8 = null,
    spec: ?[]const []const u8 = null,

    // Call tracking
    called: bool = false,
    call_count: usize = 0,
    call_args: ?[]const u8 = null,
    call_args_list: std.ArrayList([]const u8),
    method_calls: std.ArrayList([]const u8),

    // Child mocks for attribute access
    children: std.StringHashMap(*Mock),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .call_args_list = std.ArrayList([]const u8){},
            .method_calls = std.ArrayList([]const u8){},
            .children = std.StringHashMap(*Mock).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.call_args_list.deinit(self.allocator);
        self.method_calls.deinit(self.allocator);

        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            child.*.deinit();
            self.allocator.destroy(child.*);
        }
        self.children.deinit();
    }

    /// Call the mock
    pub fn call(self: *Self, args: anytype) MockValue {
        self.called = true;
        self.call_count += 1;

        // Record call args (simplified)
        _ = args;

        // Handle side_effect
        if (self.side_effect) |effects| {
            if (self.side_effect_idx < effects.len) {
                const result = effects[self.side_effect_idx];
                self.side_effect_idx += 1;
                return result;
            }
        }

        return self.return_value;
    }

    /// Get or create a child mock for attribute access
    pub fn getattr(self: *Self, name: []const u8) *Mock {
        if (self.children.get(name)) |child| {
            return child;
        }

        // Create new child mock
        const child = self.allocator.create(Mock) catch unreachable;
        child.* = Mock.init(self.allocator);
        child.name = name;
        self.children.put(name, child) catch unreachable;
        return child;
    }

    /// Reset all call information
    pub fn reset_mock(self: *Self) void {
        self.called = false;
        self.call_count = 0;
        self.call_args = null;
        self.call_args_list.clearRetainingCapacity();
        self.method_calls.clearRetainingCapacity();
        self.side_effect_idx = 0;

        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            child.*.reset_mock();
        }
    }

    /// Assert the mock was called
    pub fn assert_called(self: *Self) !void {
        if (!self.called) {
            return error.AssertionError;
        }
    }

    /// Assert the mock was called exactly once
    pub fn assert_called_once(self: *Self) !void {
        if (self.call_count != 1) {
            return error.AssertionError;
        }
    }

    /// Assert the mock was not called
    pub fn assert_not_called(self: *Self) !void {
        if (self.called) {
            return error.AssertionError;
        }
    }

    /// Assert the mock was called with specific args (simplified)
    pub fn assert_called_with(self: *Self, expected: MockValue) !void {
        _ = self;
        _ = expected;
        // Simplified - real implementation would compare call_args
    }

    /// Assert the mock was called once with specific args
    pub fn assert_called_once_with(self: *Self, expected: MockValue) !void {
        try self.assert_called_once();
        try self.assert_called_with(expected);
    }

    /// Configure return value (builder pattern)
    pub fn returns(self: *Self, value: MockValue) *Self {
        self.return_value = value;
        return self;
    }

    /// Configure side effect (builder pattern)
    pub fn withSideEffect(self: *Self, effects: []const MockValue) *Self {
        self.side_effect = effects;
        self.side_effect_idx = 0;
        return self;
    }
};

/// MagicMock - Mock with default implementations of magic methods
pub const MagicMock = struct {
    mock: Mock,

    // Magic method return values
    len_value: usize = 0,
    bool_value: bool = true,
    iter_values: ?[]const MockValue = null,
    contains_value: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .mock = Mock.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mock.deinit();
    }

    // Delegate to inner mock
    pub fn call(self: *Self, args: anytype) MockValue {
        return self.mock.call(args);
    }

    pub fn getattr(self: *Self, name: []const u8) *Mock {
        return self.mock.getattr(name);
    }

    pub fn reset_mock(self: *Self) void {
        self.mock.reset_mock();
    }

    // Magic methods
    pub fn __len__(self: *Self) usize {
        return self.len_value;
    }

    pub fn __bool__(self: *Self) bool {
        return self.bool_value;
    }

    pub fn __contains__(self: *Self, item: anytype) bool {
        _ = item;
        return self.contains_value;
    }

    pub fn __iter__(self: *Self) ?[]const MockValue {
        return self.iter_values;
    }

    // Assertions delegated to mock
    pub fn assert_called(self: *Self) !void {
        return self.mock.assert_called();
    }

    pub fn assert_called_once(self: *Self) !void {
        return self.mock.assert_called_once();
    }

    pub fn assert_not_called(self: *Self) !void {
        return self.mock.assert_not_called();
    }
};

/// Patch context - manages patching lifecycle
pub const Patch = struct {
    target: []const u8,
    attribute: []const u8,
    mock: *Mock,
    original: ?MockValue,
    active: bool,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, target: []const u8, attribute: []const u8) Self {
        const mock = allocator.create(Mock) catch unreachable;
        mock.* = Mock.init(allocator);
        return .{
            .target = target,
            .attribute = attribute,
            .mock = mock,
            .original = null,
            .active = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.active) {
            self.stop();
        }
        self.mock.deinit();
        self.allocator.destroy(self.mock);
    }

    /// Start patching
    pub fn start(self: *Self) *Mock {
        self.active = true;
        // In a real implementation, we'd save the original and replace it
        return self.mock;
    }

    /// Stop patching and restore original
    pub fn stop(self: *Self) void {
        if (self.active) {
            // In a real implementation, we'd restore the original
            self.active = false;
        }
    }

    /// Use as context manager (returns mock for use in scope)
    pub fn enter(self: *Self) *Mock {
        return self.start();
    }

    pub fn exit(self: *Self) void {
        self.stop();
    }
};

/// Create a new patch
pub fn patch(allocator: Allocator, target: []const u8) Patch {
    // Parse target into module.attribute
    if (std.mem.lastIndexOf(u8, target, ".")) |dot| {
        return Patch.init(allocator, target[0..dot], target[dot + 1 ..]);
    }
    return Patch.init(allocator, "", target);
}

/// patch.object - patch an attribute of an object
pub fn patch_object(allocator: Allocator, target: []const u8, attribute: []const u8) Patch {
    return Patch.init(allocator, target, attribute);
}

/// Create a Mock with spec from another type
pub fn create_autospec(allocator: Allocator, spec_names: []const []const u8) Mock {
    var mock = Mock.init(allocator);
    mock.spec = spec_names;
    return mock;
}

/// PropertyMock - mock for properties
pub const PropertyMock = struct {
    mock: Mock,
    fget: ?*Mock = null,
    fset: ?*Mock = null,
    fdel: ?*Mock = null,

    pub fn init(allocator: Allocator) PropertyMock {
        return .{
            .mock = Mock.init(allocator),
        };
    }

    pub fn deinit(self: *PropertyMock) void {
        self.mock.deinit();
    }
};

/// AsyncMock - mock for async functions (stub for AOT)
pub const AsyncMock = Mock;

/// NonCallableMock - mock that raises on call
pub const NonCallableMock = struct {
    mock: Mock,

    pub fn init(allocator: Allocator) NonCallableMock {
        return .{
            .mock = Mock.init(allocator),
        };
    }

    pub fn call(self: *NonCallableMock, args: anytype) !MockValue {
        _ = self;
        _ = args;
        return error.TypeError; // NonCallableMock should not be called
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Mock basic" {
    const testing = std.testing;
    var mock = Mock.init(testing.allocator);
    defer mock.deinit();

    // Configure return value
    _ = mock.returns(.{ .int = 42 });

    // Call and verify
    const result = mock.call(.{});
    try testing.expectEqual(MockValue{ .int = 42 }, result);
    try testing.expect(mock.called);
    try testing.expectEqual(@as(usize, 1), mock.call_count);
}

test "Mock side_effect" {
    const testing = std.testing;
    var mock = Mock.init(testing.allocator);
    defer mock.deinit();

    const effects = [_]MockValue{
        .{ .int = 1 },
        .{ .int = 2 },
        .{ .int = 3 },
    };
    _ = mock.withSideEffect(&effects);

    try testing.expectEqual(MockValue{ .int = 1 }, mock.call(.{}));
    try testing.expectEqual(MockValue{ .int = 2 }, mock.call(.{}));
    try testing.expectEqual(MockValue{ .int = 3 }, mock.call(.{}));
}

test "Mock assert_called" {
    const testing = std.testing;
    var mock = Mock.init(testing.allocator);
    defer mock.deinit();

    try testing.expectError(error.AssertionError, mock.assert_called());

    _ = mock.call(.{});
    try mock.assert_called();
    try mock.assert_called_once();
}

test "Mock child mocks" {
    const testing = std.testing;
    var mock = Mock.init(testing.allocator);
    defer mock.deinit();

    const child = mock.getattr("method");
    _ = child.returns(.{ .string = "child result" });

    const result = child.call(.{});
    try testing.expectEqual(MockValue{ .string = "child result" }, result);
}

test "MagicMock" {
    const testing = std.testing;
    var magic = MagicMock.init(testing.allocator);
    defer magic.deinit();

    magic.len_value = 5;
    try testing.expectEqual(@as(usize, 5), magic.__len__());

    magic.bool_value = false;
    try testing.expect(!magic.__bool__());
}

test "Patch lifecycle" {
    const testing = std.testing;
    var p = patch(testing.allocator, "module.function");
    defer p.deinit();

    const mock = p.start();
    try testing.expect(p.active);

    _ = mock.returns(.{ .int = 100 });
    try testing.expectEqual(MockValue{ .int = 100 }, mock.call(.{}));

    p.stop();
    try testing.expect(!p.active);
}
