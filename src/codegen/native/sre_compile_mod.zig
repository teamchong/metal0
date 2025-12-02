/// Python sre_compile module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", genCompile }, .{ "isstring", h.c("true") }, .{ "MAXCODE", h.U32(65535) }, .{ "MAXGROUPS", h.U32(100) },
    .{ "_code", h.c("&[_]u32{}") }, .{ "_compile", h.c("{}") }, .{ "_compile_charset", h.c("{}") },
    .{ "_optimize_charset", h.c("&[_]@TypeOf(.{}){}") }, .{ "_generate_overlap_table", h.c("&[_]i32{}") }, .{ "_compile_info", h.c("{}") },
    .{ "SRE_FLAG_TEMPLATE", h.U32(1) }, .{ "SRE_FLAG_IGNORECASE", h.U32(2) }, .{ "SRE_FLAG_LOCALE", h.U32(4) },
    .{ "SRE_FLAG_MULTILINE", h.U32(8) }, .{ "SRE_FLAG_DOTALL", h.U32(16) }, .{ "SRE_FLAG_UNICODE", h.U32(32) },
    .{ "SRE_FLAG_VERBOSE", h.U32(64) }, .{ "SRE_FLAG_DEBUG", h.U32(128) }, .{ "SRE_FLAG_ASCII", h.U32(256) },
});

fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }; }"); }
    else { try self.emit(".{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }"); }
}
