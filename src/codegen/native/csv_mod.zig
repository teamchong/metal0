/// Python csv module - CSV file reading and writing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "reader", genReader }, .{ "writer", genWriter }, .{ "DictReader", genDictReader }, .{ "DictWriter", genDictWriter },
    .{ "field_size_limit", genConst("@as(i64, 131072)") }, .{ "QUOTE_ALL", genConst("@as(i64, 1)") },
    .{ "QUOTE_MINIMAL", genConst("@as(i64, 0)") }, .{ "QUOTE_NONNUMERIC", genConst("@as(i64, 2)") },
    .{ "QUOTE_NONE", genConst("@as(i64, 3)") },
});

pub fn genReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _f = "); try self.genExpr(args[0]); try self.emit("; const _d: u8 = ");
    if (args.len > 1) { try self.genExpr(args[1]); try self.emit("[0]"); } else try self.emit("','");
    try self.emit(";\n"); try self.emitIndent();
    try self.emit("break :blk struct { data: []const u8, pos: usize = 0, delim: u8, pub fn next(s: *@This()) ?[][]const u8 { if (s.pos >= s.data.len) return null; var le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; var fs: std.ArrayList([]const u8) = .{}; var it = std.mem.splitScalar(u8, ln, s.delim); while (it.next()) |f| fs.append(__global_allocator, f) catch continue; return fs.items; } }{ .data = _f, .delim = _d }; }");
}

pub fn genWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { buffer: std.ArrayList(u8), delim: u8 = ',', pub fn writerow(s: *@This(), r: anytype) void { var f = true; for (r) |x| { if (!f) s.buffer.append(__global_allocator, s.delim) catch {}; f = false; s.buffer.appendSlice(__global_allocator, x) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn writerows(s: *@This(), rs: anytype) void { for (rs) |r| s.writerow(r); } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{} }");
}

pub fn genDictReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _f = "); try self.genExpr(args[0]); try self.emit(";\n"); try self.emitIndent();
    try self.emit("break :blk struct { data: []const u8, pos: usize = 0, fieldnames: ?[][]const u8 = null, pub fn next(s: *@This()) ?hashmap_helper.StringHashMap([]const u8) { if (s.pos >= s.data.len) return null; var le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; if (s.fieldnames == null) { var hs: std.ArrayList([]const u8) = .{}; var it = std.mem.splitScalar(u8, ln, ','); while (it.next()) |h| hs.append(__global_allocator, h) catch continue; s.fieldnames = hs.items; return s.next(); } var r = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var it = std.mem.splitScalar(u8, ln, ','); var i: usize = 0; while (it.next()) |v| { if (i < s.fieldnames.?.len) r.put(s.fieldnames.?[i], v) catch {}; i += 1; } return r; } }{ .data = _f }; }");
}

pub fn genDictWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _fn = "); try self.genExpr(args[1]); try self.emit(";\n"); try self.emitIndent();
    try self.emit("break :blk struct { buffer: std.ArrayList(u8), fieldnames: [][]const u8, pub fn writeheader(s: *@This()) void { var f = true; for (s.fieldnames) |n| { if (!f) s.buffer.append(__global_allocator, ',') catch {}; f = false; s.buffer.appendSlice(__global_allocator, n) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn writerow(s: *@This(), r: anytype) void { var f = true; for (s.fieldnames) |n| { if (!f) s.buffer.append(__global_allocator, ',') catch {}; f = false; if (r.get(n)) |v| s.buffer.appendSlice(__global_allocator, v) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{}, .fieldnames = _fn }; }");
}
