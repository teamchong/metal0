/// Python pipes module - Interface to shell pipelines (deprecated in 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .steps = &[_][]const u8{}, .debugging = false }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Template", genTemplate }, .{ "reset", genUnit }, .{ "clone", genTemplate }, .{ "debug", genUnit },
    .{ "append", genUnit }, .{ "prepend", genUnit }, .{ "open", genNull }, .{ "copy", genUnit },
    .{ "FILEIN_FILEOUT", genFF }, .{ "STDIN_FILEOUT", genMF }, .{ "FILEIN_STDOUT", genFM }, .{ "STDIN_STDOUT", genMM },
    .{ "quote", genQuote },
});

fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ff\""); }
fn genMF(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"-f\""); }
fn genFM(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"f-\""); }
fn genMM(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"--\""); }
fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; _ = s; break :blk \"''\"; }"); } else try self.emit("\"''\""); }
