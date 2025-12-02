/// Python genericpath module - Common path operations (shared by os.path implementations)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "exists", h.wrap("blk: { const path = ", "; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }", "false") },
    .{ "isfile", h.wrap("blk: { const path = ", "; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .file; }", "false") },
    .{ "isdir", h.wrap("blk: { const path = ", "; const dir = std.fs.cwd().openDir(path, .{}) catch break :blk false; dir.close(); break :blk true; }", "false") },
    .{ "getsize", h.wrap("blk: { const path = ", "; const stat = std.fs.cwd().statFile(path) catch break :blk @as(i64, 0); break :blk @intCast(stat.size); }", "@as(i64, 0)") },
    .{ "getatime", h.F64(0.0) }, .{ "getmtime", h.F64(0.0) }, .{ "getctime", h.F64(0.0) },
    .{ "commonprefix", h.c("\"\"") }, .{ "samestat", h.c("false") },
    .{ "samefile", h.wrap2("blk: { const p1 = ", "; const p2 = ", "; break :blk std.mem.eql(u8, p1, p2); }", "false") },
    .{ "sameopenfile", h.c("false") },
    .{ "islink", h.wrap("blk: { const path = ", "; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .sym_link; }", "false") },
});
