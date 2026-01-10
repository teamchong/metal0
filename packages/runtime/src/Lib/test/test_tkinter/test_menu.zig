//! test.test_tkinter.test_menu - Tk menu tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "menu" { const t = TkTest.init("test_menu"); try std.testing.expect(t.name.len > 0); }
