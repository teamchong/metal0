/// Python _io module - Core I/O implementation (underlying io module)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// File I/O Classes
// ============================================================================

/// Generate _io.FileIO(name, mode='r', closefd=True, opener=None)
pub fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }");
    } else {
        try self.emit("@as(?std.fs.File, null)");
    }
}

/// Generate _io.BytesIO(initial_bytes=b'')
pub fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const init = ");
        try self.genExpr(args[0]);
        try self.emit("; var bio = std.ArrayList(u8).init(pyaot_allocator); bio.appendSlice(init) catch {}; break :blk .{ .buffer = bio, .pos = 0 }; }");
    } else {
        try self.emit(".{ .buffer = std.ArrayList(u8).init(pyaot_allocator), .pos = 0 }");
    }
}

/// Generate _io.StringIO(initial_value='')
pub fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const init = ");
        try self.genExpr(args[0]);
        try self.emit("; var sio = std.ArrayList(u8).init(pyaot_allocator); sio.appendSlice(init) catch {}; break :blk .{ .buffer = sio, .pos = 0 }; }");
    } else {
        try self.emit(".{ .buffer = std.ArrayList(u8).init(pyaot_allocator), .pos = 0 }");
    }
}

/// Generate _io.BufferedReader(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const raw = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .raw = raw, .buffer_size = 8192 }; }");
    } else {
        try self.emit(".{ .raw = null, .buffer_size = 8192 }");
    }
}

/// Generate _io.BufferedWriter(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const raw = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .raw = raw, .buffer_size = 8192 }; }");
    } else {
        try self.emit(".{ .raw = null, .buffer_size = 8192 }");
    }
}

/// Generate _io.BufferedRandom(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const raw = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .raw = raw, .buffer_size = 8192 }; }");
    } else {
        try self.emit(".{ .raw = null, .buffer_size = 8192 }");
    }
}

/// Generate _io.BufferedRWPair(reader, writer, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedRWPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const r = ");
        try self.genExpr(args[0]);
        try self.emit("; const w = ");
        try self.genExpr(args[1]);
        try self.emit("; break :blk .{ .reader = r, .writer = w, .buffer_size = 8192 }; }");
    } else {
        try self.emit(".{ .reader = null, .writer = null, .buffer_size = 8192 }");
    }
}

/// Generate _io.TextIOWrapper(buffer, encoding=None, errors=None, newline=None, line_buffering=False, write_through=False)
pub fn genTextIOWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const buf = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .buffer = buf, .encoding = \"utf-8\" }; }");
    } else {
        try self.emit(".{ .buffer = null, .encoding = \"utf-8\" }");
    }
}

/// Generate _io.IncrementalNewlineDecoder(decoder, translate, errors='strict')
pub fn genIncrementalNewlineDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .translate = true }");
}

// ============================================================================
// Functions
// ============================================================================

/// Generate _io.open(file, mode='r', buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }");
    } else {
        try self.emit("@as(?std.fs.File, null)");
    }
}

/// Generate _io.open_code(path)
pub fn genOpen_code(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch null; }");
    } else {
        try self.emit("@as(?std.fs.File, null)");
    }
}

/// Generate _io.text_encoding(encoding, stacklevel=2)
pub fn genText_encoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"utf-8\"");
    }
}

// ============================================================================
// Abstract Base Classes
// ============================================================================

pub fn genIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genRawIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genBufferedIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genTextIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// Constants
// ============================================================================

pub fn genDEFAULT_BUFFER_SIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 8192)");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genUnsupportedOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnsupportedOperation");
}

pub fn genBlockingIOError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BlockingIOError");
}
