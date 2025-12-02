/// Python pprint module - Pretty-print data structures
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "pprint", genPprint }, .{ "pformat", genPformat }, .{ "pp", genPprint },
    .{ "isreadable", genTrue }, .{ "isrecursive", genFalse }, .{ "saferepr", genPformat },
    .{ "PrettyPrinter", genPrettyPrinter },
});

fn genPprint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.emit("std.debug.print(\"{any}\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
}

fn genPformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("pformat_blk: { var buf: [4096]u8 = undefined; break :pformat_blk std.fmt.bufPrint(&buf, \"{any}\", .{"); try self.genExpr(args[0]); try self.emit("}) catch \"\"; }");
}

fn genPrettyPrinter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { indent: i64 = 1, width: i64 = 80, depth: ?i64 = null, compact: bool = false, sort_dicts: bool = true, underscore_numbers: bool = false, pub fn pprint(s: @This(), object: anytype) void { _ = s; std.debug.print(\"{any}\\n\", .{object}); } pub fn pformat(s: @This(), object: anytype) []const u8 { _ = s; _ = object; return \"\"; } pub fn isreadable(s: @This(), object: anytype) bool { _ = s; _ = object; return true; } pub fn isrecursive(s: @This(), object: anytype) bool { _ = s; _ = object; return false; } pub fn format(s: @This(), object: anytype) []const u8 { _ = s; _ = object; return \"\"; } }{}");
}
