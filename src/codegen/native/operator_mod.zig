/// Python operator module - Standard operators as functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Arithmetic
    .{ "add", h.binop(" + ", "@as(i64, 0)") }, .{ "sub", h.binop(" - ", "@as(i64, 0)") },
    .{ "mul", h.binop(" * ", "@as(i64, 0)") }, .{ "truediv", genTruediv }, .{ "floordiv", genFloordiv },
    .{ "mod", genMod }, .{ "pow", genPow }, .{ "matmul", h.binop(" * ", "@as(i64, 0)") },
    // Unary
    .{ "neg", h.unary("(-", ")") }, .{ "pos", h.unary("", "") },
    .{ "abs", h.unary("@abs(", ")") }, .{ "invert", h.unary("(~@as(i64, ", "))") },
    // Bitwise
    .{ "lshift", h.shift(" << ") }, .{ "rshift", h.shift(" >> ") },
    .{ "and_", h.binop(" & ", "@as(i64, 0)") }, .{ "or_", h.binop(" | ", "@as(i64, 0)") },
    .{ "xor", h.binop(" ^ ", "@as(i64, 0)") },
    // Logical
    .{ "not_", genNot }, .{ "truth", genTruth },
    // Comparison
    .{ "eq", h.binop(" == ", "false") }, .{ "ne", h.binop(" != ", "true") },
    .{ "lt", h.binop(" < ", "false") }, .{ "le", h.binop(" <= ", "false") },
    .{ "gt", h.binop(" > ", "false") }, .{ "ge", h.binop(" >= ", "false") },
    // Identity
    .{ "is_", genIs }, .{ "is_not", genIsNot },
    // Sequence
    .{ "concat", genConcat }, .{ "contains", genContains },
    .{ "countOf", h.I64(0) }, .{ "indexOf", h.I64(-1) },
    // Item
    .{ "getitem", genGetitem }, .{ "setitem", genSetitem },
    .{ "delitem", h.c("null") }, .{ "length_hint", h.I64(0) },
    // Getters
    .{ "attrgetter", h.c("struct { attr: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) []const u8 { _ = obj; return \"\"; } }{}") },
    .{ "itemgetter", h.c("struct { item: i64 = 0, pub fn __call__(__self: @This(), obj: anytype) @TypeOf(obj[0]) { return obj[@intCast(__self.item)]; } }{}") },
    .{ "methodcaller", h.c("struct { name: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) void { _ = obj; } }{}") },
    // Index
    .{ "index", genIndex },
    // In-place (same as regular)
    .{ "iadd", h.binop(" + ", "@as(i64, 0)") }, .{ "isub", h.binop(" - ", "@as(i64, 0)") },
    .{ "imul", h.binop(" * ", "@as(i64, 0)") }, .{ "itruediv", genTruediv }, .{ "ifloordiv", genFloordiv },
    .{ "imod", genMod }, .{ "ipow", genPow }, .{ "ilshift", h.shift(" << ") }, .{ "irshift", h.shift(" >> ") },
    .{ "iand", h.binop(" & ", "@as(i64, 0)") }, .{ "ior", h.binop(" | ", "@as(i64, 0)") },
    .{ "ixor", h.binop(" ^ ", "@as(i64, 0)") }, .{ "iconcat", genConcat }, .{ "imatmul", h.binop(" * ", "@as(i64, 0)") },
    .{ "__call__", genCall },
});

pub fn genTruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.OperatorTruediv{})"); return; }
    if (args.len < 2) { try self.emit("@as(f64, 0.0)"); return; }
    try self.emit("(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit(")) / @as(f64, @floatFromInt("); try self.genExpr(args[1]); try self.emit(")))");
}
pub fn genFloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.OperatorFloordiv{})"); return; }
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("@divFloor("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.OperatorMod{})"); return; }
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("@mod("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("runtime.builtins.OperatorPow{}"); return; }
    if (args.len < 2) { try self.emit("@as(i64, 1)"); return; }
    try self.emit("(std.math.powi(i64, @as(i64, "); try self.genExpr(args[0]); try self.emit("), @as(u32, @intCast("); try self.genExpr(args[1]); try self.emit("))) catch 0)");
}
pub fn genNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("true"); return; }
    try self.emit("(!(runtime.toBool("); try self.genExpr(args[0]); try self.emit(")))");
}
pub fn genTruth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    try self.emit("runtime.toBool("); try self.genExpr(args[0]); try self.emit(")");
}
pub fn genIs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("false"); return; }
    const both_bool = (args[0] == .constant and args[0].constant.value == .bool) and (args[1] == .constant and args[1].constant.value == .bool);
    try self.emit(if (both_bool) "(" else "(&"); try self.genExpr(args[0]); try self.emit(" == "); try self.emit(if (both_bool) "" else "&"); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genIsNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("true"); return; }
    const both_bool = (args[0] == .constant and args[0].constant.value == .bool) and (args[1] == .constant and args[1].constant.value == .bool);
    try self.emit(if (both_bool) "(" else "(&"); try self.genExpr(args[0]); try self.emit(" != "); try self.emit(if (both_bool) "" else "&"); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genConcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.OperatorConcat{})"); return; }
    if (args.len < 2) { try self.emit("&[_]u8{}"); return; }
    try self.emit("("); try self.genExpr(args[0]); try self.emit(" + "); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genContains(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("false"); return; }
    try self.emit("runtime.containsGeneric("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genGetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.genExpr(args[0]); try self.emit("["); try self.genExpr(args[1]); try self.emit("]");
}
pub fn genSetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit("null"); return; }
    try self.emit("blk: { "); try self.genExpr(args[0]); try self.emit("["); try self.genExpr(args[1]); try self.emit("] = "); try self.genExpr(args[2]); try self.emit("; break :blk null; }");
}
pub fn genIndex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    try self.genExpr(args[0]);
}
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    try self.genExpr(args[0]); try self.emit("()");
}
