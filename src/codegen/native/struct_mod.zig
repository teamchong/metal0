/// Python struct module - pack, unpack, calcsize
/// Converts between Python values and C structs as byte strings
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Helper to emit a number
fn emitNum(self: *NativeCodegen, n: usize) CodegenError!void {
    var buf: [20]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{n}) catch return;
    try self.emit(slice);
}

/// Generate struct.pack(format, v1, v2, ...) -> bytes
/// Packs values into a byte string according to the format
pub fn genPack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;

    try self.emit("struct_pack_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _buf: [1024]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("var _pos: usize = 0;\n");

    // Pack each value according to format
    for (args[1..], 0..) |arg, i| {
        try self.emitIndent();
        try self.emit("const _val");
        try emitNum(self, i);
        try self.emit(" = ");
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("if (@TypeOf(_val");
        try emitNum(self, i);
        try self.emit(") == i32 or @TypeOf(_val");
        try emitNum(self, i);
        try self.emit(") == i64) {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _bytes = std.mem.asBytes(&_val");
        try emitNum(self, i);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("@memcpy(_buf[_pos..][0.._bytes.len], _bytes);\n");
        try self.emitIndent();
        try self.emit("_pos += _bytes.len;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.emit("_ = _fmt;\n");
    try self.emitIndent();
    try self.emit("break :struct_pack_blk _buf[0.._pos];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate struct.unpack(format, buffer) -> tuple
/// Unpacks buffer according to format
pub fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("struct_unpack_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _fmt;\n");
    try self.emitIndent();
    // Return first value as simple case (i32)
    try self.emit("const _val = std.mem.bytesToValue(i32, _data[0..4]);\n");
    try self.emitIndent();
    try self.emit("break :struct_unpack_blk .{_val};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate struct.calcsize(format) -> int
/// Returns size in bytes of the struct described by format
pub fn genCalcsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("struct_calcsize_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _size: usize = 0;\n");
    try self.emitIndent();
    try self.emit("for (_fmt) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_size += switch (c) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("'b', 'B', 'c', '?', 'x' => 1,\n");
    try self.emitIndent();
    try self.emit("'h', 'H' => 2,\n");
    try self.emitIndent();
    try self.emit("'i', 'I', 'l', 'L', 'f' => 4,\n");
    try self.emitIndent();
    try self.emit("'q', 'Q', 'd' => 8,\n");
    try self.emitIndent();
    try self.emit("else => 0,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :struct_calcsize_blk @as(i64, @intCast(_size));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate struct.pack_into(format, buffer, offset, v1, v2, ...)
/// Pack values into buffer at offset
pub fn genPackInto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("struct_pack_into_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _offset: usize = @intCast(");
    try self.genExpr(args[2]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("_ = _fmt;\n");

    for (args[3..], 0..) |arg, i| {
        try self.emitIndent();
        try self.emit("const _val");
        try emitNum(self, i);
        try self.emit(" = ");
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _bytes");
        try emitNum(self, i);
        try self.emit(" = std.mem.asBytes(&_val");
        try emitNum(self, i);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("@memcpy(_buf[_offset..][0.._bytes");
        try emitNum(self, i);
        try self.emit(".len], _bytes");
        try emitNum(self, i);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("_offset += _bytes");
        try emitNum(self, i);
        try self.emit(".len;\n");
    }

    try self.emitIndent();
    try self.emit("break :struct_pack_into_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate struct.unpack_from(format, buffer, offset=0)
/// Unpack from buffer starting at offset
pub fn genUnpackFrom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("struct_unpack_from_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _offset: usize = ");
    if (args.len > 2) {
        try self.emit("@intCast(");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _fmt;\n");
    try self.emitIndent();
    try self.emit("const _val = std.mem.bytesToValue(i32, _data[_offset..][0..4]);\n");
    try self.emitIndent();
    try self.emit("break :struct_unpack_from_blk .{_val};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate struct.iter_unpack(format, buffer) -> iterator
/// Returns iterator that unpacks buffer repeatedly
pub fn genIterUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("struct_iter_unpack_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _fmt;\n");
    try self.emitIndent();
    try self.emit("_ = _data;\n");
    try self.emitIndent();
    // Returns a simple iterator struct
    try self.emit("break :struct_iter_unpack_blk struct { items: []const u8, pos: usize = 0, pub fn next(self: *@This()) ?i32 { if (self.pos + 4 <= self.items.len) { const val = std.mem.bytesToValue(i32, self.items[self.pos..][0..4]); self.pos += 4; return val; } return null; } }{ .items = _data };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
