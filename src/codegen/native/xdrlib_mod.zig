/// Python xdrlib module - XDR data encoding/decoding
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Packer", h.c(".{ .data = \"\" }") },
    .{ "Unpacker", genUnpacker },
    .{ "Error", h.err("XdrError") },
    .{ "ConversionError", h.err("ConversionError") },
});

fn genUnpacker(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .data = data, .pos = @as(i32, 0) }; }"); } else { try self.emit(".{ .data = \"\", .pos = @as(i32, 0) }"); }
}
