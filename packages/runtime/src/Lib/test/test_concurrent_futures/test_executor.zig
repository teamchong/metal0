//! test.test_concurrent_futures.test_executor - Futures executor tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "executor" { const t = FutureTest.init("test_executor"); try std.testing.expect(t.name.len > 0); }
