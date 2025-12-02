/// Python plistlib module - Apple plist file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "load", genEmpty }, .{ "loads", genEmpty }, .{ "dump", genUnit }, .{ "dumps", genEmptyStr },
    .{ "UID", genUID }, .{ "FMT_XML", genFmtXml }, .{ "FMT_BINARY", genFmtBinary },
    .{ "Dict", genEmpty }, .{ "Data", genData }, .{ "InvalidFileException", genErr },
    .{ "readPlist", genEmpty }, .{ "writePlist", genUnit }, .{ "readPlistFromBytes", genEmpty }, .{ "writePlistToBytes", genEmptyStr },
});

fn genFmtXml(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genFmtBinary(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidFileException"); }

fn genUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .data = data }; }"); }
    else { try self.emit(".{ .data = @as(i64, 0) }"); }
}

fn genData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
