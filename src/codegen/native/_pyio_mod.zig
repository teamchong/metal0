/// Python _pyio module - Pure Python I/O implementation
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen }, .{ "file_i_o", h.c(".{ .name = \"\", .mode = \"r\", .closefd = true, .closed = false }") },
    .{ "bytes_i_o", h.c(".{ .buffer = \"\", .pos = 0 }") }, .{ "string_i_o", h.c(".{ .buffer = \"\", .pos = 0 }") },
    .{ "buffered_reader", h.c(".{ .raw = null, .buffer_size = 8192 }") }, .{ "buffered_writer", h.c(".{ .raw = null, .buffer_size = 8192 }") }, .{ "buffered_random", h.c(".{ .raw = null, .buffer_size = 8192 }") },
    .{ "buffered_r_w_pair", h.c(".{ .reader = null, .writer = null, .buffer_size = 8192 }") },
    .{ "text_i_o_wrapper", h.c(".{ .buffer = null, .encoding = \"utf-8\", .errors = \"strict\", .newline = null }") },
    .{ "incremental_newline_decoder", h.c(".{ .decoder = null, .translate = false, .errors = \"strict\" }") },
    .{ "d_e_f_a_u_l_t__b_u_f_f_e_r__s_i_z_e", h.I32(8192) }, .{ "blocking_i_o_error", h.err("BlockingIOError") }, .{ "unsupported_operation", h.err("UnsupportedOperation") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = path; break :blk .{ .name = path, .mode = \"r\", .closed = false }; }"); } else try self.emit(".{ .name = \"\", .mode = \"r\", .closed = false }"); }
