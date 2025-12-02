/// Python _imp module - Internal import machinery support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "lock_held", genFalse }, .{ "acquire_lock", genUnit }, .{ "release_lock", genUnit },
    .{ "get_frozen_object", genNull }, .{ "is_frozen", genFalse }, .{ "is_builtin", genI32_0 },
    .{ "is_frozen_package", genFalse }, .{ "create_builtin", genNull }, .{ "create_dynamic", genNull },
    .{ "exec_builtin", genI32_0 }, .{ "exec_dynamic", genI32_0 }, .{ "extension_suffixes", genExtSuffix },
    .{ "source_hash", genSrcHash }, .{ "check_hash_based_pycs", genDefault },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genExtSuffix(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }"); }
fn genSrcHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\" ** 8"); }
fn genDefault(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"default\""); }
