//! test.test_cppext.test_module8
const std = @import("std");
pub const M = struct { id: usize = 8, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module8" { const m = M{}; try std.testing.expect(m.test_fn()); }
