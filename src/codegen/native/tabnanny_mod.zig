/// Python tabnanny module - Detection of ambiguous indentation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "check", genUnit }, .{ "process_tokens", genUnit }, .{ "NannyNag", genError }, .{ "verbose", genI32_0 }, .{ "filename_only", genI32_0 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NannyNag"); }
