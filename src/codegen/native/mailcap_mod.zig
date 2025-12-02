/// Python mailcap module - Mailcap file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "findmatch", genNull }, .{ "getcaps", genEmpty }, .{ "listmailcapfiles", genStrArr }, .{ "readmailcapfile", genEmpty }, .{ "lookup", genLookup }, .{ "subst", genEmptyStr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(.{ \"\", .{} }), null)"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genStrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_].{ []const u8, .{} }{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
