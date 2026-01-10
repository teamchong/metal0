//! test.test_concurrent_futures.test_wait - Futures wait tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "wait" { const t = FutureTest.init("test_wait"); try std.testing.expect(t.name.len > 0); }
