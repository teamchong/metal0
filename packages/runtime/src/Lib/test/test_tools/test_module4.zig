//! test.test_tools.test_module4
const std = @import("std");
pub const M = struct { id: usize = 4, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module4" { const m = M{}; try std.testing.expect(m.test_fn()); }
