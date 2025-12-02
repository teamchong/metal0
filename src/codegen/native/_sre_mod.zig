/// Python _sre module - Internal SRE support (C accelerator for regex)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genCompile }, .{ "c_o_d_e_s_i_z_e", genConst("@as(i32, 4)") }, .{ "m_a_g_i_c", genConst("@as(i32, 20171005)") },
    .{ "getlower", genGetlower }, .{ "getcodesize", genConst("@as(i32, 4)") },
    .{ "match", genConst("null") }, .{ "fullmatch", genConst("null") }, .{ "search", genConst("null") },
    .{ "findall", genConst("&[_][]const u8{}") }, .{ "finditer", genConst("&[_]@TypeOf(null){}") },
    .{ "sub", genSub }, .{ "subn", genSubn }, .{ "split", genConst("&[_][]const u8{}") },
    .{ "group", genConst("\"\"") }, .{ "groups", genConst(".{}") }, .{ "groupdict", genConst(".{}") },
    .{ "start", genConst("@as(i64, 0)") }, .{ "end", genConst("@as(i64, 0)") }, .{ "span", genConst(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "expand", genConst("\"\"") },
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
