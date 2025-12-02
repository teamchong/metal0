/// Python sndhdr module - Sound file type determination
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "what", genNull }, .{ "whathdr", genNull }, .{ "SndHeaders", genHeaders }, .{ "tests", genTests },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)"); }
fn genHeaders(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }"); }
fn genTests(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]*const fn ([]const u8, *anyopaque) ?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }){}"); }
