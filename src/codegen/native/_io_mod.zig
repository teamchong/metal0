/// Python _io module - Core I/O implementation (underlying io module)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FileIO", genFileIO }, .{ "BytesIO", genBytesIO }, .{ "StringIO", genStringIO },
    .{ "BufferedReader", genBuffered }, .{ "BufferedWriter", genBuffered }, .{ "BufferedRandom", genBuffered },
    .{ "BufferedRWPair", genBufferedRW }, .{ "TextIOWrapper", genTextIO }, .{ "IncrementalNewlineDecoder", genNewline },
    .{ "open", genFileIO }, .{ "open_code", genOpenCode }, .{ "text_encoding", genTextEnc },
    .{ "IOBase", genEmpty }, .{ "RawIOBase", genEmpty }, .{ "BufferedIOBase", genEmpty }, .{ "TextIOBase", genEmpty },
    .{ "DEFAULT_BUFFER_SIZE", genBufSize }, .{ "UnsupportedOperation", genUnsupErr }, .{ "BlockingIOError", genBlockErr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genBufSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 8192)"); }
fn genUnsupErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.UnsupportedOperation"); }
fn genBlockErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.BlockingIOError"); }
fn genNewline(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .translate = true }"); }

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
