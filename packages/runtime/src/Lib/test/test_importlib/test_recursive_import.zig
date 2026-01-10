//! test.test_importlib.test_recursive_import - Tests for recursive_import
const std = @import("std");

pub const Context = struct {
    id: []const u8,
    value: i32 = 0,
    pub fn init(id: []const u8) @This() { return .{ .id = id }; }
    pub fn process(self: *@This()) void { self.value += 1; }
};

fn testBasic() !void {
    var ctx = Context.init("recursive_import");
    ctx.process();
    try std.testing.expectEqual(@as(i32, 1), ctx.value);
}

test "recursive_import" { try testBasic(); }
