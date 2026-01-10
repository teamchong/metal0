//! test.test_importlib.test_pyc_source - Tests for pyc_source
const std = @import("std");

pub const Context = struct {
    id: []const u8,
    value: i32 = 0,
    pub fn init(id: []const u8) @This() { return .{ .id = id }; }
    pub fn process(self: *@This()) void { self.value += 1; }
};

fn testBasic() !void {
    var ctx = Context.init("pyc_source");
    ctx.process();
    try std.testing.expectEqual(@as(i32, 1), ctx.value);
}

test "pyc_source" { try testBasic(); }
