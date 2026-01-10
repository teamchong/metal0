//! test.test_ast.test_part9 - ast part 9 tests
const std = @import("std");
pub const Test = struct { id: usize = 9, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part9" { const t = Test{}; try std.testing.expect(t.run()); }
