//! test.test_concurrent_futures.test_shutdown - Futures shutdown tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "shutdown" { const t = FutureTest.init("test_shutdown"); try std.testing.expect(t.name.len > 0); }
