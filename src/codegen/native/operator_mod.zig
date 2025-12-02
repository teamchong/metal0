/// Python operator module - Standard operators as functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

// Helpers
fn genBinaryOp(self: *NativeCodegen, args: []ast.Node, op_name: []const u8, op: []const u8, default: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.Operator"); try self.emit(op_name); try self.emit("{})"); return; }
    if (args.len < 2) { try self.emit(default); return; }
    try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.genExpr(args[1]); try self.emit(")");
}
fn genUnaryOp(self: *NativeCodegen, args: []ast.Node, op_name: []const u8, prefix: []const u8, suffix: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.Operator"); try self.emit(op_name); try self.emit("{})"); return; }
    try self.emit(prefix); try self.genExpr(args[0]); try self.emit(suffix);
}
fn genShiftOp(self: *NativeCodegen, args: []ast.Node, op_name: []const u8, op: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.Operator"); try self.emit(op_name); try self.emit("{})"); return; }
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit("))");
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "add", genAdd }, .{ "sub", genSub }, .{ "mul", genMul }, .{ "truediv", genTruediv },
    .{ "floordiv", genFloordiv }, .{ "mod", genMod }, .{ "pow", genPow }, .{ "neg", genNeg },
    .{ "pos", genPos }, .{ "abs", genAbs }, .{ "invert", genInvert }, .{ "lshift", genLshift },
    .{ "rshift", genRshift }, .{ "and_", genAnd }, .{ "or_", genOr }, .{ "xor", genXor },
    .{ "not_", genNot }, .{ "truth", genTruth }, .{ "eq", genEq }, .{ "ne", genNe },
    .{ "lt", genLt }, .{ "le", genLe }, .{ "gt", genGt }, .{ "ge", genGe },
    .{ "is_", genIs }, .{ "is_not", genIsNot }, .{ "concat", genConcat }, .{ "contains", genContains },
    .{ "countOf", genCountOf }, .{ "indexOf", genIndexOf }, .{ "getitem", genGetitem },
    .{ "setitem", genSetitem }, .{ "delitem", genDelitem }, .{ "length_hint", genLengthHint },
    .{ "attrgetter", genAttrgetter }, .{ "itemgetter", genItemgetter }, .{ "methodcaller", genMethodcaller },
    .{ "matmul", genMatmul }, .{ "index", genIndex }, .{ "iadd", genIadd }, .{ "isub", genIsub },
    .{ "imul", genImul }, .{ "itruediv", genItruediv }, .{ "ifloordiv", genIfloordiv },
    .{ "imod", genImod }, .{ "ipow", genIpow }, .{ "ilshift", genIlshift }, .{ "irshift", genIrshift },
    .{ "iand", genIand }, .{ "ior", genIor }, .{ "ixor", genIxor }, .{ "iconcat", genIconcat },
    .{ "imatmul", genImatmul }, .{ "__call__", genCall },
});

// Arithmetic
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Add", " + ", "@as(i64, 0)"); }
pub fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Sub", " - ", "@as(i64, 0)"); }
pub fn genMul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Mul", " * ", "@as(i64, 0)"); }
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

// Unary
pub fn genNeg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "Neg", "(-", ")"); }
pub fn genPos(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "Pos", "", ""); }
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "Abs", "@abs(", ")"); }
pub fn genInvert(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "Invert", "(~@as(i64, ", "))"); }

// Bitwise
pub fn genLshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genShiftOp(self, args, "Lshift", " << "); }
pub fn genRshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genShiftOp(self, args, "Rshift", " >> "); }
pub fn genAnd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "And", " & ", "@as(i64, 0)"); }
pub fn genOr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Or", " | ", "@as(i64, 0)"); }
pub fn genXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Xor", " ^ ", "@as(i64, 0)"); }

// Logical
pub fn genNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("true"); return; }
    try self.emit("(!(runtime.toBool("); try self.genExpr(args[0]); try self.emit(")))");
}
pub fn genTruth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    try self.emit("runtime.toBool("); try self.genExpr(args[0]); try self.emit(")");
}

// Comparison
pub fn genEq(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Eq", " == ", "false"); }
pub fn genNe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Ne", " != ", "true"); }
pub fn genLt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Lt", " < ", "false"); }
pub fn genLe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Le", " <= ", "false"); }
pub fn genGt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Gt", " > ", "false"); }
pub fn genGe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinaryOp(self, args, "Ge", " >= ", "false"); }

// Identity
pub fn genIs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("false"); return; }
    const a0_bool = args[0] == .constant and args[0].constant.value == .bool;
    const a1_bool = args[1] == .constant and args[1].constant.value == .bool;
    if (a0_bool and a1_bool) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" == "); try self.genExpr(args[1]); try self.emit(")"); }
    else { try self.emit("(&"); try self.genExpr(args[0]); try self.emit(" == &"); try self.genExpr(args[1]); try self.emit(")"); }
}
pub fn genIsNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("true"); return; }
    const a0_bool = args[0] == .constant and args[0].constant.value == .bool;
    const a1_bool = args[1] == .constant and args[1].constant.value == .bool;
    if (a0_bool and a1_bool) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" != "); try self.genExpr(args[1]); try self.emit(")"); }
    else { try self.emit("(&"); try self.genExpr(args[0]); try self.emit(" != &"); try self.genExpr(args[1]); try self.emit(")"); }
}

// Sequence
pub fn genConcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("(runtime.builtins.OperatorConcat{})"); return; }
    if (args.len < 2) { try self.emit("&[_]u8{}"); return; }
    try genAdd(self, args);
}
pub fn genContains(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("false"); return; }
    try self.emit("runtime.containsGeneric("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
pub fn genCountOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("@as(i64, 0)"); }
pub fn genIndexOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("@as(i64, -1)"); }

// Item access
pub fn genGetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.genExpr(args[0]); try self.emit("["); try self.genExpr(args[1]); try self.emit("]");
}
pub fn genSetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit("null"); return; }
    try self.emit("blk: { "); try self.genExpr(args[0]); try self.emit("["); try self.genExpr(args[1]); try self.emit("] = "); try self.genExpr(args[2]); try self.emit("; break :blk null; }");
}
pub fn genDelitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("null"); }
pub fn genLengthHint(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("@as(i64, 0)"); }

// Getters
pub fn genAttrgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { attr: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) []const u8 { _ = obj; return \"\"; } }{}");
}
pub fn genItemgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { item: i64 = 0, pub fn __call__(__self: @This(), obj: anytype) @TypeOf(obj[0]) { return obj[@intCast(__self.item)]; } }{}");
}
pub fn genMethodcaller(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { name: []const u8 = \"\", pub fn __call__(self: @This(), obj: anytype) void { _ = obj; } }{}");
}

// Others
pub fn genMatmul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMul(self, args); }
pub fn genIndex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    try self.genExpr(args[0]);
}

// In-place operators
pub fn genIadd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genAdd(self, args); }
pub fn genIsub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genSub(self, args); }
pub fn genImul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMul(self, args); }
pub fn genItruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genTruediv(self, args); }
pub fn genIfloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genFloordiv(self, args); }
pub fn genImod(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMod(self, args); }
pub fn genIpow(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genPow(self, args); }
pub fn genIlshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLshift(self, args); }
pub fn genIrshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genRshift(self, args); }
pub fn genIand(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genAnd(self, args); }
pub fn genIor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genOr(self, args); }
pub fn genIxor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genXor(self, args); }
pub fn genIconcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConcat(self, args); }
pub fn genImatmul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genMatmul(self, args); }

pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    try self.genExpr(args[0]); try self.emit("()");
}
