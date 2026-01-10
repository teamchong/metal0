//! test.test_tkinter.test_text - Tk text tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "text" { const t = TkTest.init("test_text"); try std.testing.expect(t.name.len > 0); }
