//! test.test_tkinter.test_canvas - Tk canvas tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "canvas" { const t = TkTest.init("test_canvas"); try std.testing.expect(t.name.len > 0); }
