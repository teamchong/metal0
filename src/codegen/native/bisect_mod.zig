/// Python bisect module - Array bisection algorithms
const std = @import("std");
const h = @import("mod_helper.zig");

const ArraySetup = "const _a = if (@typeInfo(@TypeOf(__v0)) == .@\"struct\" and @hasField(@TypeOf(__v0), \"items\")) __v0.items else &__v0; ";
const BisectLoop = "var _lo: usize = 0; var _hi: usize = _a.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2;";
const InsortLoop = "var _lo: usize = 0; var _hi: usize = __v0.items.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2;";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", h.wrap2Blk("bsl", ArraySetup ++ BisectLoop ++ " if (_a[_mid] < __v1) { _lo = _mid + 1; } else { _hi = _mid; } }", "@as(i64, @intCast(_lo))", "@as(usize, 0)") },
    .{ "bisect_right", h.wrap2Blk("bsr", ArraySetup ++ BisectLoop ++ " if (__v1 < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } }", "@as(i64, @intCast(_lo))", "@as(usize, 0)") },
    .{ "bisect", h.wrap2Blk("bs", ArraySetup ++ BisectLoop ++ " if (__v1 < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } }", "@as(i64, @intCast(_lo))", "@as(usize, 0)") },
    .{ "insort_left", h.wrap2Blk("inl", InsortLoop ++ " if (__v0.items[_mid] < __v1) { _lo = _mid + 1; } else { _hi = _mid; } } __v0.insert(__global_allocator, _lo, __v1) catch unreachable;", "{}", "{}") },
    .{ "insort_right", h.wrap2Blk("inr", InsortLoop ++ " if (__v1 < __v0.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } __v0.insert(__global_allocator, _lo, __v1) catch unreachable;", "{}", "{}") },
    .{ "insort", h.wrap2Blk("ins", InsortLoop ++ " if (__v1 < __v0.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } __v0.insert(__global_allocator, _lo, __v1) catch unreachable;", "{}", "{}") },
});
