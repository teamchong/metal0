/// Python _io module - Core I/O implementation (underlying io module)
const std = @import("std");
const h = @import("mod_helper.zig");

const genFileIO = h.wrap("blk: { const path = ", "; break :blk std.fs.cwd().openFile(path, .{}) catch null; }", "@as(?std.fs.File, null)");
const genBytesIO = h.wrap("blk: { const init = ", "; var bio = std.ArrayList(u8).init(metal0_allocator); bio.appendSlice(init) catch {}; break :blk .{ .buffer = bio, .pos = 0 }; }", ".{ .buffer = std.ArrayList(u8).init(metal0_allocator), .pos = 0 }");
const genStringIO = h.wrap("blk: { const init = ", "; var sio = std.ArrayList(u8).init(metal0_allocator); sio.appendSlice(init) catch {}; break :blk .{ .buffer = sio, .pos = 0 }; }", ".{ .buffer = std.ArrayList(u8).init(metal0_allocator), .pos = 0 }");
const genBuffered = h.wrap("blk: { const raw = ", "; break :blk .{ .raw = raw, .buffer_size = 8192 }; }", ".{ .raw = null, .buffer_size = 8192 }");
const genTextIO = h.wrap("blk: { const buf = ", "; break :blk .{ .buffer = buf, .encoding = \"utf-8\" }; }", ".{ .buffer = null, .encoding = \"utf-8\" }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FileIO", genFileIO }, .{ "BytesIO", genBytesIO }, .{ "StringIO", genStringIO },
    .{ "BufferedReader", genBuffered }, .{ "BufferedWriter", genBuffered }, .{ "BufferedRandom", genBuffered },
    .{ "BufferedRWPair", h.wrap2("blk: { const r = ", "; const w = ", "; break :blk .{ .reader = r, .writer = w, .buffer_size = 8192 }; }", ".{ .reader = null, .writer = null, .buffer_size = 8192 }") },
    .{ "TextIOWrapper", genTextIO }, .{ "IncrementalNewlineDecoder", h.c(".{ .translate = true }") },
    .{ "open", genFileIO },
    .{ "open_code", h.wrap("blk: { const path = ", "; break :blk std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch null; }", "@as(?std.fs.File, null)") },
    .{ "text_encoding", h.pass("\"utf-8\"") },
    .{ "IOBase", h.c(".{}") }, .{ "RawIOBase", h.c(".{}") }, .{ "BufferedIOBase", h.c(".{}") }, .{ "TextIOBase", h.c(".{}") },
    .{ "DEFAULT_BUFFER_SIZE", h.I64(8192) }, .{ "UnsupportedOperation", h.err("UnsupportedOperation") }, .{ "BlockingIOError", h.err("BlockingIOError") },
});
