/// Python csv module - CSV file reading and writing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "reader", genReader },
    .{ "writer", genWriter },
    .{ "DictReader", genDictReader },
    .{ "DictWriter", genDictWriter },
    .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", genQuoteAll },
    .{ "QUOTE_MINIMAL", genQuoteMinimal },
    .{ "QUOTE_NONNUMERIC", genQuoteNonnumeric },
    .{ "QUOTE_NONE", genQuoteNone },
});

/// Generate csv.reader(csvfile, delimiter=',', quotechar='"') -> reader object
pub fn genReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("csv_reader_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _file = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _delim: u8 = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
        try self.emit("[0]");
    } else {
        try self.emit("','");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :csv_reader_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: []const u8,\n");
    try self.emitIndent();
    try self.emit("pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("delim: u8,\n");
    try self.emitIndent();
    try self.emit("pub fn next(self: *@This()) ?[][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.pos >= self.data.len) return null;\n");
    try self.emitIndent();
    try self.emit("var line_end = std.mem.indexOfScalarPos(u8, self.data, self.pos, '\\n') orelse self.data.len;\n");
    try self.emitIndent();
    try self.emit("const line = self.data[self.pos..line_end];\n");
    try self.emitIndent();
    try self.emit("self.pos = line_end + 1;\n");
    try self.emitIndent();
    try self.emit("var fields: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var iter = std.mem.splitScalar(u8, line, self.delim);\n");
    try self.emitIndent();
    try self.emit("while (iter.next()) |field| fields.append(__global_allocator, field) catch continue;\n");
    try self.emitIndent();
    try self.emit("return fields.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .data = _file, .delim = _delim };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate csv.writer(csvfile, delimiter=',', quotechar='"') -> writer object
pub fn genWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("csv_writer_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :csv_writer_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("buffer: std.ArrayList(u8),\n");
    try self.emitIndent();
    try self.emit("delim: u8 = ',',\n");
    try self.emitIndent();
    try self.emit("pub fn writerow(self: *@This(), row: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var first = true;\n");
    try self.emitIndent();
    try self.emit("for (row) |field| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!first) self.buffer.append(__global_allocator, self.delim) catch {};\n");
    try self.emitIndent();
    try self.emit("first = false;\n");
    try self.emitIndent();
    try self.emit("self.buffer.appendSlice(__global_allocator, field) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("self.buffer.append(__global_allocator, '\\n') catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn writerows(self: *@This(), rows: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("for (rows) |row| self.writerow(row);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn getvalue(self: *@This()) []const u8 { return self.buffer.items; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .buffer = .{} };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate csv.DictReader(f, fieldnames=None, restkey=None, restval=None) -> DictReader
pub fn genDictReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("csv_dictreader_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _file = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :csv_dictreader_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: []const u8,\n");
    try self.emitIndent();
    try self.emit("pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("fieldnames: ?[][]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("pub fn next(self: *@This()) ?hashmap_helper.StringHashMap([]const u8) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.pos >= self.data.len) return null;\n");
    try self.emitIndent();
    try self.emit("var line_end = std.mem.indexOfScalarPos(u8, self.data, self.pos, '\\n') orelse self.data.len;\n");
    try self.emitIndent();
    try self.emit("const line = self.data[self.pos..line_end];\n");
    try self.emitIndent();
    try self.emit("self.pos = line_end + 1;\n");
    try self.emitIndent();
    try self.emit("if (self.fieldnames == null) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var headers: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var iter = std.mem.splitScalar(u8, line, ',');\n");
    try self.emitIndent();
    try self.emit("while (iter.next()) |h| headers.append(__global_allocator, h) catch continue;\n");
    try self.emitIndent();
    try self.emit("self.fieldnames = headers.items;\n");
    try self.emitIndent();
    try self.emit("return self.next();\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("var result = hashmap_helper.StringHashMap([]const u8).init(__global_allocator);\n");
    try self.emitIndent();
    try self.emit("var iter = std.mem.splitScalar(u8, line, ',');\n");
    try self.emitIndent();
    try self.emit("var i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (iter.next()) |val| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (i < self.fieldnames.?.len) result.put(self.fieldnames.?[i], val) catch {};\n");
    try self.emitIndent();
    try self.emit("i += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("return result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .data = _file };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate csv.DictWriter(f, fieldnames) -> DictWriter
pub fn genDictWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("csv_dictwriter_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fieldnames = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :csv_dictwriter_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("buffer: std.ArrayList(u8),\n");
    try self.emitIndent();
    try self.emit("fieldnames: [][]const u8,\n");
    try self.emitIndent();
    try self.emit("pub fn writeheader(self: *@This()) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var first = true;\n");
    try self.emitIndent();
    try self.emit("for (self.fieldnames) |name| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!first) self.buffer.append(__global_allocator, ',') catch {};\n");
    try self.emitIndent();
    try self.emit("first = false;\n");
    try self.emitIndent();
    try self.emit("self.buffer.appendSlice(__global_allocator, name) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("self.buffer.append(__global_allocator, '\\n') catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn writerow(self: *@This(), row: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var first = true;\n");
    try self.emitIndent();
    try self.emit("for (self.fieldnames) |name| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!first) self.buffer.append(__global_allocator, ',') catch {};\n");
    try self.emitIndent();
    try self.emit("first = false;\n");
    try self.emitIndent();
    try self.emit("if (row.get(name)) |val| self.buffer.appendSlice(__global_allocator, val) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("self.buffer.append(__global_allocator, '\\n') catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn getvalue(self: *@This()) []const u8 { return self.buffer.items; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .buffer = .{}, .fieldnames = _fieldnames };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate csv.field_size_limit(new_limit=None) -> int
pub fn genFieldSizeLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Default field size limit is 128KB
    try self.emit("@as(i64, 131072)");
}

/// Generate csv.QUOTE_ALL constant
pub fn genQuoteAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate csv.QUOTE_MINIMAL constant
pub fn genQuoteMinimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate csv.QUOTE_NONNUMERIC constant
pub fn genQuoteNonnumeric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}

/// Generate csv.QUOTE_NONE constant
pub fn genQuoteNone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 3)");
}
