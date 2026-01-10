//! test.test_interpreters.test_module5
const std = @import("std");
pub const M = struct { id: usize = 5, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module5" { const m = M{}; try std.testing.expect(m.test_fn()); }
