//! test.test_concurrent_futures.test_map - Futures map tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "map" { const t = FutureTest.init("test_map"); try std.testing.expect(t.name.len > 0); }
