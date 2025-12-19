/// Python _csv module - C accelerator for csv (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", genRW },
    .{ "writer", genRW },
    .{ "register_dialect", genRegisterDialect },
    .{ "unregister_dialect", genUnregisterDialect },
    .{ "get_dialect", genGetDialect },
    .{ "list_dialects", genListDialects },
    .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", genQuoteAll },
    .{ "QUOTE_MINIMAL", genQuoteMinimal },
    .{ "QUOTE_NONNUMERIC", genQuoteNonnumeric },
    .{ "QUOTE_NONE", genQuoteNone },
    .{ "Error", genError },
});

fn genRW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, ".{ .file = null, .dialect = \"excel\" }");
        return;
    }
    try self.withInlineBlock("csv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const __v = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} .{{ .file = __v, .dialect = \"excel\" }}", .{label});
        }
    }.emit);
}

fn genRegisterDialect(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "{}");
}

fn genUnregisterDialect(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "{}");
}

fn genGetDialect(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }");
}

fn genListDialects(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }");
}

fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try emitConst(self, "@as(i64, 131072)");
    }
}

fn genQuoteAll(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "1");
}

fn genQuoteMinimal(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "0");
}

fn genQuoteNonnumeric(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "2");
}

fn genQuoteNone(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "3");
}

fn genError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "error.CsvError");
}
