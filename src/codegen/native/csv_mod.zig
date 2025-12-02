/// Python csv module - CSV file reading and writing
const std = @import("std");
const h = @import("mod_helper.zig");

const readerBody = "; const _d: u8 = ',';\nbreak :blk struct { data: []const u8, pos: usize = 0, delim: u8, pub fn next(s: *@This()) ?[][]const u8 { if (s.pos >= s.data.len) return null; var le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; var fs: std.ArrayList([]const u8) = .{}; var it = std.mem.splitScalar(u8, ln, s.delim); while (it.next()) |f| fs.append(__global_allocator, f) catch continue; return fs.items; } }{ .data = _f, .delim = _d }; }";
const dictReaderBody = ";\nbreak :blk struct { data: []const u8, pos: usize = 0, fieldnames: ?[][]const u8 = null, pub fn next(s: *@This()) ?hashmap_helper.StringHashMap([]const u8) { if (s.pos >= s.data.len) return null; var le = std.mem.indexOfScalarPos(u8, s.data, s.pos, '\\n') orelse s.data.len; const ln = s.data[s.pos..le]; s.pos = le + 1; if (s.fieldnames == null) { var hs: std.ArrayList([]const u8) = .{}; var it = std.mem.splitScalar(u8, ln, ','); while (it.next()) |fh| hs.append(__global_allocator, fh) catch continue; s.fieldnames = hs.items; return s.next(); } var r = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var it = std.mem.splitScalar(u8, ln, ','); var i: usize = 0; while (it.next()) |v| { if (i < s.fieldnames.?.len) r.put(s.fieldnames.?[i], v) catch {}; i += 1; } return r; } }{ .data = _f }; }";
const dictWriterBody = ";\nbreak :blk struct { buffer: std.ArrayList(u8), fieldnames: [][]const u8, pub fn writeheader(s: *@This()) void { var f = true; for (s.fieldnames) |n| { if (!f) s.buffer.append(__global_allocator, ',') catch {}; f = false; s.buffer.appendSlice(__global_allocator, n) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn writerow(s: *@This(), r: anytype) void { var f = true; for (s.fieldnames) |n| { if (!f) s.buffer.append(__global_allocator, ',') catch {}; f = false; if (r.get(n)) |v| s.buffer.appendSlice(__global_allocator, v) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{}, .fieldnames = _fn }; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", h.wrap("blk: { const _f = ", readerBody, "void{}") },
    .{ "writer", genWriter },
    .{ "DictReader", h.wrap("blk: { const _f = ", dictReaderBody, "void{}") },
    .{ "DictWriter", h.wrapN(1, "blk: { const _fn = ", dictWriterBody, "void{}") },
    .{ "field_size_limit", h.I64(131072) }, .{ "QUOTE_ALL", h.I64(1) },
    .{ "QUOTE_MINIMAL", h.I64(0) }, .{ "QUOTE_NONNUMERIC", h.I64(2) },
    .{ "QUOTE_NONE", h.I64(3) },
});

pub const genWriter = h.c("struct { buffer: std.ArrayList(u8), delim: u8 = ',', pub fn writerow(s: *@This(), r: anytype) void { var f = true; for (r) |x| { if (!f) s.buffer.append(__global_allocator, s.delim) catch {}; f = false; s.buffer.appendSlice(__global_allocator, x) catch {}; } s.buffer.append(__global_allocator, '\\n') catch {}; } pub fn writerows(s: *@This(), rs: anytype) void { for (rs) |r| s.writerow(r); } pub fn getvalue(s: *@This()) []const u8 { return s.buffer.items; } }{ .buffer = .{} }");
