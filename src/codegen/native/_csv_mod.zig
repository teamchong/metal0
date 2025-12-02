/// Python _csv module - C accelerator for csv (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", genReaderWriter }, .{ "writer", genReaderWriter },
    .{ "register_dialect", h.c("{}") }, .{ "unregister_dialect", h.c("{}") },
    .{ "get_dialect", h.c(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }") },
    .{ "list_dialects", h.c("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }") }, .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", h.I32(1) }, .{ "QUOTE_MINIMAL", h.I32(0) }, .{ "QUOTE_NONNUMERIC", h.I32(2) }, .{ "QUOTE_NONE", h.I32(3) },
    .{ "Error", h.err("CsvError") },
});

fn genReaderWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const csvfile = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }"); } else try self.emit(".{ .file = null, .dialect = \"excel\" }"); }
fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(i64, 131072)"); }
