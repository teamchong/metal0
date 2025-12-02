/// Python _tokenize module - Internal tokenize support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "token_info", genTokenInfo }, .{ "tokenize", genTokens }, .{ "generate_tokens", genTokens },
    .{ "detect_encoding", genDetectEncoding }, .{ "untokenize", genEmptyStr }, .{ "open", genNull },
    .{ "token_error", genTokenError }, .{ "stop_tokenizing", genStopTokenizing },
    .{ "e_n_c_o_d_i_n_g", genI32(62) }, .{ "c_o_m_m_e_n_t", genI32(60) }, .{ "n_l", genI32(61) },
});

fn genTokenInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }"); }
fn genTokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}"); }
fn genDetectEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"utf-8\", &[_][]const u8{} }"); }
fn genTokenError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TokenError"); }
fn genStopTokenizing(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.StopTokenizing"); }
