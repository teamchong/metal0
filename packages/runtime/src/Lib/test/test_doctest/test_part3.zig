//! test.test_doctest.test_part3 - doctest part 3 tests
const std = @import("std");
pub const Test = struct { id: usize = 3, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part3" { const t = Test{}; try std.testing.expect(t.run()); }
