/// Python encodings module - Standard Encodings Package
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "search_function", genSearch }, .{ "normalize_encoding", genNormalize },
    .{ "CodecInfo", h.c(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }") },
    .{ "aliases", h.c(".{ .ascii = \"ascii\", .utf_8 = \"utf-8\", .utf_16 = \"utf-16\", .utf_32 = \"utf-32\", .latin_1 = \"iso8859-1\", .iso_8859_1 = \"iso8859-1\" }") },
});

fn genSearch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const encoding = "); try self.genExpr(args[0]); try self.emit("; _ = encoding; break :blk .{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }; }"); } else { try self.emit("null"); }
}
fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const e = "); try self.genExpr(args[0]); try self.emit("; _ = e; break :blk \"utf_8\"; }"); } else { try self.emit("\"\""); }
}
