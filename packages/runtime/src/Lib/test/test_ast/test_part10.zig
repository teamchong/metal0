//! test.test_ast.test_part10 - ast part 10 tests
const std = @import("std");
pub const Test = struct { id: usize = 10, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part10" { const t = Test{}; try std.testing.expect(t.run()); }
