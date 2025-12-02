/// Python platform module - Access to underlying platform's identifying data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "system", genSystem }, .{ "machine", genMachine }, .{ "node", genNode }, .{ "release", genEmptyStr },
    .{ "version", genEmptyStr }, .{ "platform", genPlatform }, .{ "processor", genMachine },
    .{ "python_implementation", genImpl }, .{ "python_version", genPyVer }, .{ "python_version_tuple", genPyVerTup },
    .{ "python_branch", genEmptyStr }, .{ "python_revision", genEmptyStr }, .{ "python_build", genBuild },
    .{ "python_compiler", genCompiler }, .{ "uname", genUname }, .{ "architecture", genArch },
    .{ "mac_ver", genMacVer }, .{ "win32_ver", genWin32Ver }, .{ "win32_edition", genEmptyStr },
    .{ "win32_is_iot", genFalse }, .{ "libc_ver", genLibcVer }, .{ "freedesktop_os_release", genOsRelease },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genNode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"localhost\""); }
fn genImpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"metal0\""); }
fn genPyVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"3.12.0\""); }
fn genPyVerTup(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"3\", \"12\", \"0\" }"); }
fn genBuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", \"\" }"); }
fn genCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Zig\""); }
fn genArch(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"64bit\", \"\" }"); }
fn genMacVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", .{ \"\", \"\", \"\" }, \"\" }"); }
fn genWin32Ver(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", \"\", \"\", \"\" }"); }
fn genLibcVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"glibc\", \"\" }"); }
fn genOsRelease(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"); }
fn genSystem(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@tagName(@import(\"builtin\").os.tag)"); }
fn genMachine(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@tagName(@import(\"builtin\").cpu.arch)"); }
fn genPlatform(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@tagName(@import(\"builtin\").os.tag) ++ \"-\" ++ @tagName(@import(\"builtin\").cpu.arch)"); }
fn genUname(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { system: []const u8 = @tagName(@import(\"builtin\").os.tag), node: []const u8 = \"localhost\", release: []const u8 = \"\", version: []const u8 = \"\", machine: []const u8 = @tagName(@import(\"builtin\").cpu.arch), processor: []const u8 = @tagName(@import(\"builtin\").cpu.arch) }{}"); }
