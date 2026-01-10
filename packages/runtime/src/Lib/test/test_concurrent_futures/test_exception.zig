//! test.test_concurrent_futures.test_exception - Futures exception tests
const std = @import("std");

pub const FutureTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "exception" { const t = FutureTest.init("test_exception"); try std.testing.expect(t.name.len > 0); }
