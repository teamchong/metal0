/// Python sysconfig module - Python configuration information
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "get_config_vars", genConst(".{ .prefix = \"/usr/local\", .exec_prefix = \"/usr/local\", .py_version = \"3.12\", .py_version_short = \"3.12\", .py_version_nodot = \"312\", .installed_base = \"/usr/local\", .installed_platbase = \"/usr/local\", .platbase = \"/usr/local\", .projectbase = \"/usr/local\", .abiflags = \"\", .SOABI = \"cpython-312\", .EXT_SUFFIX = \".so\" }") },
    .{ "get_config_var", genGetConfigVar },
    .{ "get_scheme_names", genConst("&[_][]const u8{ \"posix_home\", \"posix_prefix\", \"posix_user\", \"nt\", \"nt_user\", \"osx_framework_user\" }") },
    .{ "get_default_scheme", genConst("\"posix_prefix\"") }, .{ "get_preferred_scheme", genConst("\"posix_prefix\"") },
    .{ "get_path_names", genConst("&[_][]const u8{ \"stdlib\", \"platstdlib\", \"purelib\", \"platlib\", \"include\", \"platinclude\", \"scripts\", \"data\" }") },
    .{ "get_paths", genConst(".{ .stdlib = \"/usr/local/lib/python3.12\", .platstdlib = \"/usr/local/lib/python3.12\", .purelib = \"/usr/local/lib/python3.12/site-packages\", .platlib = \"/usr/local/lib/python3.12/site-packages\", .include = \"/usr/local/include/python3.12\", .platinclude = \"/usr/local/include/python3.12\", .scripts = \"/usr/local/bin\", .data = \"/usr/local\" }") },
    .{ "get_path", genGetPath },
    .{ "get_python_lib", genConst("\"/usr/local/lib/python3.12/site-packages\"") },
    .{ "get_platform", genConst("\"darwin-arm64\"") },
    .{ "get_makefile_filename", genConst("\"/usr/local/lib/python3.12/config-3.12/Makefile\"") },
    .{ "parse_config_h", genConst(".{}") }, .{ "is_python_build", genConst("false") },
});

fn genGetConfigVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; if (std.mem.eql(u8, name, \"prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"exec_prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"EXT_SUFFIX\")) break :blk \".so\" else break :blk null; }"); } else try self.emit("null");
}

fn genGetPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; if (std.mem.eql(u8, name, \"stdlib\")) break :blk \"/usr/local/lib/python3.12\" else if (std.mem.eql(u8, name, \"purelib\")) break :blk \"/usr/local/lib/python3.12/site-packages\" else if (std.mem.eql(u8, name, \"scripts\")) break :blk \"/usr/local/bin\" else break :blk null; }"); } else try self.emit("null");
}
