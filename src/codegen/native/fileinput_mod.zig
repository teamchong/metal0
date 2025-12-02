/// Python fileinput module - Iterate over lines from multiple input streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genI32_m1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "input", genInput }, .{ "filename", genEmptyStr }, .{ "fileno", genI32_m1 },
    .{ "lineno", genI64_0 }, .{ "filelineno", genI64_0 },
    .{ "isfirstline", genFalse }, .{ "isstdin", genFalse }, .{ "nextfile", genUnit }, .{ "close", genUnit },
    .{ "FileInput", genFileInput }, .{ "hook_compressed", genNull }, .{ "hook_encoded", genNull },
});

fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\" }"); }
fn genFileInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\", .encoding = null, .errors = null }"); }
