/// Python _opcode module - Internal opcode support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "stack_effect", genI32_0 }, .{ "is_valid", genTrue }, .{ "has_arg", genTrue },
    .{ "has_const", genFalse }, .{ "has_name", genFalse }, .{ "has_jump", genFalse },
    .{ "has_free", genFalse }, .{ "has_local", genFalse }, .{ "has_exc", genFalse },
});
