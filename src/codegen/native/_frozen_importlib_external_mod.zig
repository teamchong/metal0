/// Python _frozen_importlib_external module - External frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "source_file_loader", genSourceFileLoader }, .{ "sourceless_file_loader", genConst(".{ .name = \"\", .path = \"\" }") }, .{ "extension_file_loader", genConst(".{ .name = \"\", .path = \"\" }") },
    .{ "file_finder", genConst(".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }") }, .{ "path_finder", genConst(".{}") }, .{ "get_supported_file_loaders", genConst("&[_]@TypeOf(.{}){}") },
    .{ "install", genConst("{}") }, .{ "cache_from_source", genPassthrough }, .{ "source_from_cache", genPassthrough },
    .{ "spec_from_file_location", genConst(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }") },
    .{ "b_y_t_e_c_o_d_e__s_u_f_f_i_x_e_s", genConst("&[_][]const u8{ \".pyc\" }") }, .{ "s_o_u_r_c_e__s_u_f_f_i_x_e_s", genConst("&[_][]const u8{ \".py\" }") }, .{ "e_x_t_e_n_s_i_o_n__s_u_f_f_i_x_e_s", genConst("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }") },
});

fn genSourceFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; const path = "); try self.genExpr(args[1]); try self.emit("; break :blk .{ .name = name, .path = path }; }"); }
    else try self.emit(".{ .name = \"\", .path = \"\" }");
}
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = path; break :blk path; }"); } else try self.emit("\"\""); }
