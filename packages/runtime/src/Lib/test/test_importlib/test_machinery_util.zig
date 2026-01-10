//! test.test_importlib.test_machinery_util - Tests for machinery_util
const std = @import("std");

pub const Context = struct {
    id: []const u8,
    value: i32 = 0,
    pub fn init(id: []const u8) @This() { return .{ .id = id }; }
    pub fn process(self: *@This()) void { self.value += 1; }
};

fn testBasic() !void {
    var ctx = Context.init("machinery_util");
    ctx.process();
    try std.testing.expectEqual(@as(i32, 1), ctx.value);
}

test "machinery_util" { try testBasic(); }
