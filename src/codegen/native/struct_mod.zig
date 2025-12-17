/// Python struct module - pack, unpack, calcsize
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pack", genPack }, .{ "unpack", genUnpack }, .{ "calcsize", genCalcsize },
    .{ "pack_into", genPackInto }, .{ "unpack_from", genUnpackFrom }, .{ "iter_unpack", genIterUnpack },
});

fn emitNum(self: *NativeCodegen, n: usize) CodegenError!void {
    var buf: [20]u8 = undefined;
    try self.emit(std.fmt.bufPrint(&buf, "{d}", .{n}) catch return);
}

fn getFormatStr(arg: ast.Node) ?[]const u8 {
    return if (arg == .constant and arg.constant.value == .string) blk: {
        const s = arg.constant.value.string;
        break :blk if (s.len >= 2) s[1 .. s.len - 1] else s;
    } else null;
}

fn getPackType(c: u8) []const u8 {
    return switch (c) { 'f' => "f32", 'd' => "f64", 'h' => "i16", 'H' => "u16", 'b' => "i8", 'B' => "u8", 'I', 'L' => "u32", 'q' => "i64", 'Q' => "u64", else => "i32" };
}

fn getUnpackSize(c: u8) []const u8 {
    return switch (c) { 'f', 'I', 'L' => "4", 'd', 'q', 'Q' => "8", 'h', 'H' => "2", 'b', 'B' => "1", else => "4" };
}

fn getFmtOff(fmt: []const u8) usize {
    return if (fmt.len > 0 and (fmt[0] == '<' or fmt[0] == '>' or fmt[0] == '@' or fmt[0] == '=' or fmt[0] == '!')) 1 else 0;
}

