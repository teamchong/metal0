/// Python _pyio module - Pure Python I/O implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genBuffer8192(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .raw = null, .buffer_size = 8192 }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "file_i_o", genFileIO }, .{ "bytes_i_o", genBytesIO }, .{ "string_i_o", genBytesIO },
    .{ "buffered_reader", genBuffer8192 }, .{ "buffered_writer", genBuffer8192 }, .{ "buffered_random", genBuffer8192 },
    .{ "buffered_r_w_pair", genBufferedRWPair }, .{ "text_i_o_wrapper", genTextIOWrapper }, .{ "incremental_newline_decoder", genNewlineDecoder },
    .{ "d_e_f_a_u_l_t__b_u_f_f_e_r__s_i_z_e", genBufferSize }, .{ "blocking_i_o_error", genBlockingIOError }, .{ "unsupported_operation", genUnsupportedOp },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = path; break :blk .{ .name = path, .mode = \"r\", .closed = false }; }"); } else try self.emit(".{ .name = \"\", .mode = \"r\", .closed = false }"); }
fn genFileIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .mode = \"r\", .closefd = true, .closed = false }"); }
fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .buffer = \"\", .pos = 0 }"); }
fn genBufferedRWPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .reader = null, .writer = null, .buffer_size = 8192 }"); }
fn genTextIOWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .buffer = null, .encoding = \"utf-8\", .errors = \"strict\", .newline = null }"); }
fn genNewlineDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decoder = null, .translate = false, .errors = \"strict\" }"); }
fn genBufferSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8192)"); }
fn genBlockingIOError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.BlockingIOError"); }
fn genUnsupportedOp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.UnsupportedOperation"); }
