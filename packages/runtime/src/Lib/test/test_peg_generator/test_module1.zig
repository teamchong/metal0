//! test.test_peg_generator.test_module1
const std = @import("std");
pub const M = struct { id: usize = 1, pub fn test_fn(self: @This()) bool { _ = self; return true; } };
test "module1" { const m = M{}; try std.testing.expect(m.test_fn()); }
