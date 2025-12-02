/// Python bisect module - Array bisection algorithms
const std = @import("std");
const h = @import("mod_helper.zig");

const ArraySetup = "; const _a = if (@typeInfo(@TypeOf(_a_raw)) == .@\"struct\" and @hasField(@TypeOf(_a_raw), \"items\")) _a_raw.items else &_a_raw; const _x = ";
const BisectLoop = "; var _lo: usize = 0; var _hi: usize = _a.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2;";
const InsortLoop = "; var _lo: usize = 0; var _hi: usize = _a.items.len; while (_lo < _hi) { const _mid = _lo + (_hi - _lo) / 2;";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", h.wrap2("blk: { const _a_raw = ", ArraySetup, BisectLoop ++ " if (_a[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; } } break :blk @as(i64, @intCast(_lo)); }", "@as(usize, 0)") },
    .{ "bisect_right", h.wrap2("blk: { const _a_raw = ", ArraySetup, BisectLoop ++ " if (_x < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } break :blk @as(i64, @intCast(_lo)); }", "@as(usize, 0)") },
    .{ "bisect", h.wrap2("blk: { const _a_raw = ", ArraySetup, BisectLoop ++ " if (_x < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } break :blk @as(i64, @intCast(_lo)); }", "@as(usize, 0)") },
    .{ "insort_left", h.wrap2("blk: { var _a = ", "; const _x = ", InsortLoop ++ " if (_a.items[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; } } _a.insert(__global_allocator, _lo, _x) catch {}; break :blk; }", "{}") },
    .{ "insort_right", h.wrap2("blk: { var _a = ", "; const _x = ", InsortLoop ++ " if (_x < _a.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } _a.insert(__global_allocator, _lo, _x) catch {}; break :blk; }", "{}") },
    .{ "insort", h.wrap2("blk: { var _a = ", "; const _x = ", InsortLoop ++ " if (_x < _a.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; } } _a.insert(__global_allocator, _lo, _x) catch {}; break :blk; }", "{}") },
});
