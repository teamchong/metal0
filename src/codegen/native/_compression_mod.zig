/// Python _compression module - Internal compression support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genUsize_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 0)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "DecompressReader", genDecompressReader }, .{ "BaseStream", genEmpty },
    .{ "readable", genTrue }, .{ "writable", genFalse }, .{ "seekable", genTrue },
    .{ "read", genEmptyStr }, .{ "read1", genEmptyStr }, .{ "readline", genEmptyStr },
    .{ "readlines", genReadlines }, .{ "readinto", genUsize_0 },
    .{ "seek", genI64_0 }, .{ "tell", genI64_0 }, .{ "close", genUnit },
});

fn genDecompressReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .fp = null, .decomp = null, .eof = false, .pos = 0, .size = -1 }"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genReadlines(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
