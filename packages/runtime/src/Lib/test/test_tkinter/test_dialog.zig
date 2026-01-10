//! test.test_tkinter.test_dialog - Tk dialog tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "dialog" { const t = TkTest.init("test_dialog"); try std.testing.expect(t.name.len > 0); }
