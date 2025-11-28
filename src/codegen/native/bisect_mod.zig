/// Python bisect module - Array bisection algorithms
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate bisect.bisect_left(a, x, lo=0, hi=len(a)) -> index
pub fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(usize, 0)");
        return;
    }

    try self.emit("bisect_left_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _a = ");
    try self.genExpr(args[0]);
    try self.emit(".items;\n");
    try self.emitIndent();
    try self.emit("const _x = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _lo: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _hi: usize = _a.len;\n");
    try self.emitIndent();
    try self.emit("while (_lo < _hi) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _mid = _lo + (_hi - _lo) / 2;\n");
    try self.emitIndent();
    try self.emit("if (_a[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :bisect_left_blk _lo;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate bisect.bisect_right(a, x, lo=0, hi=len(a)) -> index (alias: bisect)
pub fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(usize, 0)");
        return;
    }

    try self.emit("bisect_right_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _a = ");
    try self.genExpr(args[0]);
    try self.emit(".items;\n");
    try self.emitIndent();
    try self.emit("const _x = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _lo: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _hi: usize = _a.len;\n");
    try self.emitIndent();
    try self.emit("while (_lo < _hi) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _mid = _lo + (_hi - _lo) / 2;\n");
    try self.emitIndent();
    try self.emit("if (_x < _a[_mid]) { _hi = _mid; } else { _lo = _mid + 1; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :bisect_right_blk _lo;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate bisect.bisect(a, x, lo=0, hi=len(a)) -> index (alias for bisect_right)
pub fn genBisect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genBisectRight(self, args);
}

/// Generate bisect.insort_left(a, x, lo=0, hi=len(a)) -> None
pub fn genInsortLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("insort_left_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _a = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _x = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _lo: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _hi: usize = _a.items.len;\n");
    try self.emitIndent();
    try self.emit("while (_lo < _hi) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _mid = _lo + (_hi - _lo) / 2;\n");
    try self.emitIndent();
    try self.emit("if (_a.items[_mid] < _x) { _lo = _mid + 1; } else { _hi = _mid; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_a.insert(allocator, _lo, _x) catch {};\n");
    try self.emitIndent();
    try self.emit("break :insort_left_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate bisect.insort_right(a, x, lo=0, hi=len(a)) -> None (alias: insort)
pub fn genInsortRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("insort_right_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _a = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _x = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _lo: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _hi: usize = _a.items.len;\n");
    try self.emitIndent();
    try self.emit("while (_lo < _hi) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _mid = _lo + (_hi - _lo) / 2;\n");
    try self.emitIndent();
    try self.emit("if (_x < _a.items[_mid]) { _hi = _mid; } else { _lo = _mid + 1; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_a.insert(allocator, _lo, _x) catch {};\n");
    try self.emitIndent();
    try self.emit("break :insort_right_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate bisect.insort(a, x, lo=0, hi=len(a)) -> None (alias for insort_right)
pub fn genInsort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genInsortRight(self, args);
}
