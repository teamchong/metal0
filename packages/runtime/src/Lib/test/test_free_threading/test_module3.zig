//! test.test_free_threading.test_module3
const std = @import("std");
pub const M = struct { id: usize = 3, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module3" { const m = M{}; try std.testing.expect(m.test_fn()); }
