/// Python encodings module - Standard Encodings Package
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate encodings.search_function(encoding)
pub fn genSearchFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const encoding = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = encoding; break :blk .{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }; }");
    } else {
        try self.emit("null");
    }
}

/// Generate encodings.normalize_encoding(encoding)
pub fn genNormalizeEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const e = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = e; break :blk \"utf_8\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate encodings.CodecInfo class
pub fn genCodecInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }");
}

/// Generate encodings.aliases dict
pub fn genAliases(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .ascii = \"ascii\", .utf_8 = \"utf-8\", .utf_16 = \"utf-16\", .utf_32 = \"utf-32\", .latin_1 = \"iso8859-1\", .iso_8859_1 = \"iso8859-1\" }");
}
