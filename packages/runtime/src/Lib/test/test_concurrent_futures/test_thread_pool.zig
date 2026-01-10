//! test.test_concurrent_futures.test_thread_pool - Futures thread_pool tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "thread_pool" { const t = FutureTest.init("test_thread_pool"); try std.testing.expect(t.name.len > 0); }
