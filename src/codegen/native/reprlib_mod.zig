/// Python reprlib module - Alternate repr() implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Repr", h.c(".{ .maxlevel = 6, .maxtuple = 6, .maxlist = 6, .maxarray = 5, .maxdict = 4, .maxset = 6, .maxfrozenset = 6, .maxdeque = 6, .maxstring = 30, .maxlong = 40, .maxother = 30, .fillvalue = \"...\" }") },
    .{ "repr", h.wrap("blk: { const obj = ", "; break :blk std.fmt.allocPrint(metal0_allocator, \"{any}\", .{obj}) catch \"<repr error>\"; }", "\"\"") },
    .{ "recursive_repr", h.c("@as(?*const fn(anytype) anytype, null)") },
});
