/// Python _tokenize module - Internal tokenize support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "token_info", h.c(".{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }") },
    .{ "tokenize", h.c("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}") },
    .{ "generate_tokens", h.c("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}") },
    .{ "detect_encoding", h.c(".{ \"utf-8\", &[_][]const u8{} }") }, .{ "untokenize", h.c("\"\"") }, .{ "open", h.c("null") },
    .{ "token_error", h.err("TokenError") }, .{ "stop_tokenizing", h.err("StopTokenizing") },
    .{ "e_n_c_o_d_i_n_g", h.I32(62) }, .{ "c_o_m_m_e_n_t", h.I32(60) }, .{ "n_l", h.I32(61) },
});
