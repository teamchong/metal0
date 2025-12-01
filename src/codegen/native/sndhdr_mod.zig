/// Python sndhdr module - Sound file type determination
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "what", genWhat },
    .{ "whathdr", genWhathdr },
    .{ "SndHeaders", genSndHeaders },
    .{ "tests", genTests },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sndhdr.what(filename)
pub fn genWhat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns SndHeaders namedtuple or None
    try self.emit("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)");
}

/// Generate sndhdr.whathdr(filename)
pub fn genWhathdr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Alias for what()
    try self.emit("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)");
}

/// Generate sndhdr.SndHeaders namedtuple
pub fn genSndHeaders(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }");
}

// ============================================================================
// Test functions (exposed for custom detection)
// ============================================================================

pub fn genTests(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*const fn ([]const u8, *anyopaque) ?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }){}");
}
