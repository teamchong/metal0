/// Python sysconfig module - Python configuration information
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_config_vars", h.c(".{ .prefix = \"/usr/local\", .exec_prefix = \"/usr/local\", .py_version = \"3.12\", .py_version_short = \"3.12\", .py_version_nodot = \"312\", .installed_base = \"/usr/local\", .installed_platbase = \"/usr/local\", .platbase = \"/usr/local\", .projectbase = \"/usr/local\", .abiflags = \"\", .SOABI = \"cpython-312\", .EXT_SUFFIX = \".so\" }") },
    .{ "get_config_var", genGetConfigVar },
    .{ "get_scheme_names", h.c("&[_][]const u8{ \"posix_home\", \"posix_prefix\", \"posix_user\", \"nt\", \"nt_user\", \"osx_framework_user\" }") },
    .{ "get_default_scheme", h.c("\"posix_prefix\"") }, .{ "get_preferred_scheme", h.c("\"posix_prefix\"") },
    .{ "get_path_names", h.c("&[_][]const u8{ \"stdlib\", \"platstdlib\", \"purelib\", \"platlib\", \"include\", \"platinclude\", \"scripts\", \"data\" }") },
    .{ "get_paths", h.c(".{ .stdlib = \"/usr/local/lib/python3.12\", .platstdlib = \"/usr/local/lib/python3.12\", .purelib = \"/usr/local/lib/python3.12/site-packages\", .platlib = \"/usr/local/lib/python3.12/site-packages\", .include = \"/usr/local/include/python3.12\", .platinclude = \"/usr/local/include/python3.12\", .scripts = \"/usr/local/bin\", .data = \"/usr/local\" }") },
    .{ "get_path", genGetPath },
    .{ "get_python_lib", h.c("\"/usr/local/lib/python3.12/site-packages\"") },
    .{ "get_platform", h.c("\"darwin-arm64\"") },
    .{ "get_makefile_filename", h.c("\"/usr/local/lib/python3.12/config-3.12/Makefile\"") },
    .{ "parse_config_h", h.c(".{}") }, .{ "is_python_build", h.c("false") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genGetConfigVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("gcv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const name = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; if (std.mem.eql(u8, name, \"prefix\")) break :{s} \"/usr/local\" else if (std.mem.eql(u8, name, \"exec_prefix\")) break :{s} \"/usr/local\" else if (std.mem.eql(u8, name, \"EXT_SUFFIX\")) break :{s} \".so\" else break :{s} null", .{ label, label, label, label });
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genGetPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("gp", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const name = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; if (std.mem.eql(u8, name, \"stdlib\")) break :{s} \"/usr/local/lib/python3.12\" else if (std.mem.eql(u8, name, \"purelib\")) break :{s} \"/usr/local/lib/python3.12/site-packages\" else if (std.mem.eql(u8, name, \"scripts\")) break :{s} \"/usr/local/bin\" else break :{s} null", .{ label, label, label, label });
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}
