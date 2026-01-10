//! test.test_ttk.test_widgets - Tk widgets tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "widgets" { const t = TkTest.init("test_widgets"); try std.testing.expect(t.name.len > 0); }
