/// Python _frozen_importlib_external module - External frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .path = \"\" }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "source_file_loader", genSourceFileLoader }, .{ "sourceless_file_loader", genEmptyLoader }, .{ "extension_file_loader", genEmptyLoader },
    .{ "file_finder", genFileFinder }, .{ "path_finder", genEmpty }, .{ "get_supported_file_loaders", genEmptyArray },
    .{ "install", genUnit }, .{ "cache_from_source", genPassthrough }, .{ "source_from_cache", genPassthrough },
    .{ "spec_from_file_location", genSpecFromFileLocation },
    .{ "b_y_t_e_c_o_d_e__s_u_f_f_i_x_e_s", genBytecodeSuffixes }, .{ "s_o_u_r_c_e__s_u_f_f_i_x_e_s", genSourceSuffixes }, .{ "e_x_t_e_n_s_i_o_n__s_u_f_f_i_x_e_s", genExtensionSuffixes },
});

fn genSourceFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; const path = "); try self.genExpr(args[1]); try self.emit("; break :blk .{ .name = name, .path = path }; }"); }
    else try genEmptyLoader(self, args);
}
fn genFileFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }"); }
fn genEmptyArray(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = path; break :blk path; }"); } else try self.emit("\"\""); }
fn genSpecFromFileLocation(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }"); }
fn genBytecodeSuffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \".pyc\" }"); }
fn genSourceSuffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \".py\" }"); }
fn genExtensionSuffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }"); }
