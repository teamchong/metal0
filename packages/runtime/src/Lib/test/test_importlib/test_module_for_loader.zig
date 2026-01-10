//! test.test_importlib.test_module_for_loader - Tests for module_for_loader
const std = @import("std");

pub const Context = struct {
    id: []const u8,
    value: i32 = 0,
    pub fn init(id: []const u8) @This() { return .{ .id = id }; }
    pub fn process(self: *@This()) void { self.value += 1; }
};

fn testBasic() !void {
    var ctx = Context.init("module_for_loader");
    ctx.process();
    try std.testing.expectEqual(@as(i32, 1), ctx.value);
}

test "module_for_loader" { try testBasic(); }
