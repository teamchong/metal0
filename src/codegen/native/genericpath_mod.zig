/// Python genericpath module - Common path operations (shared by os.path implementations)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "exists", h.wrapBlk("ex", "_ = std.fs.cwd().statFile(__v) catch unreachable;", "true", "false") },
    .{ "isfile", h.wrapBlk("isf", "const _stat = std.fs.cwd().statFile(__v) catch unreachable;", "_stat.kind == .file", "false") },
    .{ "isdir", h.wrapBlk("isd", "const _dir = std.fs.cwd().openDir(__v, .{}) catch unreachable; _dir.close();", "true", "false") },
    .{ "getsize", h.wrapBlk("gsz", "const _stat = std.fs.cwd().statFile(__v) catch unreachable;", "@as(i64, @intCast(_stat.size))", "@as(i64, 0)") },
    .{ "getatime", h.F64(0.0) }, .{ "getmtime", h.F64(0.0) }, .{ "getctime", h.F64(0.0) },
    .{ "commonprefix", h.c("\"\"") }, .{ "samestat", h.c("false") },
    .{ "samefile", h.wrap2Blk("samef", "", "std.mem.eql(u8, __v0, __v1)", "false") },
    .{ "sameopenfile", h.c("false") },
    .{ "islink", h.wrapBlk("isl", "const _stat = std.fs.cwd().statFile(__v) catch unreachable;", "_stat.kind == .sym_link", "false") },
});
