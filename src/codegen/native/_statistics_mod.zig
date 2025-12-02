/// Python _statistics module - Internal statistics support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "normal_dist_inv_cdf", h.F64(0.0) },
});
