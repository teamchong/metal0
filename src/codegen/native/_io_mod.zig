/// Python _io module - Core I/O implementation (underlying io module)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FileIO", genFileIO }, .{ "BytesIO", genBytesIO }, .{ "StringIO", genStringIO },
    .{ "BufferedReader", genBuffered }, .{ "BufferedWriter", genBuffered }, .{ "BufferedRandom", genBuffered },
    .{ "BufferedRWPair", genBufferedRW }, .{ "TextIOWrapper", genTextIO }, .{ "IncrementalNewlineDecoder", h.c(".{ .translate = true }") },
    .{ "open", genFileIO }, .{ "open_code", genOpenCode }, .{ "text_encoding", genTextEnc },
    .{ "IOBase", h.c(".{}") }, .{ "RawIOBase", h.c(".{}") }, .{ "BufferedIOBase", h.c(".{}") }, .{ "TextIOBase", h.c(".{}") },
    .{ "DEFAULT_BUFFER_SIZE", h.I64(8192) }, .{ "UnsupportedOperation", h.err("UnsupportedOperation") }, .{ "BlockingIOError", h.err("BlockingIOError") },
});

fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }"); } else { try self.emit("@as(?std.fs.File, null)"); }
}

fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const init = "); try self.genExpr(args[0]); try self.emit("; var bio = std.ArrayList(u8).init(metal0_allocator); bio.appendSlice(init) catch {}; break :blk .{ .buffer = bio, .pos = 0 }; }"); } else { try self.emit(".{ .buffer = std.ArrayList(u8).init(metal0_allocator), .pos = 0 }"); }
}

fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const init = "); try self.genExpr(args[0]); try self.emit("; var sio = std.ArrayList(u8).init(metal0_allocator); sio.appendSlice(init) catch {}; break :blk .{ .buffer = sio, .pos = 0 }; }"); } else { try self.emit(".{ .buffer = std.ArrayList(u8).init(metal0_allocator), .pos = 0 }"); }
}

fn genBuffered(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const raw = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .raw = raw, .buffer_size = 8192 }; }"); } else { try self.emit(".{ .raw = null, .buffer_size = 8192 }"); }
}

fn genBufferedRW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const r = "); try self.genExpr(args[0]); try self.emit("; const w = "); try self.genExpr(args[1]); try self.emit("; break :blk .{ .reader = r, .writer = w, .buffer_size = 8192 }; }"); } else { try self.emit(".{ .reader = null, .writer = null, .buffer_size = 8192 }"); }
}

fn genTextIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const buf = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .buffer = buf, .encoding = \"utf-8\" }; }"); } else { try self.emit(".{ .buffer = null, .encoding = \"utf-8\" }"); }
}

fn genOpenCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch null; }"); } else { try self.emit("@as(?std.fs.File, null)"); }
}

fn genTextEnc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"utf-8\"");
}