pub fn genPack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        // struct.pack() with no args or only keyword args raises TypeError
        try self.emit("runtime.builtins.structPackNoArgs()");
        return;
    }
    const fmt_str = getFormatStr(args[0]);
    const fmt_off: usize = if (fmt_str) |f| getFmtOff(f) else 0;
    const pack_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_pack: {{ const _fmt = ", .{pack_id}); try self.genExpr(args[0]);
    try self.emit("; var _buf: [1024]u8 = undefined; var _pos: usize = 0; ");
    for (args[1..], 0..) |arg, i| {
        const fc: u8 = if (fmt_str) |f| (if (i + fmt_off < f.len) f[i + fmt_off] else 'i') else 'i';
        try self.emit("const _val"); try emitNum(self, i); try self.emit(": "); try self.emit(getPackType(fc));
        try self.emit(if (fc == 'f' or fc == 'd') " = @floatCast(" else " = runtime.packInt("); try self.genExpr(arg);
        try self.emit("); const _bytes"); try emitNum(self, i); try self.emit(" = std.mem.asBytes(&_val"); try emitNum(self, i);
        try self.emit("); @memcpy(_buf[_pos..][0.._bytes"); try emitNum(self, i); try self.emit(".len], _bytes"); try emitNum(self, i);
        try self.emit("); _pos += _bytes"); try emitNum(self, i); try self.emit(".len; ");
    }
    try self.emitFmt("_ = _fmt; break :__m{d}_struct_pack _buf[0.._pos]; }}", .{pack_id});
}

pub fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    const fmt_str = getFormatStr(args[0]);
    const unpack_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_unpack: {{ const _fmt = ", .{unpack_id}); try self.genExpr(args[0]);
    try self.emit("; const _raw_data = "); try self.genExpr(args[1]);
    // Handle PyBytes (has .data field) vs raw slice
    try self.emit("; const _data = if (@TypeOf(_raw_data) == runtime.builtins.PyBytes) _raw_data.data else _raw_data; _ = _fmt; ");
    if (fmt_str) |fmt| {
        try self.emit("var _pos: usize = 0; ");
        for (fmt, 0..) |c, i| {
            const ty = getPackType(c);
            try self.emit("const _val"); try emitNum(self, i);
            if (c == 'f' or c == 'd') {
                try self.emit(": "); try self.emit(ty); try self.emit(" = std.mem.bytesToValue("); try self.emit(ty);
            } else {
                try self.emit(": i64 = @intCast(std.mem.bytesToValue("); try self.emit(ty);
            }
            try self.emit(", _data[_pos..][0.."); try self.emit(getUnpackSize(c)); try self.emit("])); _pos += "); try self.emit(getUnpackSize(c)); try self.emit("; ");
        }
        try self.emitFmt("break :__m{d}_struct_unpack .{{", .{unpack_id});
        for (0..fmt.len) |i| { if (i > 0) try self.emit(", "); try self.emit("_val"); try emitNum(self, i); }
        try self.emit("}; }");
    } else try self.emitFmt("const _val = std.mem.bytesToValue(i32, _data[0..4]); break :__m{d}_struct_unpack .{{_val}}; }}", .{unpack_id});
}

// struct.calcsize: handle both []const u8 and PyValue (from generators)
pub fn genCalcsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    const calcsize_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_calcsize: {{ const _raw_fmt = ", .{calcsize_id});
    try self.genExpr(args[0]);
    try self.emitFmt("; const _fmt = if (@TypeOf(_raw_fmt) == runtime.PyValue) _raw_fmt.asString() else _raw_fmt; var _size: usize = 0; for (_fmt) |c| {{ _size += switch (c) {{ 'b', 'B', 'c', '?', 'x' => 1, 'h', 'H' => 2, 'i', 'I', 'l', 'L', 'f' => 4, 'q', 'Q', 'd' => 8, else => 0 }}; }} break :__m{d}_struct_calcsize @as(i64, @intCast(_size)); }}", .{calcsize_id});
}

fn genPackInto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        // struct.pack_into() with insufficient args raises TypeError
        try self.emit("runtime.builtins.structPackIntoNoArgs()");
        return;
    }
    const pack_into_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_pack_into: {{ const _fmt = ", .{pack_into_id}); try self.genExpr(args[0]);
    try self.emit("; const _buf = "); try self.genExpr(args[1]);
    try self.emit("; var _offset: usize = @intCast("); try self.genExpr(args[2]); try self.emit("); _ = _fmt; ");
    for (args[3..], 0..) |arg, i| {
        try self.emit("const _val"); try emitNum(self, i); try self.emit(" = "); try self.genExpr(arg);
        try self.emit("; const _bytes"); try emitNum(self, i); try self.emit(" = std.mem.asBytes(&_val"); try emitNum(self, i);
        try self.emit("); @memcpy(_buf[_offset..][0.._bytes"); try emitNum(self, i); try self.emit(".len], _bytes"); try emitNum(self, i);
        try self.emit("); _offset += _bytes"); try emitNum(self, i); try self.emit(".len; ");
    }
    try self.emitFmt("break :__m{d}_struct_pack_into; }}", .{pack_into_id});
}

fn genUnpackFrom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    const unpack_from_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_unpack_from: {{ const _fmt = ", .{unpack_from_id}); try self.genExpr(args[0]);
    try self.emit("; const _data = "); try self.genExpr(args[1]); try self.emit("; const _offset: usize = ");
    if (args.len > 2) { try self.emit("@intCast("); try self.genExpr(args[2]); try self.emit(")"); } else try self.emit("0");
    try self.emitFmt("; _ = _fmt; const _val = std.mem.bytesToValue(i32, _data[_offset..][0..4]); break :__m{d}_struct_unpack_from .{{_val}}; }}", .{unpack_from_id});
}

fn genIterUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("struct { pub fn next(__self: *@This()) ?i32 { _ = __self; return null; } }{}");
        return;
    }
    const iter_unpack_id = self.nextNameId();
    try self.emitFmt("__m{d}_struct_iter_unpack: {{ const _fmt = ", .{iter_unpack_id});
    try self.genExpr(args[0]);
    try self.emit("; const _data = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; _ = _fmt; _ = _data; break :__m{d}_struct_iter_unpack struct {{ items: []const u8, pos: usize = 0, pub fn next(__self: *@This()) ?i32 {{ if (__self.pos + 4 <= __self.items.len) {{ const val = std.mem.bytesToValue(i32, __self.items[__self.pos..][0..4]); __self.pos += 4; return val; }} return null; }} }}{{ .items = _data }}; }}", .{iter_unpack_id});
}
