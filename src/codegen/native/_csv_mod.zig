/// Python _csv module - C accelerator for csv (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "reader", genReaderWriter }, .{ "writer", genReaderWriter },
    .{ "register_dialect", genUnit }, .{ "unregister_dialect", genUnit },
    .{ "get_dialect", genGetDialect }, .{ "list_dialects", genListDialects }, .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", genI32(1) }, .{ "QUOTE_MINIMAL", genI32(0) }, .{ "QUOTE_NONNUMERIC", genI32(2) }, .{ "QUOTE_NONE", genI32(3) },
    .{ "Error", genError },
});

fn genReaderWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const csvfile = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }"); } else try self.emit(".{ .file = null, .dialect = \"excel\" }"); }
fn genGetDialect(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }"); }
fn genListDialects(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }"); }
fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(i64, 131072)"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.CsvError"); }
