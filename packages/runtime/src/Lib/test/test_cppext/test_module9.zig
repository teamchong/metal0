//! test.test_cppext.test_module9
const std = @import("std");
pub const M = struct { id: usize = 9, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module9" { const m = M{}; try std.testing.expect(m.test_fn()); }
