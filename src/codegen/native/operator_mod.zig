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
    .{ "not_", h.wrap("(!(runtime.toBool(", ")))", "true") },
    .{ "truth", h.wrap("runtime.toBool(", ")", "false") },
    // Comparison
    .{ "eq", h.binop(" == ", "false") }, .{ "ne", h.binop(" != ", "true") },
    .{ "lt", h.binop(" < ", "false") }, .{ "le", h.binop(" <= ", "false") },
    .{ "gt", h.binop(" > ", "false") }, .{ "ge", h.binop(" >= ", "false") },
    // Identity
    .{ "is_", genIs }, .{ "is_not", genIsNot },
    // Sequence
    .{ "concat", h.binop(" + ", "&[_]u8{}") },
    .{ "contains", h.wrap2("runtime.containsGeneric(", ", ", ")", "false") },
    .{ "countOf", h.I64(0) }, .{ "indexOf", h.I64(-1) },
    // Item
    .{ "getitem", h.wrap2("", "[", "]", "@as(i64, 0)") }, .{ "setitem", h.wrap3("blk: { ", "[", "] = ", "; break :blk null; }", "null") },
    .{ "delitem", h.c("null") }, .{ "length_hint", h.I64(0) },
    // Getters
    .{ "attrgetter", h.c("struct { attr: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) []const u8 { _ = obj; return \"\"; } }{}") },
    .{ "itemgetter", h.c("struct { item: i64 = 0, pub fn __call__(__self: @This(), obj: anytype) @TypeOf(obj[0]) { return obj[@intCast(__self.item)]; } }{}") },
    .{ "methodcaller", h.c("struct { name: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) void { _ = obj; } }{}") },
    // Index
    .{ "index", h.pass("@as(i64, 0)") },
    // In-place (same as regular)
    .{ "iadd", h.binop(" + ", "@as(i64, 0)") }, .{ "isub", h.binop(" - ", "@as(i64, 0)") },
    .{ "imul", h.binop(" * ", "@as(i64, 0)") }, .{ "itruediv", genTruediv }, .{ "ifloordiv", genFloordiv },
    .{ "imod", genMod }, .{ "ipow", genPow }, .{ "ilshift", h.shift(" << ") }, .{ "irshift", h.shift(" >> ") },
    .{ "iand", h.binop(" & ", "@as(i64, 0)") }, .{ "ior", h.binop(" | ", "@as(i64, 0)") },
    .{ "ixor", h.binop(" ^ ", "@as(i64, 0)") }, .{ "iconcat", h.binop(" + ", "&[_]u8{}") }, .{ "imatmul", h.binop(" * ", "@as(i64, 0)") },
    .{ "__call__", h.wrap("", "()", "void{}") },
});

fn divOp(self: *NativeCodegen, args: []ast.Node, comptime builtin: []const u8, comptime default: []const u8, comptime pre: []const u8, comptime mid: []const u8, comptime suf: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit(builtin); return; }
    if (args.len < 2) { try self.emit(default); return; }
    try self.emit(pre); try self.genExpr(args[0]); try self.emit(mid); try self.genExpr(args[1]); try self.emit(suf);
}
fn genTruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try divOp(self, args, "(runtime.builtins.OperatorTruediv{})", "@as(f64, 0.0)", "(@as(f64, @floatFromInt(", ")) / @as(f64, @floatFromInt(", ")))");
}
fn genFloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try divOp(self, args, "(runtime.builtins.OperatorFloordiv{})", "@as(i64, 0)", "@divFloor(", ", ", ")");
}
fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try divOp(self, args, "(runtime.builtins.OperatorMod{})", "@as(i64, 0)", "@mod(", ", ", ")");
}
fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try divOp(self, args, "runtime.builtins.OperatorPow{}", "@as(i64, 1)", "(std.math.powi(i64, @as(i64, ", "), @as(u32, @intCast(", "))) catch 0)");
}
fn genIdentity(self: *NativeCodegen, args: []ast.Node, comptime op: []const u8, comptime default: []const u8) CodegenError!void {
    if (args.len < 2) { try self.emit(default); return; }
    const both_bool = (args[0] == .constant and args[0].constant.value == .bool) and (args[1] == .constant and args[1].constant.value == .bool);
    try self.emit(if (both_bool) "(" else "(&"); try self.genExpr(args[0]); try self.emit(op); try self.emit(if (both_bool) "" else "&"); try self.genExpr(args[1]); try self.emit(")");
}
fn genIs(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genIdentity(self, args, " == ", "false"); }
fn genIsNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genIdentity(self, args, " != ", "true"); }
