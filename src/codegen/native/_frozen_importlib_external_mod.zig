/// Python _frozen_importlib_external module - External frozen import machinery
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "source_file_loader", genSourceFileLoader },
    .{ "sourceless_file_loader", genSourcelessFileLoader },
    .{ "extension_file_loader", genExtensionFileLoader },
    .{ "file_finder", genFileFinder },
    .{ "path_finder", genPathFinder },
    .{ "get_supported_file_loaders", genGetSupportedFileLoaders },
    .{ "install", genInstall },
    .{ "cache_from_source", genCacheFromSource },
    .{ "source_from_cache", genSourceFromCache },
    .{ "spec_from_file_location", genSpecFromFileLocation },
    .{ "b_y_t_e_c_o_d_e__s_u_f_f_i_x_e_s", genBytecodeSuffixes },
    .{ "s_o_u_r_c_e__s_u_f_f_i_x_e_s", genSourceSuffixes },
    .{ "e_x_t_e_n_s_i_o_n__s_u_f_f_i_x_e_s", genExtensionSuffixes },
});

fn genSourceFileLoader(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("sfl", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; break :{s} .{{ .name = __v0, .path = __v1 }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .path = \"\" }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genSourcelessFileLoader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .path = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genExtensionFileLoader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .path = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFileFinder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }"), builder_mod.EmitConfig.forExpression());
}

fn genPathFinder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetSupportedFileLoaders(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genInstall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCacheFromSource(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genSourceFromCache(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genSpecFromFileLocation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }"), builder_mod.EmitConfig.forExpression());
}

fn genBytecodeSuffixes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \".pyc\" }"), builder_mod.EmitConfig.forExpression());
}

fn genSourceSuffixes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \".py\" }"), builder_mod.EmitConfig.forExpression());
}

fn genExtensionSuffixes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }"), builder_mod.EmitConfig.forExpression());
}
