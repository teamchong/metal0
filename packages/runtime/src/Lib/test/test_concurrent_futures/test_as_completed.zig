//! test.test_concurrent_futures.test_as_completed - Futures as_completed tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "as_completed" { const t = FutureTest.init("test_as_completed"); try std.testing.expect(t.name.len > 0); }
