/// Python _pyio module - Pure Python I/O implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _pyio.open(file, mode='r', buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = path; break :blk .{ .name = path, .mode = \"r\", .closed = false }; }");
    } else {
        try self.emit(".{ .name = \"\", .mode = \"r\", .closed = false }");
    }
}

/// Generate _pyio.FileIO(name, mode='r', closefd=True, opener=None)
pub fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .mode = \"r\", .closefd = true, .closed = false }");
}

/// Generate _pyio.BytesIO(initial_bytes=b'')
pub fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .buffer = \"\", .pos = 0 }");
}

/// Generate _pyio.StringIO(initial_value='', newline='\\n')
pub fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .buffer = \"\", .pos = 0 }");
}

/// Generate _pyio.BufferedReader(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .raw = null, .buffer_size = 8192 }");
}

/// Generate _pyio.BufferedWriter(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .raw = null, .buffer_size = 8192 }");
}

/// Generate _pyio.BufferedRandom(raw, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .raw = null, .buffer_size = 8192 }");
}

/// Generate _pyio.BufferedRWPair(reader, writer, buffer_size=DEFAULT_BUFFER_SIZE)
pub fn genBufferedRWPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .reader = null, .writer = null, .buffer_size = 8192 }");
}

/// Generate _pyio.TextIOWrapper(buffer, encoding=None, errors=None, newline=None, line_buffering=False, write_through=False)
pub fn genTextIOWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .buffer = null, .encoding = \"utf-8\", .errors = \"strict\", .newline = null }");
}

/// Generate _pyio.IncrementalNewlineDecoder(decoder, translate, errors='strict')
pub fn genIncrementalNewlineDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .decoder = null, .translate = false, .errors = \"strict\" }");
}

/// Generate _pyio.DEFAULT_BUFFER_SIZE constant
pub fn genDEFAULT_BUFFER_SIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8192)");
}

/// Generate _pyio.BlockingIOError exception
pub fn genBlockingIOError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BlockingIOError");
}

/// Generate _pyio.UnsupportedOperation exception
pub fn genUnsupportedOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnsupportedOperation");
}
