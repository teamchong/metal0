/// Python csv module - CSV file reading and writing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", genReader },
    .{ "writer", genWriter },
    .{ "DictReader", genDictReader },
    .{ "DictWriter", genDictWriter },
    .{ "field_size_limit", h.I64(131072) }, .{ "QUOTE_ALL", h.I64(1) },
    .{ "QUOTE_MINIMAL", h.I64(0) }, .{ "QUOTE_NONNUMERIC", h.I64(2) },
    .{ "QUOTE_NONE", h.I64(3) },
});

const genWriter = h.c("struct { buffer: std.ArrayList(u8), delim: u8 = ',', pub fn writerow(s: *@This(), r: anytype) void { var _first = true; for (r) |x| { if (!_first) s.buffer.append(__global_allocator, s.delim) catch unreachable; _first = false; s.buffer.appendSlice(__global_allocator, x) catch unreachable; } s.buffer.append(__global_allocator, '\\n') catch unreachable; } pub fn writerows(s: *@This(), rs: anytype) void { for (rs) |_r| s.writerow(_r); } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{} }");

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_rd: {{ const _f = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _d: u8 = ','; const _str = if (@TypeOf(_f) == *runtime.io.StringIO) _f.getvalue() else _f; break :__m{d}_rd struct {{ data: []const u8, pos: usize = 0, delim: u8, pub fn next(s: *@This()) ?[][]const u8 {{ if (s.pos >= s.data.len) return null; const le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; var fs: std.ArrayList([]const u8) = .{{}}; var it = std.mem.splitScalar(u8, ln, s.delim); while (it.next()) |f| fs.append(__global_allocator, f) catch continue; return fs.items; }} }}{{ .data = _str, .delim = _d }}; }})", .{id});
}

fn genDictReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_dr: {{ const _f = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_dr struct {{ data: []const u8, pos: usize = 0, fieldnames: ?[][]const u8 = null, pub fn next(s: *@This()) ?hashmap_helper.StringHashMap([]const u8) {{ if (s.pos >= s.data.len) return null; const le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; if (s.fieldnames == null) {{ var hs: std.ArrayList([]const u8) = .{{}}; var it = std.mem.splitScalar(u8, ln, ','); while (it.next()) |fh| hs.append(__global_allocator, fh) catch continue; s.fieldnames = hs.items; return s.next(); }} var r = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var it = std.mem.splitScalar(u8, ln, ','); var i: usize = 0; while (it.next()) |v| {{ if (i < s.fieldnames.?.len) r.put(s.fieldnames.?[i], v) catch unreachable; i += 1; }} return r; }} }}{{ .data = _f }}; }})", .{id});
}

fn genDictWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("void{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_dw: {{ const _fn = ", .{id}); try self.genExpr(args[1]);
    try self.emitFmt("; break :__m{d}_dw struct {{ buffer: std.ArrayList(u8), fieldnames: [][]const u8, pub fn writeheader(s: *@This()) void {{ var _first = true; for (s.fieldnames) |n| {{ if (!_first) s.buffer.append(__global_allocator, ',') catch unreachable; _first = false; s.buffer.appendSlice(__global_allocator, n) catch unreachable; }} s.buffer.append(__global_allocator, '\\n') catch unreachable; }} pub fn writerow(s: *@This(), _row: anytype) void {{ var _first = true; for (s.fieldnames) |n| {{ if (!_first) s.buffer.append(__global_allocator, ',') catch unreachable; _first = false; if (_row.get(n)) |v| s.buffer.appendSlice(__global_allocator, v) catch unreachable; }} s.buffer.append(__global_allocator, '\\n') catch unreachable; }} pub fn getvalue(s: *@This()) []const u8 {{ return s.buffer.items; }} }}{{ .buffer = .{{}}, .fieldnames = _fn }}; }})", .{id});
}
