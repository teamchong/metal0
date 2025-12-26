/// Python _pyio module - Pure Python I/O implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "file_i_o", genFileIO },
    .{ "bytes_i_o", genBytesIO },
    .{ "string_i_o", genStringIO },
    .{ "buffered_reader", genBufferedReader },
    .{ "buffered_writer", genBufferedWriter },
    .{ "buffered_random", genBufferedRandom },
    .{ "buffered_r_w_pair", genBufferedRWPair },
    .{ "text_i_o_wrapper", genTextIOWrapper },
    .{ "incremental_newline_decoder", genIncrementalNewlineDecoder },
    .{ "d_e_f_a_u_l_t__b_u_f_f_e_r__s_i_z_e", genDefaultBufferSize },
    .{ "blocking_i_o_error", genBlockingIOError },
    .{ "unsupported_operation", genUnsupportedOperation },
});

fn genOpen(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .name = \"\", .mode = \"r\", .closed = false }";
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(default), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("pyio", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __v = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; break :{s} .{{ .name = __v, .mode = \"r\", .closed = false }}", .{label});
        }
    }.emit);
}

fn genFileIO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .mode = \"r\", .closefd = true, .closed = false }"), builder_mod.EmitConfig.forExpression());
}

fn genBytesIO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = \"\", .pos = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genStringIO(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = \"\", .pos = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genBufferedReader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .raw = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
}

fn genBufferedWriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .raw = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
}

fn genBufferedRandom(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .raw = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
}

fn genBufferedRWPair(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .reader = null, .writer = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
}

fn genTextIOWrapper(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = null, .encoding = \"utf-8\", .errors = \"strict\", .newline = null }"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementalNewlineDecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .decoder = null, .translate = false, .errors = \"strict\" }"), builder_mod.EmitConfig.forExpression());
}

fn genDefaultBufferSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8192), builder_mod.EmitConfig.forExpression());
}

fn genBlockingIOError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.BlockingIOError"), builder_mod.EmitConfig.forExpression());
}

fn genUnsupportedOperation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.UnsupportedOperation"), builder_mod.EmitConfig.forExpression());
}
