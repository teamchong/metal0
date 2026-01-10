//! test.test_interpreters.test_module10
const std = @import("std");
pub const M = struct { id: usize = 10, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module10" { const m = M{}; try std.testing.expect(m.test_fn()); }
