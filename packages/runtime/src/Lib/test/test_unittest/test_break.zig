//! test.test_unittest.test_break - Unittest break tests
const std = @import("std");

pub const TestConfig = struct {
    name: []const u8,
    enabled: bool = true,
    verbose: bool = false,
    
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
};

pub const TestContext = struct {
    allocator: std.mem.Allocator,
    passed: usize = 0,
    failed: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn recordPass(self: *@This()) void { self.passed += 1; }
    pub fn recordFail(self: *@This()) void { self.failed += 1; }
    pub fn wasSuccessful(self: @This()) bool { return self.failed == 0; }
};

test "break_config" {
    const cfg = TestConfig.init("test_break");
    try std.testing.expect(cfg.enabled);
}

test "break_context" {
    var ctx = TestContext.init(std.testing.allocator);
    ctx.recordPass();
    try std.testing.expect(ctx.wasSuccessful());
}
