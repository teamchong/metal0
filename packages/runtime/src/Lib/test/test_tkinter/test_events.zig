//! test.test_tkinter.test_events - Tk events tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "events" { const t = TkTest.init("test_events"); try std.testing.expect(t.name.len > 0); }
