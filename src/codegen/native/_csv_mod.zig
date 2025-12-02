/// Python _csv module - C accelerator for csv (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "reader", genReaderWriter }, .{ "writer", genReaderWriter },
    .{ "register_dialect", genConst("{}") }, .{ "unregister_dialect", genConst("{}") },
    .{ "get_dialect", genConst(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }") },
    .{ "list_dialects", genConst("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }") }, .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", genConst("@as(i32, 1)") }, .{ "QUOTE_MINIMAL", genConst("@as(i32, 0)") }, .{ "QUOTE_NONNUMERIC", genConst("@as(i32, 2)") }, .{ "QUOTE_NONE", genConst("@as(i32, 3)") },
    .{ "Error", genConst("error.CsvError") },
});

fn genReaderWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const csvfile = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }"); } else try self.emit(".{ .file = null, .dialect = \"excel\" }"); }
fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(i64, 131072)"); }
