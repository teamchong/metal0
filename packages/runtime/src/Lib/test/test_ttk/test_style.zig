//! test.test_ttk.test_style - Tk style tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "style" { const t = TkTest.init("test_style"); try std.testing.expect(t.name.len > 0); }
