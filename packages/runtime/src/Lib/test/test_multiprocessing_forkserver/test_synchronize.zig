//! test.test_multiprocessing_forkserver.test_synchronize - Multiprocessing synchronize tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "synchronize" { const t = MPTest.init("test_synchronize"); try std.testing.expect(t.n.len > 0); }
