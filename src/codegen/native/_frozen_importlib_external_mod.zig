/// Python _frozen_importlib_external module - External frozen import machinery
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "source_file_loader", genSourceFileLoader }, .{ "sourceless_file_loader", h.c(".{ .name = \"\", .path = \"\" }") }, .{ "extension_file_loader", h.c(".{ .name = \"\", .path = \"\" }") },
    .{ "file_finder", h.c(".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }") }, .{ "path_finder", h.c(".{}") }, .{ "get_supported_file_loaders", h.c("&[_]@TypeOf(.{}){}") },
    .{ "install", h.c("{}") }, .{ "cache_from_source", h.pass("\"\"") }, .{ "source_from_cache", h.pass("\"\"") },
    .{ "spec_from_file_location", h.c(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }") },
    .{ "b_y_t_e_c_o_d_e__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".pyc\" }") }, .{ "s_o_u_r_c_e__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".py\" }") }, .{ "e_x_t_e_n_s_i_o_n__s_u_f_f_i_x_e_s", h.c("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }") },
});

fn genSourceFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; const path = "); try self.genExpr(args[1]); try self.emit("; break :blk .{ .name = name, .path = path }; }"); }
    else try self.emit(".{ .name = \"\", .path = \"\" }");
}
