//! test.test_zipfile.test_write - Zipfile write tests
const std = @import("std");
pub const ZipTest = struct { path: []const u8, pub fn init(p: []const u8) @This() { return .{ .path = p }; } };
test "write" { const t = ZipTest.init("test.zip"); try std.testing.expect(t.path.len > 0); }
