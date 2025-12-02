/// Python _tokenize module - Internal tokenize support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "token_info", genConst(".{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }") },
    .{ "tokenize", genConst("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}") },
    .{ "generate_tokens", genConst("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}") },
    .{ "detect_encoding", genConst(".{ \"utf-8\", &[_][]const u8{} }") }, .{ "untokenize", genConst("\"\"") }, .{ "open", genConst("null") },
    .{ "token_error", genConst("error.TokenError") }, .{ "stop_tokenizing", genConst("error.StopTokenizing") },
    .{ "e_n_c_o_d_i_n_g", genI32(62) }, .{ "c_o_m_m_e_n_t", genI32(60) }, .{ "n_l", genI32(61) },
});
