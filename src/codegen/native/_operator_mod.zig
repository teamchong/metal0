/// Python _operator module - C accelerator for operator (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _operator.itemgetter(*items)
pub fn genItemgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const key = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .key = key }; }");
    } else {
        try self.emit(".{ .key = 0 }");
    }
}

/// Generate _operator.attrgetter(*attrs)
pub fn genAttrgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const attr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .attr = attr }; }");
    } else {
        try self.emit(".{ .attr = \"\" }");
    }
}

/// Generate _operator.methodcaller(name, *args, **kwargs)
pub fn genMethodcaller(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name }; }");
    } else {
        try self.emit(".{ .name = \"\" }");
    }
}

// Comparison operations
pub fn genLt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" < ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

pub fn genLe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" <= ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

pub fn genEq(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" == ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

pub fn genNe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" != ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("true");
    }
}

pub fn genGe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" >= ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

pub fn genGt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" > ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

// Arithmetic operations
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" + ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" - ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genMul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" * ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genTruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(@as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit(")) / @as(f64, @floatFromInt(");
        try self.genExpr(args[1]);
        try self.emit(")))");
    } else {
        try self.emit("0.0");
    }
}

pub fn genFloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("@divFloor(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("@mod(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genNeg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("-(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genPos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("+(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@abs(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

// Bitwise operations
pub fn genAnd_(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" & ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genOr_(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" | ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" ^ ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

pub fn genInvert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("~(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("-1");
    }
}

pub fn genLshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" << @intCast(");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("0");
    }
}

pub fn genRshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" >> @intCast(");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("0");
    }
}

// Logical operations
pub fn genNot_(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("!(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("true");
    }
}

pub fn genTruth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const v = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk v != 0 and v != false; }");
    } else {
        try self.emit("false");
    }
}

// Sequence operations
pub fn genConcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { var result = std.ArrayList(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("[0])).init(__global_allocator); result.appendSlice(");
        try self.genExpr(args[0]);
        try self.emit(") catch {}; result.appendSlice(");
        try self.genExpr(args[1]);
        try self.emit(") catch {}; break :blk result.items; }");
    } else {
        try self.emit("&[_]u8{}");
    }
}

pub fn genContains(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const seq = ");
        try self.genExpr(args[0]);
        try self.emit("; const item = ");
        try self.genExpr(args[1]);
        try self.emit("; for (seq) |elem| { if (elem == item) break :blk true; } break :blk false; }");
    } else {
        try self.emit("false");
    }
}

pub fn genCountOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const seq = ");
        try self.genExpr(args[0]);
        try self.emit("; const item = ");
        try self.genExpr(args[1]);
        try self.emit("; var count: i64 = 0; for (seq) |elem| { if (elem == item) count += 1; } break :blk count; }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genIndexOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const seq = ");
        try self.genExpr(args[0]);
        try self.emit("; const item = ");
        try self.genExpr(args[1]);
        try self.emit("; for (seq, 0..) |elem, i| { if (elem == item) break :blk @as(i64, @intCast(i)); } break :blk @as(i64, -1); }");
    } else {
        try self.emit("@as(i64, -1)");
    }
}

pub fn genGetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.genExpr(args[0]);
        try self.emit("[@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")]");
    } else {
        try self.emit("null");
    }
}

pub fn genLength_hint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
        try self.emit(".len");
    } else {
        try self.emit("@as(usize, 0)");
    }
}

// Identity
pub fn genIs_(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(@intFromPtr(&");
        try self.genExpr(args[0]);
        try self.emit(") == @intFromPtr(&");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("false");
    }
}

pub fn genIs_not(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("(@intFromPtr(&");
        try self.genExpr(args[0]);
        try self.emit(") != @intFromPtr(&");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("true");
    }
}

pub fn genIndex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(i64, 0)");
    }
}
