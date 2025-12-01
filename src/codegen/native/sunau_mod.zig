/// Python sunau module - Sun AU audio file handling
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen },
    .{ "Au_read", genAu_read },
    .{ "Au_write", genAu_write },
    .{ "AUDIO_FILE_MAGIC", genAUDIO_FILE_MAGIC },
    .{ "AUDIO_FILE_ENCODING_MULAW_8", genAUDIO_FILE_ENCODING_MULAW_8 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_8", genAUDIO_FILE_ENCODING_LINEAR_8 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_16", genAUDIO_FILE_ENCODING_LINEAR_16 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_24", genAUDIO_FILE_ENCODING_LINEAR_24 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_32", genAUDIO_FILE_ENCODING_LINEAR_32 },
    .{ "AUDIO_FILE_ENCODING_FLOAT", genAUDIO_FILE_ENCODING_FLOAT },
    .{ "AUDIO_FILE_ENCODING_DOUBLE", genAUDIO_FILE_ENCODING_DOUBLE },
    .{ "AUDIO_FILE_ENCODING_ALAW_8", genAUDIO_FILE_ENCODING_ALAW_8 },
    .{ "Error", genError },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sunau.open(f, mode=None)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const f = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }");
    } else {
        try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }");
    }
}

/// Generate sunau.Au_read class
pub fn genAu_read(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }");
}

/// Generate sunau.Au_write class
pub fn genAu_write(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }");
}

// ============================================================================
// Encoding format constants
// ============================================================================

pub fn genAUDIO_FILE_MAGIC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x2e736e64)"); // ".snd"
}

pub fn genAUDIO_FILE_ENCODING_MULAW_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genAUDIO_FILE_ENCODING_LINEAR_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genAUDIO_FILE_ENCODING_LINEAR_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genAUDIO_FILE_ENCODING_LINEAR_24(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genAUDIO_FILE_ENCODING_LINEAR_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genAUDIO_FILE_ENCODING_FLOAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genAUDIO_FILE_ENCODING_DOUBLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genAUDIO_FILE_ENCODING_ALAW_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 27)");
}

// ============================================================================
// Exception
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SunauError");
}
