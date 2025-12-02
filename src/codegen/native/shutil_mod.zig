/// Python shutil module - high-level file operations
const std = @import("std");
const h = @import("mod_helper.zig");

const copyBody = "; std.fs.copyFileAbsolute(_src, _dst, .{}) catch break :blk _dst; break :blk _dst; }";
const moveBody = "; std.fs.renameAbsolute(_src, _dst) catch break :blk _dst; break :blk _dst; }";
const copytreeBody = "; var _src_dir = std.fs.openDirAbsolute(_src, .{ .iterate = true }) catch break :blk _dst; defer _src_dir.close(); std.fs.makeDirAbsolute(_dst) catch {}; var _iter = _src_dir.iterate(); while (_iter.next() catch null) |entry| { const _src_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_src, entry.name}) catch continue; defer __global_allocator.free(_src_path); const _dst_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_dst, entry.name}) catch continue; defer __global_allocator.free(_dst_path); if (entry.kind == .file) std.fs.copyFileAbsolute(_src_path, _dst_path, .{}) catch continue; } break :blk _dst; }";
const whichBody = "; const _paths = std.posix.getenv(\"PATH\") orelse break :blk null; var _iter = std.mem.splitSequence(u8, _paths, \":\"); while (_iter.next()) |dir| { const _full_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{dir, _cmd}) catch continue; const _stat = std.fs.cwd().statFile(_full_path) catch continue; _ = _stat; break :blk _full_path; } break :blk null; }";
const genCopy = h.wrap2("blk: { const _src = ", "; const _dst = ", copyBody, "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy }, .{ "copy2", genCopy }, .{ "copyfile", genCopy },
    .{ "copystat", h.c("{}") }, .{ "copymode", h.c("{}") },
    .{ "move", h.wrap2("blk: { const _src = ", "; const _dst = ", moveBody, "\"\"") },
    .{ "rmtree", h.wrap("blk: { const _path = ", "; std.fs.deleteTreeAbsolute(_path) catch {}; break :blk; }", "{}") },
    .{ "copytree", h.wrap2("blk: { const _src = ", "; const _dst = ", copytreeBody, "\"\"") },
    .{ "disk_usage", h.c(".{ @as(i64, 0), @as(i64, 0), @as(i64, 0) }") },
    .{ "which", h.wrap("blk: { const _cmd = ", whichBody, "null") },
    .{ "get_terminal_size", h.c(".{ @as(i64, 80), @as(i64, 24) }") },
    .{ "make_archive", h.pass("\"\"") }, .{ "unpack_archive", h.c("{}") },
});
