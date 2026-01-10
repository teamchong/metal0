//! test.test_ast.test_part8 - ast part 8 tests
const std = @import("std");
pub const Test = struct { id: usize = 8, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part8" { const t = Test{}; try std.testing.expect(t.run()); }
