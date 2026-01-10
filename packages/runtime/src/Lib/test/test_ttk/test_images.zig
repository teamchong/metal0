//! test.test_ttk.test_images - Tk images tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "images" { const t = TkTest.init("test_images"); try std.testing.expect(t.name.len > 0); }
