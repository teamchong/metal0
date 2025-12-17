/// Python _io module - Core I/O implementation (underlying io module)
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(?std.fs.File, null)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__io_fio_{d}: {{ const __path_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__io_fio_{d} std.fs.cwd().openFile(__path_{d}, .{{}}) catch null; }})", .{ id, id });
}

fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .buffer = .{}, .pos = 0 }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__io_bio_{d}: {{ const __init_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; var __bio_{d}: std.ArrayList(u8) = .{{}}; __bio_{d}.appendSlice(__global_allocator, __init_{d}) catch unreachable; break :__io_bio_{d} .{{ .buffer = __bio_{d}, .pos = 0 }}; }})", .{ id, id, id, id, id });
}

fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .buffer = .{}, .pos = 0 }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__io_sio_{d}: {{ const __init_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; var __sio_{d}: std.ArrayList(u8) = .{{}}; __sio_{d}.appendSlice(__global_allocator, __init_{d}) catch unreachable; break :__io_sio_{d} .{{ .buffer = __sio_{d}, .pos = 0 }}; }})", .{ id, id, id, id, id });
}

const genBuffered = h.structBlk("buf", ".raw = __v, .buffer_size = 8192", ".{ .raw = null, .buffer_size = 8192 }");
const genTextIO = h.structBlk("tio", ".buffer = __v, .encoding = \"utf-8\"", ".{ .buffer = null, .encoding = \"utf-8\" }");

fn genBufferedRWPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit(".{ .reader = null, .writer = null, .buffer_size = 8192 }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__io_rwp_{d}: {{ const __r_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __w_{d} = ", .{id});
    try self.genExpr(args[1]);
    try self.emitFmt("; break :__io_rwp_{d} .{{ .reader = __r_{d}, .writer = __w_{d}, .buffer_size = 8192 }}; }})", .{ id, id, id });
}

fn genOpenCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(?std.fs.File, null)"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__io_oc_{d}: {{ const __path_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__io_oc_{d} std.fs.cwd().openFile(__path_{d}, .{{ .mode = .read_only }}) catch null; }})", .{ id, id });
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FileIO", genFileIO }, .{ "BytesIO", genBytesIO }, .{ "StringIO", genStringIO },
    .{ "BufferedReader", genBuffered }, .{ "BufferedWriter", genBuffered }, .{ "BufferedRandom", genBuffered },
    .{ "BufferedRWPair", genBufferedRWPair },
    .{ "TextIOWrapper", genTextIO }, .{ "IncrementalNewlineDecoder", h.c(".{ .translate = true }") },
    .{ "open", genFileIO },
    .{ "open_code", genOpenCode },
    .{ "text_encoding", h.pass("\"utf-8\"") },
    .{ "IOBase", h.c(".{}") }, .{ "RawIOBase", h.c(".{}") }, .{ "BufferedIOBase", h.c(".{}") }, .{ "TextIOBase", h.c(".{}") },
    .{ "DEFAULT_BUFFER_SIZE", h.I64(8192) }, .{ "UnsupportedOperation", h.err("UnsupportedOperation") }, .{ "BlockingIOError", h.err("BlockingIOError") },
});
