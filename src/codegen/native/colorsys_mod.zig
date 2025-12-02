/// Python colorsys module - Color system conversions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "rgb_to_yiq", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "yiq_to_rgb", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "rgb_to_hls", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "hls_to_rgb", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "rgb_to_hsv", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
    .{ "hsv_to_rgb", h.c(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }") },
});
