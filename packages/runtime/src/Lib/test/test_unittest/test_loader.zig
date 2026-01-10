//! test.test_unittest.test_loader - Test loader tests
const std = @import("std");

pub const TestLoader = struct {
    allocator: std.mem.Allocator,
    suiteClass: type = TestSuite,
    testMethodPrefix: []const u8 = "test",
    sortTestMethodsUsing: ?*const fn ([]const u8, []const u8) bool = null,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn loadTestsFromTestCase(self: @This(), comptime TestCaseClass: type) TestSuite {
        var suite = TestSuite.init(self.allocator);
        const decls = @typeInfo(TestCaseClass).@"struct".decls;
        inline for (decls) |decl| {
            if (std.mem.startsWith(u8, decl.name, self.testMethodPrefix)) {
                suite.addTest(decl.name) catch {};
            }
        }
        return suite;
    }
    
    pub fn loadTestsFromModule(self: @This(), module_name: []const u8) TestSuite {
        _ = module_name;
        return TestSuite.init(self.allocator);
    }
    
    pub fn loadTestsFromName(self: @This(), name: []const u8) TestSuite {
        _ = name;
        return TestSuite.init(self.allocator);
    }
    
    pub fn loadTestsFromNames(self: @This(), names: []const []const u8) TestSuite {
        var suite = TestSuite.init(self.allocator);
        for (names) |name| {
            _ = suite.addTest(name) catch {};
        }
        return suite;
    }
    
    pub fn discover(self: @This(), start_dir: []const u8, pattern: []const u8) TestSuite {
        _ = start_dir; _ = pattern;
        return TestSuite.init(self.allocator);
    }
};

pub const TestSuite = struct {
    tests: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator, .tests = std.ArrayList([]const u8).init(allocator) };
    }
    
    pub fn deinit(self: *@This()) void {
        self.tests.deinit();
    }
    
    pub fn addTest(self: *@This(), name: []const u8) !void {
        try self.tests.append(name);
    }
    
    pub fn countTestCases(self: @This()) usize {
        return self.tests.items.len;
    }
};

test "loader_init" {
    const loader = TestLoader.init(std.testing.allocator);
    try std.testing.expectEqualStrings("test", loader.testMethodPrefix);
}

test "loader_load_from_names" {
    const loader = TestLoader.init(std.testing.allocator);
    const names = [_][]const u8{ "test1", "test2", "test3" };
    var suite = loader.loadTestsFromNames(&names);
    defer suite.deinit();
    try std.testing.expectEqual(@as(usize, 3), suite.countTestCases());
}

test "suite_add_test" {
    var suite = TestSuite.init(std.testing.allocator);
    defer suite.deinit();
    try suite.addTest("test_foo");
    try suite.addTest("test_bar");
    try std.testing.expectEqual(@as(usize, 2), suite.countTestCases());
}
