/// Python platform module - Access to underlying platform's identifying data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "system", genSystem },
    .{ "machine", genMachine },
    .{ "node", genNode },
    .{ "release", genRelease },
    .{ "version", genVersion },
    .{ "platform", genPlatform },
    .{ "processor", genProcessor },
    .{ "python_implementation", genPythonImplementation },
    .{ "python_version", genPythonVersion },
    .{ "python_version_tuple", genPythonVersionTuple },
    .{ "python_branch", genPythonBranch },
    .{ "python_revision", genPythonRevision },
    .{ "python_build", genPythonBuild },
    .{ "python_compiler", genPythonCompiler },
    .{ "uname", genUname },
    .{ "architecture", genArchitecture },
    .{ "mac_ver", genMacVer },
    .{ "win32_ver", genWin32Ver },
    .{ "win32_edition", genWin32Edition },
    .{ "win32_is_iot", genWin32IsIot },
    .{ "libc_ver", genLibcVer },
    .{ "freedesktop_os_release", genFreedesktopOsRelease },
});

/// Generate platform.system() -> str
pub fn genSystem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@tagName(@import(\"builtin\").os.tag)");
}

/// Generate platform.machine() -> str
pub fn genMachine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@tagName(@import(\"builtin\").cpu.arch)");
}

/// Generate platform.node() -> str
pub fn genNode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"localhost\"");
}

/// Generate platform.release() -> str
pub fn genRelease(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate platform.version() -> str
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate platform.platform(aliased=False, terse=False) -> str
pub fn genPlatform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@tagName(@import(\"builtin\").os.tag) ++ \"-\" ++ @tagName(@import(\"builtin\").cpu.arch)");
}

/// Generate platform.processor() -> str
pub fn genProcessor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMachine(self, args);
}

/// Generate platform.python_implementation() -> str
pub fn genPythonImplementation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"metal0\"");
}

/// Generate platform.python_version() -> str
pub fn genPythonVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"3.12.0\"");
}

/// Generate platform.python_version_tuple() -> tuple
pub fn genPythonVersionTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"3\", \"12\", \"0\" }");
}

/// Generate platform.python_branch() -> str
pub fn genPythonBranch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate platform.python_revision() -> str
pub fn genPythonRevision(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate platform.python_build() -> tuple
pub fn genPythonBuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", \"\" }");
}

/// Generate platform.python_compiler() -> str
pub fn genPythonCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Zig\"");
}

/// Generate platform.uname() -> uname_result
pub fn genUname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("system: []const u8 = @tagName(@import(\"builtin\").os.tag),\n");
    try self.emitIndent();
    try self.emit("node: []const u8 = \"localhost\",\n");
    try self.emitIndent();
    try self.emit("release: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("version: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("machine: []const u8 = @tagName(@import(\"builtin\").cpu.arch),\n");
    try self.emitIndent();
    try self.emit("processor: []const u8 = @tagName(@import(\"builtin\").cpu.arch),\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate platform.architecture(executable=sys.executable, bits='', linkage='') -> tuple
pub fn genArchitecture(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"64bit\", \"\" }");
}

/// Generate platform.mac_ver(release='', versioninfo=('', '', ''), machine='') -> tuple
pub fn genMacVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", .{ \"\", \"\", \"\" }, \"\" }");
}

/// Generate platform.win32_ver(release='', version='', csd='', ptype='') -> tuple
pub fn genWin32Ver(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", \"\", \"\", \"\" }");
}

/// Generate platform.win32_edition() -> str
pub fn genWin32Edition(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate platform.win32_is_iot() -> bool
pub fn genWin32IsIot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate platform.libc_ver(executable=None, lib='', version='', chunksize=16384) -> tuple
pub fn genLibcVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"glibc\", \"\" }");
}

/// Generate platform.freedesktop_os_release() -> dict
pub fn genFreedesktopOsRelease(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)");
}
