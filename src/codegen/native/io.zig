/// IO module codegen - StringIO, BytesIO
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Generate io.StringIO() constructor
pub fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.StringIO.create(__global_allocator)");
    } else {
        try self.emit("try runtime.io.StringIO.createWithValue(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate io.BytesIO() constructor
pub fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
    } else {
        try self.emit("try runtime.io.BytesIO.createWithValue(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate io.open() - same as builtin open()
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genOpen(self, args);
}

/// Generate io.TextIOWrapper(buffer, encoding, errors, newline, line_buffering, write_through)
pub fn genTextIOWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.StringIO.create(__global_allocator)");
        return;
    }
    // Wrap an existing buffer - for now, just return a StringIO
    try self.emit("try runtime.io.StringIO.createWithValue(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate io.BufferedReader(raw, buffer_size)
pub fn genBufferedReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
        return;
    }
    // Wrap raw stream - for now, return BytesIO
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.BufferedWriter(raw, buffer_size)
pub fn genBufferedWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
        return;
    }
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.BufferedRandom(raw, buffer_size)
pub fn genBufferedRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.BufferedRWPair(reader, writer, buffer_size)
pub fn genBufferedRWPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.FileIO(name, mode, closefd, opener)
pub fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
        return;
    }
    // Open file in binary mode
    try self.emit("try runtime.io.openFile(__global_allocator, ");
    try self.genExpr(args[0]);
    if (args.len > 1) {
        try self.emit(", ");
        try self.genExpr(args[1]);
    } else {
        try self.emit(", \"rb\"");
    }
    try self.emit(")");
}

/// Generate io.RawIOBase - base class
pub fn genRawIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.IOBase - base class
pub fn genIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
}

/// Generate io.TextIOBase - base class
pub fn genTextIOBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try runtime.io.StringIO.create(__global_allocator)");
}

/// Generate io.UnsupportedOperation exception
pub fn genUnsupportedOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnsupportedOperation");
}

/// Generate io.DEFAULT_BUFFER_SIZE constant
pub fn genDEFAULT_BUFFER_SIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 8192)");
}

/// Generate io.SEEK_SET constant
pub fn genSEEK_SET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate io.SEEK_CUR constant
pub fn genSEEK_CUR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate io.SEEK_END constant
pub fn genSEEK_END(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}
