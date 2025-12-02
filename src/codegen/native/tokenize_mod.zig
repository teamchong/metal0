/// Python tokenize module - Tokenizer for Python source
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "tokenize", h.c("metal0_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()") },
    .{ "generate_tokens", h.c("metal0_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()") },
    .{ "detect_encoding", h.c(".{ \"utf-8\", metal0_runtime.PyList([]const u8).init() }") },
    .{ "open", genOpen }, .{ "untokenize", h.c("\"\"") },
    .{ "TokenInfo", h.c(".{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" }") },
    .{ "TokenError", h.err("TokenError") }, .{ "StopTokenizing", h.err("StopTokenizing") },
    .{ "ENDMARKER", h.I32(0) }, .{ "NAME", h.I32(1) }, .{ "NUMBER", h.I32(2) }, .{ "STRING", h.I32(3) },
    .{ "NEWLINE", h.I32(4) }, .{ "INDENT", h.I32(5) }, .{ "DEDENT", h.I32(6) }, .{ "OP", h.I32(54) },
    .{ "ERRORTOKEN", h.I32(59) }, .{ "COMMENT", h.I32(60) }, .{ "NL", h.I32(61) }, .{ "ENCODING", h.I32(62) }, .{ "N_TOKENS", h.I32(63) },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }"); }
    else { try self.emit("@as(?std.fs.File, null)"); }
}
