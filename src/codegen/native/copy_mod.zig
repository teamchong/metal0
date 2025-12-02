/// Python copy module - copy, deepcopy
const std = @import("std");
const h = @import("mod_helper.zig");

pub const genCopy = h.wrap("copy_blk: { const _src = ", "; if (@typeInfo(@TypeOf(_src)) == .@\"struct\" and @hasField(@TypeOf(_src), \"items\")) { var _copy = @TypeOf(_src).init(__global_allocator); _copy.appendSlice(__global_allocator, _src.items) catch {}; break :copy_blk _copy; } break :copy_blk _src; }", "void{}");
pub const genDeepcopy = h.wrap("deepcopy_blk: { const _src = ", "; if (@TypeOf(_src) == i64 or @TypeOf(_src) == f64 or @TypeOf(_src) == bool or @TypeOf(_src) == []const u8) { break :deepcopy_blk _src; } if (@typeInfo(@TypeOf(_src)) == .@\"struct\" and @hasField(@TypeOf(_src), \"items\")) { var _copy = @TypeOf(_src).init(__global_allocator); for (_src.items) |item| { _copy.append(__global_allocator, item) catch continue; } break :deepcopy_blk _copy; } break :deepcopy_blk _src; }", "void{}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy }, .{ "deepcopy", genDeepcopy }, .{ "replace", h.pass("void{}") },
});
