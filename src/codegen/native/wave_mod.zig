/// Python wave module - WAV file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate wave.open(f, mode=None)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const f = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }");
    } else {
        try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }");
    }
}

/// Generate wave.Wave_read class
pub fn genWave_read(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }");
}

/// Generate wave.Wave_write class
pub fn genWave_write(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }");
}

// ============================================================================
// Exception
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.WaveError");
}
