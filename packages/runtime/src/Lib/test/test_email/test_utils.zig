//! test.test_email.test_utils - Email utils tests
const std = @import("std");

pub const Config = struct {
    name: []const u8 = "test_utils",
    enabled: bool = true,
    
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn validate(self: @This()) bool { return self.enabled; }
};

pub const TestContext = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(bool),
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator, .results = std.ArrayList(bool).init(allocator) };
    }
    
    pub fn deinit(self: *@This()) void { self.results.deinit(); }
    
    pub fn addResult(self: *@This(), passed: bool) !void { try self.results.append(passed); }
    
    pub fn allPassed(self: @This()) bool {
        for (self.results.items) |r| { if (!r) return false; }
        return true;
    }
};

test "utils_config" {
    const cfg = Config.init("test");
    try std.testing.expect(cfg.validate());
}

test "utils_context" {
    var ctx = TestContext.init(std.testing.allocator);
    defer ctx.deinit();
    try ctx.addResult(true);
    try std.testing.expect(ctx.allPassed());
}
