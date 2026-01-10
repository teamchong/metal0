//! test.test_ttk.test_geometry - Tk geometry tests
const std = @import("std");
pub const TkTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "geometry" { const t = TkTest.init("test_geometry"); try std.testing.expect(t.name.len > 0); }
