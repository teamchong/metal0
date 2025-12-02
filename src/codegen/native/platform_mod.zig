/// Python platform module - Access to underlying platform's identifying data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "system", genConst("@tagName(@import(\"builtin\").os.tag)") },
    .{ "machine", genConst("@tagName(@import(\"builtin\").cpu.arch)") },
    .{ "node", genConst("\"localhost\"") },
    .{ "release", genConst("\"\"") }, .{ "version", genConst("\"\"") },
    .{ "platform", genConst("@tagName(@import(\"builtin\").os.tag) ++ \"-\" ++ @tagName(@import(\"builtin\").cpu.arch)") },
    .{ "processor", genConst("@tagName(@import(\"builtin\").cpu.arch)") },
    .{ "python_implementation", genConst("\"metal0\"") },
    .{ "python_version", genConst("\"3.12.0\"") },
    .{ "python_version_tuple", genConst(".{ \"3\", \"12\", \"0\" }") },
    .{ "python_branch", genConst("\"\"") }, .{ "python_revision", genConst("\"\"") },
    .{ "python_build", genConst(".{ \"\", \"\" }") },
    .{ "python_compiler", genConst("\"Zig\"") },
    .{ "uname", genConst("struct { system: []const u8 = @tagName(@import(\"builtin\").os.tag), node: []const u8 = \"localhost\", release: []const u8 = \"\", version: []const u8 = \"\", machine: []const u8 = @tagName(@import(\"builtin\").cpu.arch), processor: []const u8 = @tagName(@import(\"builtin\").cpu.arch) }{}") },
    .{ "architecture", genConst(".{ \"64bit\", \"\" }") },
    .{ "mac_ver", genConst(".{ \"\", .{ \"\", \"\", \"\" }, \"\" }") },
    .{ "win32_ver", genConst(".{ \"\", \"\", \"\", \"\" }") },
    .{ "win32_edition", genConst("\"\"") }, .{ "win32_is_iot", genConst("false") },
    .{ "libc_ver", genConst(".{ \"glibc\", \"\" }") },
    .{ "freedesktop_os_release", genConst("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
});
