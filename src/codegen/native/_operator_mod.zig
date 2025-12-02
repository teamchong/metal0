/// Python _operator module - C accelerator for operator (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "itemgetter", genItemgetter }, .{ "attrgetter", genAttrgetter }, .{ "methodcaller", genMethodcaller },
    .{ "lt", genLt }, .{ "le", genLe }, .{ "eq", genEq }, .{ "ne", genNe }, .{ "ge", genGe }, .{ "gt", genGt },
    .{ "add", genAdd }, .{ "sub", genSub }, .{ "mul", genMul }, .{ "truediv", genTruediv },
    .{ "floordiv", genFloordiv }, .{ "mod", genMod }, .{ "neg", genNeg }, .{ "pos", genPos }, .{ "abs", genAbs },
    .{ "and_", genAnd_ }, .{ "or_", genOr_ }, .{ "xor", genXor }, .{ "invert", genInvert },
    .{ "lshift", genLshift }, .{ "rshift", genRshift }, .{ "not_", genNot_ }, .{ "truth", genTruth },
    .{ "concat", genConcat }, .{ "contains", genContains }, .{ "countOf", genCountOf }, .{ "indexOf", genIndexOf },
    .{ "getitem", genGetitem }, .{ "length_hint", genLength_hint }, .{ "is_", genIs_ }, .{ "is_not", genIs_not },
    .{ "index", genIndex },
});

// Helpers
fn genGetter(self: *NativeCodegen, args: []ast.Node, field: []const u8, default: []const u8) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const "); try self.emit(field); try self.emit(" = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ ."); try self.emit(field); try self.emit(" = "); try self.emit(field); try self.emit(" }; }"); }
    else { try self.emit(".{ ."); try self.emit(field); try self.emit(" = "); try self.emit(default); try self.emit(" }"); }
}
fn genBinOp(self: *NativeCodegen, args: []ast.Node, op: []const u8, default: []const u8) CodegenError!void {
    if (args.len >= 2) { try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(default);
}
fn genBinFunc(self: *NativeCodegen, args: []ast.Node, func: []const u8, default: []const u8) CodegenError!void {
    if (args.len >= 2) { try self.emit(func); try self.emit("("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(default);
}
fn genUnaryOp(self: *NativeCodegen, args: []ast.Node, prefix: []const u8, suffix: []const u8, default: []const u8) CodegenError!void {
    if (args.len > 0) { try self.emit(prefix); try self.genExpr(args[0]); try self.emit(suffix); } else try self.emit(default);
}
fn genShift(self: *NativeCodegen, args: []ast.Node, op: []const u8) CodegenError!void {
    if (args.len >= 2) { try self.emit("("); try self.genExpr(args[0]); try self.emit(op); try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("0");
}

// Getters
pub fn genItemgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genGetter(self, args, "key", "0"); }
pub fn genAttrgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genGetter(self, args, "attr", "\"\""); }
pub fn genMethodcaller(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genGetter(self, args, "name", "\"\""); }

// Comparison
pub fn genLt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " < ", "false"); }
pub fn genLe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " <= ", "false"); }
pub fn genEq(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " == ", "false"); }
pub fn genNe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " != ", "true"); }
pub fn genGe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " >= ", "false"); }
pub fn genGt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " > ", "false"); }

// Arithmetic
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " + ", "0"); }
pub fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " - ", "0"); }
pub fn genMul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " * ", "0"); }
pub fn genTruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit(")) / @as(f64, @floatFromInt("); try self.genExpr(args[1]); try self.emit(")))"); } else try self.emit("0.0");
}
pub fn genFloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinFunc(self, args, "@divFloor", "0"); }
pub fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinFunc(self, args, "@mod", "0"); }
pub fn genNeg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "-(", ")", "0"); }
pub fn genPos(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "+(", ")", "0"); }
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "@abs(", ")", "0"); }

// Bitwise
pub fn genAnd_(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " & ", "0"); }
pub fn genOr_(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " | ", "0"); }
pub fn genXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genBinOp(self, args, " ^ ", "0"); }
pub fn genInvert(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "~(", ")", "-1"); }
pub fn genLshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genShift(self, args, " << "); }
pub fn genRshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genShift(self, args, " >> "); }

// Logical
pub fn genNot_(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "!(", ")", "true"); }
pub fn genTruth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const v = "); try self.genExpr(args[0]); try self.emit("; break :blk v != 0 and v != false; }"); } else try self.emit("false");
}

// Sequence
pub fn genConcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { var result = std.ArrayList(@TypeOf("); try self.genExpr(args[0]); try self.emit("[0])).init(__global_allocator); result.appendSlice("); try self.genExpr(args[0]); try self.emit(") catch {}; result.appendSlice("); try self.genExpr(args[1]); try self.emit(") catch {}; break :blk result.items; }"); } else try self.emit("&[_]u8{}");
}
pub fn genContains(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const item = "); try self.genExpr(args[1]); try self.emit("; for (seq) |elem| { if (elem == item) break :blk true; } break :blk false; }"); } else try self.emit("false");
}
pub fn genCountOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const item = "); try self.genExpr(args[1]); try self.emit("; var count: i64 = 0; for (seq) |elem| { if (elem == item) count += 1; } break :blk count; }"); } else try self.emit("@as(i64, 0)");
}
pub fn genIndexOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const seq = "); try self.genExpr(args[0]); try self.emit("; const item = "); try self.genExpr(args[1]); try self.emit("; for (seq, 0..) |elem, i| { if (elem == item) break :blk @as(i64, @intCast(i)); } break :blk @as(i64, -1); }"); } else try self.emit("@as(i64, -1)");
}
pub fn genGetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.genExpr(args[0]); try self.emit("[@intCast("); try self.genExpr(args[1]); try self.emit(")]"); } else try self.emit("null");
}
pub fn genLength_hint(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "", ".len", "@as(usize, 0)"); }

// Identity
pub fn genIs_(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("(@intFromPtr(&"); try self.genExpr(args[0]); try self.emit(") == @intFromPtr(&"); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("false");
}
pub fn genIs_not(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("(@intFromPtr(&"); try self.genExpr(args[0]); try self.emit(") != @intFromPtr(&"); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("true");
}
pub fn genIndex(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genUnaryOp(self, args, "@as(i64, @intCast(", "))", "@as(i64, 0)"); }
