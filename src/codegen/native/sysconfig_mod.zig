/// Python sysconfig module - Python configuration information
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sysconfig.get_config_vars(*args)
pub fn genGetConfigVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prefix = \"/usr/local\", .exec_prefix = \"/usr/local\", .py_version = \"3.12\", .py_version_short = \"3.12\", .py_version_nodot = \"312\", .installed_base = \"/usr/local\", .installed_platbase = \"/usr/local\", .platbase = \"/usr/local\", .projectbase = \"/usr/local\", .abiflags = \"\", .SOABI = \"cpython-312\", .EXT_SUFFIX = \".so\" }");
}

/// Generate sysconfig.get_config_var(name)
pub fn genGetConfigVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; if (std.mem.eql(u8, name, \"prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"exec_prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"EXT_SUFFIX\")) break :blk \".so\" else break :blk null; }");
    } else {
        try self.emit("null");
    }
}

/// Generate sysconfig.get_scheme_names()
pub fn genGetSchemeNames(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"posix_home\", \"posix_prefix\", \"posix_user\", \"nt\", \"nt_user\", \"osx_framework_user\" }");
}

/// Generate sysconfig.get_default_scheme()
pub fn genGetDefaultScheme(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"posix_prefix\"");
}

/// Generate sysconfig.get_preferred_scheme(key)
pub fn genGetPreferredScheme(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"posix_prefix\"");
}

/// Generate sysconfig.get_path_names()
pub fn genGetPathNames(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"stdlib\", \"platstdlib\", \"purelib\", \"platlib\", \"include\", \"platinclude\", \"scripts\", \"data\" }");
}

/// Generate sysconfig.get_paths(scheme=None, vars=None, expand=True)
pub fn genGetPaths(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .stdlib = \"/usr/local/lib/python3.12\", .platstdlib = \"/usr/local/lib/python3.12\", .purelib = \"/usr/local/lib/python3.12/site-packages\", .platlib = \"/usr/local/lib/python3.12/site-packages\", .include = \"/usr/local/include/python3.12\", .platinclude = \"/usr/local/include/python3.12\", .scripts = \"/usr/local/bin\", .data = \"/usr/local\" }");
}

/// Generate sysconfig.get_path(name, scheme=None, vars=None, expand=True)
pub fn genGetPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; if (std.mem.eql(u8, name, \"stdlib\")) break :blk \"/usr/local/lib/python3.12\" else if (std.mem.eql(u8, name, \"purelib\")) break :blk \"/usr/local/lib/python3.12/site-packages\" else if (std.mem.eql(u8, name, \"scripts\")) break :blk \"/usr/local/bin\" else break :blk null; }");
    } else {
        try self.emit("null");
    }
}

/// Generate sysconfig.get_python_lib(plat_specific=False, standard_lib=False, prefix=None)
pub fn genGetPythonLib(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr/local/lib/python3.12/site-packages\"");
}

/// Generate sysconfig.get_platform()
pub fn genGetPlatform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"darwin-arm64\"");
}

/// Generate sysconfig.get_makefile_filename()
pub fn genGetMakefileFilename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/usr/local/lib/python3.12/config-3.12/Makefile\"");
}

/// Generate sysconfig.parse_config_h(fp, vars=None)
pub fn genParseConfigH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate sysconfig.is_python_build(check_home=False)
pub fn genIsPythonBuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}
