/// Python _frozen_importlib_external module - External frozen import machinery
const std = @import("std");
const h = @import("mod_helper.zig");

const genSourceFileLoader = h.wrap2("blk: { const name = ", "; const path = ", "; break :blk .{ .name = name, .path = path }; }", ".{ .name = \"\", .path = \"\" }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "source_file_loader", genSourceFileLoader }, .{ "sourceless_file_loader", h.c(".{ .name = \"\", .path = \"\" }") }, .{ "extension_file_loader", h.c(".{ .name = \"\", .path = \"\" }") },
    .{ "file_finder", h.c(".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }") }, .{ "path_finder", h.c(".{}") }, .{ "get_supported_file_loaders", h.c("&[_]@TypeOf(.{}){}") },
    .{ "install", h.c("{}") }, .{ "cache_from_source", h.pass("\"\"") }, .{ "source_from_cache", h.pass("\"\"") },
    .{ "spec_from_file_location", h.c(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }") },
    .{ "b_y_t_e_c_o_d_e__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".pyc\" }") }, .{ "s_o_u_r_c_e__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".py\" }") }, .{ "e_x_t_e_n_s_i_o_n__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }") },
});
