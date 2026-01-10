//! test.test_importlib.test_pycache - Tests for pycache
const std = @import("std");

pub const Context = struct {
    id: []const u8,
    value: i32 = 0,
    pub fn init(id: []const u8) @This() { return .{ .id = id }; }
    pub fn process(self: *@This()) void { self.value += 1; }
};

fn testBasic() !void {
    var ctx = Context.init("pycache");
    ctx.process();
    try std.testing.expectEqual(@as(i32, 1), ctx.value);
}

test "pycache" { try testBasic(); }
