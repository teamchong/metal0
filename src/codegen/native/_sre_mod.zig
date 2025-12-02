/// Python _sre module - Internal SRE support (C accelerator for regex)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genCompile }, .{ "c_o_d_e_s_i_z_e", genI32_4 }, .{ "m_a_g_i_c", genMagic }, .{ "getlower", genGetlower }, .{ "getcodesize", genI32_4 },
    .{ "match", genNull }, .{ "fullmatch", genNull }, .{ "search", genNull }, .{ "findall", genStrArr }, .{ "finditer", genNullArr },
    .{ "sub", genSub }, .{ "subn", genSubn }, .{ "split", genStrArr }, .{ "group", genEmptyStr }, .{ "groups", genEmpty }, .{ "groupdict", genEmpty },
    .{ "start", genI64_0 }, .{ "end", genI64_0 }, .{ "span", genSpan }, .{ "expand", genEmptyStr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genStrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genNullArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(null){}"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 20171005)"); }
fn genSpan(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i64, 0), @as(i64, 0) }"); }

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
