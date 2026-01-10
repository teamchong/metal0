//! test.test_ctypes.test_posix - Tests for POSIX-specific ctypes
//! Reference: cpython/Lib/test/test_ctypes/test_posix.py

const std = @import("std");
const builtin = @import("builtin");

pub const is_posix = builtin.os.tag != .windows;

pub const pid_t = i32;
pub const uid_t = u32;
pub const gid_t = u32;
pub const mode_t = u32;
pub const off_t = i64;
pub const size_t = usize;
pub const ssize_t = isize;

test "posix_types" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(pid_t));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(off_t));
}
