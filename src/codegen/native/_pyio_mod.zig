/// Python _pyio module - Pure Python I/O implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "file_i_o", genConst(".{ .name = \"\", .mode = \"r\", .closefd = true, .closed = false }") },
    .{ "bytes_i_o", genConst(".{ .buffer = \"\", .pos = 0 }") }, .{ "string_i_o", genConst(".{ .buffer = \"\", .pos = 0 }") },
    .{ "buffered_reader", genConst(".{ .raw = null, .buffer_size = 8192 }") }, .{ "buffered_writer", genConst(".{ .raw = null, .buffer_size = 8192 }") }, .{ "buffered_random", genConst(".{ .raw = null, .buffer_size = 8192 }") },
    .{ "buffered_r_w_pair", genConst(".{ .reader = null, .writer = null, .buffer_size = 8192 }") },
    .{ "text_i_o_wrapper", genConst(".{ .buffer = null, .encoding = \"utf-8\", .errors = \"strict\", .newline = null }") },
    .{ "incremental_newline_decoder", genConst(".{ .decoder = null, .translate = false, .errors = \"strict\" }") },
    .{ "d_e_f_a_u_l_t__b_u_f_f_e_r__s_i_z_e", genConst("@as(i32, 8192)") }, .{ "blocking_i_o_error", genConst("error.BlockingIOError") }, .{ "unsupported_operation", genConst("error.UnsupportedOperation") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = path; break :blk .{ .name = path, .mode = \"r\", .closed = false }; }"); } else try self.emit(".{ .name = \"\", .mode = \"r\", .closed = false }"); }
