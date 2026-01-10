//! test.regrtestdata - Regression test data
const std = @import("std");

pub const TestData = struct {
    name: []const u8,
    data: []const u8,
    expected: []const u8,
    
    pub fn init(name: []const u8, data: []const u8, expected: []const u8) @This() {
        return .{ .name = name, .data = data, .expected = expected };
    }
    
    pub fn verify(self: @This()) bool {
        return std.mem.eql(u8, self.data, self.expected) or self.expected.len == 0;
    }
};

pub const RegressionTest = struct {
    name: []const u8,
    test_data: std.ArrayList(TestData),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .test_data = std.ArrayList(TestData).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.test_data.deinit();
    }
    
    pub fn addData(self: *@This(), data: TestData) !void {
        try self.test_data.append(data);
    }
    
    pub fn runAll(self: @This()) usize {
        var passed: usize = 0;
        for (self.test_data.items) |td| {
            if (td.verify()) passed += 1;
        }
        return passed;
    }
};

test "test_data_verify" {
    const td = TestData.init("test1", "hello", "hello");
    try std.testing.expect(td.verify());
}

test "regression_test" {
    var rt = RegressionTest.init(std.testing.allocator, "regr1");
    defer rt.deinit();
    try rt.addData(TestData.init("t1", "a", "a"));
    try std.testing.expectEqual(@as(usize, 1), rt.runAll());
}
