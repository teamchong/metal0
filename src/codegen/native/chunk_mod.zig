/// Python chunk module - Read IFF chunked data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate chunk.Chunk(file, align=True, bigendian=True, inclheader=False)
pub fn genChunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const file = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = file; break :blk .{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }; }");
    } else {
        try self.emit(".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }");
    }
}

/// Generate Chunk.getname()
pub fn genGetname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate Chunk.getsize()
pub fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate Chunk.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Chunk.isatty()
pub fn genIsatty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Chunk.seek(pos, whence=0)
pub fn genSeek(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Chunk.tell()
pub fn genTell(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate Chunk.read(size=-1)
pub fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate Chunk.skip()
pub fn genSkip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
