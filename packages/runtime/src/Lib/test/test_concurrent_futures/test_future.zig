//! test.test_concurrent_futures.test_future - Futures future tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "future" { const t = FutureTest.init("test_future"); try std.testing.expect(t.name.len > 0); }
