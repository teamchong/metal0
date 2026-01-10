//! test.test_doctest.test_part5 - doctest part 5 tests
const std = @import("std");
pub const Test = struct { id: usize = 5, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part5" { const t = Test{}; try std.testing.expect(t.run()); }
