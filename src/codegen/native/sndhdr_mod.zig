/// Python sndhdr module - Sound file type determination
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "what", genConst("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)") },
    .{ "whathdr", genConst("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)") },
    .{ "SndHeaders", genConst(".{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }") },
    .{ "tests", genConst("&[_]*const fn ([]const u8, *anyopaque) ?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }){}") },
});
