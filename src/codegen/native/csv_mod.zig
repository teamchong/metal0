/// Python csv module - CSV file reading and writing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
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

fn genWriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { buffer: std.ArrayList(u8), delim: u8 = ',', pub fn writerow(s: *@This(), r: anytype) void { var _first = true; for (r) |x| { if (!_first) s.buffer.append(__global_allocator, s.delim) catch unreachable; _first = false; s.buffer.appendSlice(__global_allocator, x) catch unreachable; } s.buffer.append(__global_allocator, '\\n') catch unreachable; } pub fn writerows(s: *@This(), rs: anytype) void { for (rs) |_r| s.writerow(_r); } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{} }"), builder_mod.EmitConfig.forExpression());
}

fn genReader(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("rd", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _f = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; const _d: u8 = ','; const _str = if (@TypeOf(_f) == *runtime.io.StringIO) _f.getvalue() else _f; break :{s} struct {{ data: []const u8, pos: usize = 0, delim: u8, pub fn next(s: *@This()) ?[][]const u8 {{ if (s.pos >= s.data.len) return null; const le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; var fs: std.ArrayList([]const u8) = .{{}}; var it = std.mem.splitScalar(u8, ln, s.delim); while (it.next()) |f| fs.append(__global_allocator, f) catch continue; return fs.items; }} }}{{ .data = _str, .delim = _d }}; ", .{label});
        }
    }.emit);
}

fn genDictReader(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("dr", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _f = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} struct {{ data: []const u8, pos: usize = 0, fieldnames: ?[][]const u8 = null, pub fn next(s: *@This()) ?hashmap_helper.StringHashMap([]const u8) {{ if (s.pos >= s.data.len) return null; const le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; if (s.fieldnames == null) {{ var hs: std.ArrayList([]const u8) = .{{}}; var it = std.mem.splitScalar(u8, ln, ','); while (it.next()) |fh| hs.append(__global_allocator, fh) catch continue; s.fieldnames = hs.items; return s.next(); }} var r = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var it = std.mem.splitScalar(u8, ln, ','); var i: usize = 0; while (it.next()) |v| {{ if (i < s.fieldnames.?.len) r.put(s.fieldnames.?[i], v) catch unreachable; i += 1; }} return r; }} }}{{ .data = _f }}; ", .{label});
        }
    }.emit);
}

fn genDictWriter(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("dw", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _fn = ");
            try c.genExpr(a[1]);
            try emitFmtConst(c, "; break :{s} struct {{ buffer: std.ArrayList(u8), fieldnames: [][]const u8, pub fn writeheader(s: *@This()) void {{ var _first = true; for (s.fieldnames) |n| {{ if (!_first) s.buffer.append(__global_allocator, ',') catch unreachable; _first = false; s.buffer.appendSlice(__global_allocator, n) catch unreachable; }} s.buffer.append(__global_allocator, '\\n') catch unreachable; }} pub fn writerow(s: *@This(), _row: anytype) void {{ var _first = true; for (s.fieldnames) |n| {{ if (!_first) s.buffer.append(__global_allocator, ',') catch unreachable; _first = false; if (_row.get(n)) |v| s.buffer.appendSlice(__global_allocator, v) catch unreachable; }} s.buffer.append(__global_allocator, '\\n') catch unreachable; }} pub fn getvalue(s: *@This()) []const u8 {{ return s.buffer.items; }} }}{{ .buffer = .{{}}, .fieldnames = _fn }}; ", .{label});
        }
    }.emit);
}

fn genFieldSizeLimit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(131072), builder_mod.EmitConfig.forExpression());
}

fn genQuoteAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genQuoteMinimal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genQuoteNonnumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genQuoteNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}
