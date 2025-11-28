/// Python operator module - Standard operators as functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate operator.add(a, b) -> a + b
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" + ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.sub(a, b) -> a - b
pub fn genSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" - ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.mul(a, b) -> a * b
pub fn genMul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" * ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.truediv(a, b) -> a / b
pub fn genTruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    try self.emit("(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit(")) / @as(f64, @floatFromInt(");
    try self.genExpr(args[1]);
    try self.emit(")))");
}

/// Generate operator.floordiv(a, b) -> a // b
pub fn genFloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("@divFloor(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.mod(a, b) -> a % b
pub fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("@mod(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.pow(a, b) -> a ** b
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 1)");
        return;
    }
    try self.emit("std.math.pow(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("), ");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.neg(a) -> -a
pub fn genNeg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(-");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate operator.pos(a) -> +a
pub fn genPos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate operator.abs(a) -> |a|
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("@abs(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate operator.invert(a) -> ~a
pub fn genInvert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(~");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate operator.lshift(a, b) -> a << b
pub fn genLshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" << @intCast(");
    try self.genExpr(args[1]);
    try self.emit("))");
}

/// Generate operator.rshift(a, b) -> a >> b
pub fn genRshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" >> @intCast(");
    try self.genExpr(args[1]);
    try self.emit("))");
}

/// Generate operator.and_(a, b) -> a & b
pub fn genAnd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" & ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.or_(a, b) -> a | b
pub fn genOr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" | ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.xor(a, b) -> a ^ b
pub fn genXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" ^ ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.not_(a) -> not a
pub fn genNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("true");
        return;
    }
    try self.emit("!");
    try self.genExpr(args[0]);
}

/// Generate operator.truth(a) -> bool(a)
pub fn genTruth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" != 0)");
}

/// Generate operator.eq(a, b) -> a == b
pub fn genEq(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" == ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.ne(a, b) -> a != b
pub fn genNe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("true");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" != ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.lt(a, b) -> a < b
pub fn genLt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" < ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.le(a, b) -> a <= b
pub fn genLe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" <= ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.gt(a, b) -> a > b
pub fn genGt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" > ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.ge(a, b) -> a >= b
pub fn genGe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" >= ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.is_(a, b) -> a is b
pub fn genIs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }
    try self.emit("(&");
    try self.genExpr(args[0]);
    try self.emit(" == &");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.is_not(a, b) -> a is not b
pub fn genIsNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("true");
        return;
    }
    try self.emit("(&");
    try self.genExpr(args[0]);
    try self.emit(" != &");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate operator.concat(a, b) -> a + b (sequences)
pub fn genConcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("&[_]u8{}");
        return;
    }
    try genAdd(self, args);
}

/// Generate operator.contains(a, b) -> b in a
pub fn genContains(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate operator.countOf(a, b) -> count of b in a
pub fn genCountOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate operator.indexOf(a, b) -> index of b in a
pub fn genIndexOf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -1)");
}

/// Generate operator.getitem(a, b) -> a[b]
pub fn genGetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.genExpr(args[0]);
    try self.emit("[");
    try self.genExpr(args[1]);
    try self.emit("]");
}

/// Generate operator.setitem(a, b, c) -> a[b] = c
pub fn genSetitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;
    try self.genExpr(args[0]);
    try self.emit("[");
    try self.genExpr(args[1]);
    try self.emit("] = ");
    try self.genExpr(args[2]);
}

/// Generate operator.delitem(a, b) -> del a[b]
pub fn genDelitem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate operator.length_hint(obj, default=0) -> length hint
pub fn genLengthHint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate operator.attrgetter(attr) -> callable
pub fn genAttrgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("attr: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn __call__(self: @This(), obj: anytype) []const u8 { _ = self; _ = obj; return \"\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate operator.itemgetter(item) -> callable
pub fn genItemgetter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("item: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn __call__(self: @This(), obj: anytype) @TypeOf(obj[0]) { return obj[@intCast(self.item)]; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate operator.methodcaller(name, *args) -> callable
pub fn genMethodcaller(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn __call__(self: @This(), obj: anytype) void { _ = self; _ = obj; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate operator.matmul(a, b) -> a @ b
pub fn genMatmul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMul(self, args);
}

/// Generate operator.index(a) -> a.__index__()
pub fn genIndex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.genExpr(args[0]);
}

// In-place operators (iadd, isub, etc.) - return modified value

/// Generate operator.iadd(a, b) -> a += b
pub fn genIadd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genAdd(self, args);
}

/// Generate operator.isub(a, b) -> a -= b
pub fn genIsub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genSub(self, args);
}

/// Generate operator.imul(a, b) -> a *= b
pub fn genImul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMul(self, args);
}

/// Generate operator.itruediv(a, b) -> a /= b
pub fn genItruediv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genTruediv(self, args);
}

/// Generate operator.ifloordiv(a, b) -> a //= b
pub fn genIfloordiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genFloordiv(self, args);
}

/// Generate operator.imod(a, b) -> a %= b
pub fn genImod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMod(self, args);
}

/// Generate operator.ipow(a, b) -> a **= b
pub fn genIpow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genPow(self, args);
}

/// Generate operator.ilshift(a, b) -> a <<= b
pub fn genIlshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genLshift(self, args);
}

/// Generate operator.irshift(a, b) -> a >>= b
pub fn genIrshift(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genRshift(self, args);
}

/// Generate operator.iand(a, b) -> a &= b
pub fn genIand(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genAnd(self, args);
}

/// Generate operator.ior(a, b) -> a |= b
pub fn genIor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOr(self, args);
}

/// Generate operator.ixor(a, b) -> a ^= b
pub fn genIxor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genXor(self, args);
}

/// Generate operator.iconcat(a, b) -> a += b (sequences)
pub fn genIconcat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConcat(self, args);
}

/// Generate operator.imatmul(a, b) -> a @= b
pub fn genImatmul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMatmul(self, args);
}

/// Generate operator.call(obj, *args, **kwargs) -> obj(*args, **kwargs)
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("void{}");
        return;
    }
    try self.genExpr(args[0]);
    try self.emit("()");
}
