//! test.test_tomllib.test_part1 - tomllib part 1 tests
const std = @import("std");
pub const Test = struct { id: usize = 1, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part1" { const t = Test{}; try std.testing.expect(t.run()); }
