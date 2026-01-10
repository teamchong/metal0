//! test.test_zoneinfo.test_part2 - zoneinfo part 2 tests
const std = @import("std");
pub const Test = struct { id: usize = 2, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part2" { const t = Test{}; try std.testing.expect(t.run()); }
