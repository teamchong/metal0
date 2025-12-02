/// Python unicodedata module - Unicode character database
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genCharFunc(comptime label: []const u8, comptime default: []const u8, comptime body: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit(label ++ ": { const c = "); try self.genExpr(args[0]); try self.emit("[0]; " ++ body ++ " }");
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "lookup", genLookup }, .{ "name", genName },
    .{ "decimal", genCharFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "digit", genCharFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "numeric", genCharFunc("blk", "@as(f64, -1.0)", "if (c >= '0' and c <= '9') break :blk @as(f64, @floatFromInt(c - '0')) else break :blk -1.0;") },
    .{ "category", genCharFunc("blk", "\"Cn\"", "if (c >= 'a' and c <= 'z') break :blk \"Ll\" else if (c >= 'A' and c <= 'Z') break :blk \"Lu\" else if (c >= '0' and c <= '9') break :blk \"Nd\" else if (c == ' ') break :blk \"Zs\" else break :blk \"Cn\";") },
    .{ "bidirectional", genCharFunc("blk", "\"\"", "if (c >= 'a' and c <= 'z') break :blk \"L\" else if (c >= 'A' and c <= 'Z') break :blk \"L\" else if (c >= '0' and c <= '9') break :blk \"EN\" else break :blk \"ON\";") },
    .{ "combining", h.I32(0) }, .{ "east_asian_width", h.c("\"N\"") },
    .{ "mirrored", h.I32(0) }, .{ "decomposition", h.c("\"\"") },
    .{ "normalize", genNormalize }, .{ "is_normalized", h.c("true") },
    .{ "unidata_version", h.c("\"15.0.0\"") }, .{ "ucd_3_2_0", h.c(".{}") },
});

fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; _ = name; break :blk \"?\"; }");
}

fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const c = "); try self.genExpr(args[0]); try self.emit("; _ = c; break :blk \"UNKNOWN\"; }");
}

fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("\"\"");
}
