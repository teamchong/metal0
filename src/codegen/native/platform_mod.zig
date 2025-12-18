/// Python platform module - Access to underlying platform's identifying data
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
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

fn genSystem(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@tagName(@import(\"builtin\").os.tag)"), builder_mod.EmitConfig.forExpression());
}

fn genMachine(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@tagName(@import(\"builtin\").cpu.arch)"), builder_mod.EmitConfig.forExpression());
}

fn genNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("localhost"), builder_mod.EmitConfig.forExpression());
}

fn genRelease(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genPlatform(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@tagName(@import(\"builtin\").os.tag) ++ \"-\" ++ @tagName(@import(\"builtin\").cpu.arch)"), builder_mod.EmitConfig.forExpression());
}

fn genProcessor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@tagName(@import(\"builtin\").cpu.arch)"), builder_mod.EmitConfig.forExpression());
}

fn genPythonImplementation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("metal0"), builder_mod.EmitConfig.forExpression());
}

fn genPythonVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("3.12.0"), builder_mod.EmitConfig.forExpression());
}

fn genPythonVersionTuple(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"3\", \"12\", \"0\" }"), builder_mod.EmitConfig.forExpression());
}

fn genPythonBranch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genPythonRevision(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genPythonBuild(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genPythonCompiler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Zig"), builder_mod.EmitConfig.forExpression());
}

fn genUname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { system: []const u8 = @tagName(@import(\"builtin\").os.tag), node: []const u8 = \"localhost\", release: []const u8 = \"\", version: []const u8 = \"\", machine: []const u8 = @tagName(@import(\"builtin\").cpu.arch), processor: []const u8 = @tagName(@import(\"builtin\").cpu.arch) }{}"), builder_mod.EmitConfig.forExpression());
}

fn genArchitecture(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"64bit\", \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genMacVer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", .{ \"\", \"\", \"\" }, \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genWin32Ver(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", \"\", \"\", \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genWin32Edition(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genWin32IsIot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genLibcVer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"glibc\", \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFreedesktopOsRelease(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}
