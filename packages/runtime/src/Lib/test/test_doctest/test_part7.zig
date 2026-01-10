//! test.test_doctest.test_part7 - doctest part 7 tests
const std = @import("std");
pub const Test = struct { id: usize = 7, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part7" { const t = Test{}; try std.testing.expect(t.run()); }
