//! test.test_doctest.test_part6 - doctest part 6 tests
const std = @import("std");
pub const Test = struct { id: usize = 6, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part6" { const t = Test{}; try std.testing.expect(t.run()); }
