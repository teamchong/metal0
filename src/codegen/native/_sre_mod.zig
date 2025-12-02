/// Python _sre module - Internal SRE support (C accelerator for regex)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", genCompile }, .{ "c_o_d_e_s_i_z_e", h.I32(4) }, .{ "m_a_g_i_c", h.I32(20171005) },
    .{ "getlower", genGetlower }, .{ "getcodesize", h.I32(4) },
    .{ "match", h.c("null") }, .{ "fullmatch", h.c("null") }, .{ "search", h.c("null") },
    .{ "findall", h.c("&[_][]const u8{}") }, .{ "finditer", h.c("&[_]@TypeOf(null){}") },
    .{ "sub", genSub }, .{ "subn", genSubn }, .{ "split", h.c("&[_][]const u8{}") },
    .{ "group", h.c("\"\"") }, .{ "groups", h.c(".{}") }, .{ "groupdict", h.c(".{}") },
    .{ "start", h.I64(0) }, .{ "end", h.I64(0) }, .{ "span", h.c(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "expand", h.c("\"\"") },
});

fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const pat = "); try self.genExpr(args[0]); try self.emit("; _ = pat; break :blk .{ .pattern = pat, .flags = 0, .groups = 0 }; }"); } else { try self.emit(".{ .pattern = \"\", .flags = 0, .groups = 0 }"); }
}

fn genGetlower(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(i32, 0)");
}

fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("\"\"");
}

fn genSubn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit(".{ "); try self.genExpr(args[1]); try self.emit(", @as(i64, 0) }"); } else { try self.emit(".{ \"\", @as(i64, 0) }"); }
}
