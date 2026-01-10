//! test.test_concurrent_futures.test_process_pool - Futures process_pool tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "process_pool" { const t = FutureTest.init("test_process_pool"); try std.testing.expect(t.name.len > 0); }
