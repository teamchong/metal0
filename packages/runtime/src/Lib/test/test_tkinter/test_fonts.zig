//! test.test_tkinter.test_fonts - Tk fonts tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "fonts" { const t = TkTest.init("test_fonts"); try std.testing.expect(t.name.len > 0); }
