/// Python unicodedata module - Unicode character database
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genCharFunc(comptime label: []const u8, comptime default: []const u8, comptime body: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(default); return; }
        try self.emit(label ++ ": { const c = "); try self.genExpr(args[0]); try self.emit("[0]; " ++ body ++ " }");
    } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "lookup", genLookup }, .{ "name", genName },
    .{ "decimal", genCharFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "digit", genCharFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "numeric", genCharFunc("blk", "@as(f64, -1.0)", "if (c >= '0' and c <= '9') break :blk @as(f64, @floatFromInt(c - '0')) else break :blk -1.0;") },
    .{ "category", genCharFunc("blk", "\"Cn\"", "if (c >= 'a' and c <= 'z') break :blk \"Ll\" else if (c >= 'A' and c <= 'Z') break :blk \"Lu\" else if (c >= '0' and c <= '9') break :blk \"Nd\" else if (c == ' ') break :blk \"Zs\" else break :blk \"Cn\";") },
    .{ "bidirectional", genCharFunc("blk", "\"\"", "if (c >= 'a' and c <= 'z') break :blk \"L\" else if (c >= 'A' and c <= 'Z') break :blk \"L\" else if (c >= '0' and c <= '9') break :blk \"EN\" else break :blk \"ON\";") },
    .{ "combining", genConst("@as(i32, 0)") }, .{ "east_asian_width", genConst("\"N\"") },
    .{ "mirrored", genConst("@as(i32, 0)") }, .{ "decomposition", genConst("\"\"") },
    .{ "normalize", genNormalize }, .{ "is_normalized", genConst("true") },
    .{ "unidata_version", genConst("\"15.0.0\"") }, .{ "ucd_3_2_0", genConst(".{}") },
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
