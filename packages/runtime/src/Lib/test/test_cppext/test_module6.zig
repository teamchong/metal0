//! test.test_cppext.test_module6
const std = @import("std");
pub const M = struct { id: usize = 6, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module6" { const m = M{}; try std.testing.expect(m.test_fn()); }
