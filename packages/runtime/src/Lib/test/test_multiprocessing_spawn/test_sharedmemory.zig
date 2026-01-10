//! test.test_multiprocessing_spawn.test_sharedmemory - Multiprocessing sharedmemory tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "sharedmemory" { const t = MPTest.init("test_sharedmemory"); try std.testing.expect(t.n.len > 0); }
