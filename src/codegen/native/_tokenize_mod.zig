/// Python _tokenize module - Internal tokenize support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "token_info", genTokenInfo },
    .{ "tokenize", genTokenize },
    .{ "generate_tokens", genGenerateTokens },
    .{ "detect_encoding", genDetectEncoding },
    .{ "untokenize", genUntokenize },
    .{ "open", genOpen },
    .{ "token_error", genTokenError },
    .{ "stop_tokenizing", genStopTokenizing },
    .{ "e_n_c_o_d_i_n_g", genEncoding },
    .{ "c_o_m_m_e_n_t", genComment },
    .{ "n_l", genNl },
});

fn genTokenInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genTokenize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}"), builder_mod.EmitConfig.forExpression());
}

fn genGenerateTokens(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}"), builder_mod.EmitConfig.forExpression());
}

fn genDetectEncoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"utf-8\", &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genUntokenize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genOpen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genTokenError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.TokenError"), builder_mod.EmitConfig.forExpression());
}

fn genStopTokenizing(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.StopTokenizing"), builder_mod.EmitConfig.forExpression());
}

fn genEncoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(62), builder_mod.EmitConfig.forExpression());
}

fn genComment(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(60), builder_mod.EmitConfig.forExpression());
}

fn genNl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(61), builder_mod.EmitConfig.forExpression());
}

