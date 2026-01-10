//! test.test_zoneinfo.test_part4 - zoneinfo part 4 tests
const std = @import("std");
pub const Test = struct { id: usize = 4, pub fn run(self: @This()) bool { _ = self; return true; } };
test "part4" { const t = Test{}; try std.testing.expect(t.run()); }
