/// Python _csv module - C accelerator for csv (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

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

fn genRW(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write(".{ .file = null, .dialect = \"excel\" }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("csv", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const __v = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; break :{s} .{{ .file = __v, .dialect = \"excel\" }}", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genRegisterDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genUnregisterDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genListDialects(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genFieldSizeLimit(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        const b = try self.getBuilder();
        try b.write("@as(i64, 131072)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genQuoteAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("1");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genQuoteMinimal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("0");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genQuoteNonnumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("2");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genQuoteNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("3");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("error.CsvError");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
