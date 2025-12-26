/// Python struct module - pack, unpack, calcsize
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pack", genPack }, .{ "unpack", genUnpack }, .{ "calcsize", genCalcsize },
    .{ "pack_into", genPackInto }, .{ "unpack_from", genUnpackFrom }, .{ "iter_unpack", genIterUnpack },
});

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
    // For struct.pack, we need to emit the args inline since we iterate over them
    const label = try self.emitInlineBlockStart("struct_pack");
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit("; var _buf: [1024]u8 = undefined; var _pos: usize = 0; ");
    for (args[1..], 0..) |arg, i| {
        const fc: u8 = if (fmt_str) |f| (if (i + fmt_off < f.len) f[i + fmt_off] else 'i') else 'i';
        try self.emitFmt("const _val{d}: {s}{s}", .{ i, getPackType(fc), if (fc == 'f' or fc == 'd') " = @floatCast(" else " = runtime.packInt(" });
        try self.genExpr(arg);
        try self.emitFmt("); const _bytes{d} = std.mem.asBytes(&_val{d}); @memcpy(_buf[_pos..][0.._bytes{d}.len], _bytes{d}); _pos += _bytes{d}.len; ", .{ i, i, i, i, i });
    }
    try self.emitFmt("_ = _fmt; break :{s} _buf[0.._pos]; ", .{label});
    try self.emitInlineBlockEnd();
}

pub fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    const fmt_str = getFormatStr(args[0]);
    // For struct.unpack, we need to emit inline since we iterate over fmt
    const label = try self.emitInlineBlockStart("struct_unpack");
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit("; const _raw_data = ");
    try self.genExpr(args[1]);
    // Handle PyBytes (has .data field) vs raw slice
    try self.emit("; const _data = if (@TypeOf(_raw_data) == runtime.builtins.PyBytes) _raw_data.data else _raw_data; _ = _fmt; ");
    if (fmt_str) |fmt| {
        try self.emit("var _pos: usize = 0; ");
        for (fmt, 0..) |c, i| {
            const ty = getPackType(c);
            if (c == 'f' or c == 'd') {
                try self.emitFmt("const _val{d}: {s} = std.mem.bytesToValue({s}, _data[_pos..][0..{s}])); _pos += {s}; ", .{ i, ty, ty, getUnpackSize(c), getUnpackSize(c) });
            } else {
                try self.emitFmt("const _val{d}: i64 = @intCast(std.mem.bytesToValue({s}, _data[_pos..][0..{s}])); _pos += {s}; ", .{ i, ty, getUnpackSize(c), getUnpackSize(c) });
            }
        }
        try self.emitFmt("break :{s} .{{", .{label});
        for (0..fmt.len) |i| {
            if (i > 0) try self.emit(", ");
            try self.emitFmt("_val{d}", .{i});
        }
        try self.emit("}; ");
        try self.emitInlineBlockEnd();
    } else {
        try self.emitFmt("const _val = std.mem.bytesToValue(i32, _data[0..4]); break :{s} .{{_val}}; ", .{label});
        try self.emitInlineBlockEnd();
    }
}

// struct.calcsize: handle both []const u8 and PyValue (from generators)
pub fn genCalcsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.withInlineBlock("struct_calcsize", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _raw_fmt = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _fmt = if (@TypeOf(_raw_fmt) == runtime.PyValue) _raw_fmt.asString() else _raw_fmt; var _size: usize = 0; for (_fmt) |fc| {{ _size += switch (fc) {{ 'b', 'B', 'c', '?', 'x' => 1, 'h', 'H' => 2, 'i', 'I', 'l', 'L', 'f' => 4, 'q', 'Q', 'd' => 8, else => 0 }}; }} break :{s} @as(i64, @intCast(_size)); ", .{label});
        }
    }.emit);
}

fn genPackInto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        // struct.pack_into() with insufficient args raises TypeError
        try self.emit("runtime.builtins.structPackIntoNoArgs()");
        return;
    }
    // For struct.pack_into, we need to emit inline since we iterate over args
    const label = try self.emitInlineBlockStart("struct_pack_into");
    try self.emit("const _fmt = ");
    try self.genExpr(args[0]);
    try self.emit("; const _buf = ");
    try self.genExpr(args[1]);
    try self.emit("; var _offset: usize = @intCast(");
    try self.genExpr(args[2]);
    try self.emit("); _ = _fmt; ");
    for (args[3..], 0..) |arg, i| {
        try self.emitFmt("const _val{d} = ", .{i});
        try self.genExpr(arg);
        try self.emitFmt("; const _bytes{d} = std.mem.asBytes(&_val{d}); @memcpy(_buf[_offset..][0.._bytes{d}.len], _bytes{d}); _offset += _bytes{d}.len; ", .{ i, i, i, i, i });
    }
    try self.emitFmt("break :{s}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genUnpackFrom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("struct_unpack_from", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _fmt = ");
            try c.genExpr(a[0]);
            try c.emit("; const _data = ");
            try c.genExpr(a[1]);
            try c.emit("; const _offset: usize = ");
            if (a.len > 2) {
                try c.emit("@intCast(");
                try c.genExpr(a[2]);
                try c.emit(")");
            } else {
                try c.emit("0");
            }
            try c.emitFmt("; _ = _fmt; const _val = std.mem.bytesToValue(i32, _data[_offset..][0..4]); break :{s} .{{_val}}; ", .{label});
        }
    }.emit);
}

fn genIterUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("struct { pub fn next(__self: *@This()) ?i32 { _ = __self; return null; } }{}");
        return;
    }
    try self.withInlineBlock("struct_iter_unpack", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _fmt = ");
            try c.genExpr(a[0]);
            try c.emit("; const _data = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = _fmt; _ = _data; break :{s} struct {{ items: []const u8, pos: usize = 0, pub fn next(__self: *@This()) ?i32 {{ if (__self.pos + 4 <= __self.items.len) {{ const val = std.mem.bytesToValue(i32, __self.items[__self.pos..][0..4]); __self.pos += 4; return val; }} return null; }} }}{{ .items = _data }}; ", .{label});
        }
    }.emit);
}
