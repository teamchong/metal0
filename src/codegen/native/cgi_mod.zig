/// Python cgi module - CGI utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genEmpty }, .{ "parse_qs", genEmpty }, .{ "parse_multipart", genEmpty },
    .{ "parse_qsl", genParseQsl }, .{ "parse_header", genParseHeader },
    .{ "test", genUnit }, .{ "print_environ", genUnit }, .{ "print_form", genUnit },
    .{ "print_directory", genUnit }, .{ "print_environ_usage", genUnit },
    .{ "escape", genEscape }, .{ "FieldStorage", genFieldStorage }, .{ "MiniFieldStorage", genMiniFieldStorage },
    .{ "maxlen", genMaxlen },
});

fn genParseQsl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_].{ []const u8, []const u8 }{}"); }
fn genParseHeader(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", .{} }"); }
fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
fn genFieldStorage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = @as(?[]const u8, null), .filename = @as(?[]const u8, null), .value = @as(?[]const u8, null), .file = @as(?*anyopaque, null), .type = \"text/plain\", .type_options = .{}, .disposition = @as(?[]const u8, null), .disposition_options = .{}, .headers = .{}, .list = @as(?*anyopaque, null) }"); }
fn genMiniFieldStorage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = @as(?[]const u8, null), .value = @as(?[]const u8, null) }"); }
fn genMaxlen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
