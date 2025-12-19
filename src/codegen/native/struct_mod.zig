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

fn emitNum(b: anytype, n: usize) !void {
    try b.writeFmt("{d}", .{n});
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
        const b = try self.getBuilder();
        try b.write("runtime.builtins.structPackNoArgs()");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    const fmt_str = getFormatStr(args[0]);
    const fmt_off: usize = if (fmt_str) |f| getFmtOff(f) else 0;
    // For struct.pack, we need to emit the args inline since we iterate over them
    const label = try self.emitInlineBlockStart("struct_pack");
    {
        const b = try self.getBuilder();
        try b.write("const _fmt = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write("; var _buf: [1024]u8 = undefined; var _pos: usize = 0; ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    for (args[1..], 0..) |arg, i| {
        const fc: u8 = if (fmt_str) |f| (if (i + fmt_off < f.len) f[i + fmt_off] else 'i') else 'i';
        {
            const b = try self.getBuilder();
            try b.write("const _val");
            try emitNum(b, i);
            try b.write(": ");
            try b.write(getPackType(fc));
            try b.write(if (fc == 'f' or fc == 'd') " = @floatCast(" else " = runtime.packInt(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(arg);
        {
            const b = try self.getBuilder();
            try b.write("); const _bytes");
            try emitNum(b, i);
            try b.write(" = std.mem.asBytes(&_val");
            try emitNum(b, i);
            try b.write("); @memcpy(_buf[_pos..][0.._bytes");
            try emitNum(b, i);
            try b.write(".len], _bytes");
            try emitNum(b, i);
            try b.write("); _pos += _bytes");
            try emitNum(b, i);
            try b.write(".len; ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    }
    {
        const b = try self.getBuilder();
        try b.writeFmt("_ = _fmt; break :{s} _buf[0.._pos]; ", .{label});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.emitInlineBlockEnd();
}

pub fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    const fmt_str = getFormatStr(args[0]);
    // For struct.unpack, we need to emit inline since we iterate over fmt
    const label = try self.emitInlineBlockStart("struct_unpack");
    {
        const b = try self.getBuilder();
        try b.write("const _fmt = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write("; const _raw_data = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    // Handle PyBytes (has .data field) vs raw slice
    {
        const b = try self.getBuilder();
        try b.write("; const _data = if (@TypeOf(_raw_data) == runtime.builtins.PyBytes) _raw_data.data else _raw_data; _ = _fmt; ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (fmt_str) |fmt| {
        {
            const b = try self.getBuilder();
            try b.write("var _pos: usize = 0; ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        for (fmt, 0..) |c, i| {
            const ty = getPackType(c);
            const b = try self.getBuilder();
            try b.write("const _val");
            try emitNum(b, i);
            if (c == 'f' or c == 'd') {
                try b.write(": ");
                try b.write(ty);
                try b.write(" = std.mem.bytesToValue(");
                try b.write(ty);
            } else {
                try b.write(": i64 = @intCast(std.mem.bytesToValue(");
                try b.write(ty);
            }
            try b.write(", _data[_pos..][0..");
            try b.write(getUnpackSize(c));
            try b.write("])); _pos += ");
            try b.write(getUnpackSize(c));
            try b.write("; ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        {
            const b = try self.getBuilder();
            try b.writeFmt("break :{s} .{{", .{label});
            for (0..fmt.len) |i| {
                if (i > 0) try b.write(", ");
                try b.write("_val");
                try emitNum(b, i);
            }
            try b.write("}; ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.emitInlineBlockEnd();
    } else {
        const b = try self.getBuilder();
        try b.writeFmt("const _val = std.mem.bytesToValue(i32, _data[0..4]); break :{s} .{{_val}}; ", .{label});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        try self.emitInlineBlockEnd();
    }
}

// struct.calcsize: handle both []const u8 and PyValue (from generators)
pub fn genCalcsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("@as(i64, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("struct_calcsize", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _raw_fmt = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const _fmt = if (@TypeOf(_raw_fmt) == runtime.PyValue) _raw_fmt.asString() else _raw_fmt; var _size: usize = 0; for (_fmt) |fc| {{ _size += switch (fc) {{ 'b', 'B', 'c', '?', 'x' => 1, 'h', 'H' => 2, 'i', 'I', 'l', 'L', 'f' => 4, 'q', 'Q', 'd' => 8, else => 0 }}; }} break :{s} @as(i64, @intCast(_size)); ", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genPackInto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        // struct.pack_into() with insufficient args raises TypeError
        const b = try self.getBuilder();
        try b.write("runtime.builtins.structPackIntoNoArgs()");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    // For struct.pack_into, we need to emit inline since we iterate over args
    const label = try self.emitInlineBlockStart("struct_pack_into");
    {
        const b = try self.getBuilder();
        try b.write("const _fmt = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write("; const _buf = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write("; var _offset: usize = @intCast(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[2]);
    {
        const b = try self.getBuilder();
        try b.write("); _ = _fmt; ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    for (args[3..], 0..) |arg, i| {
        {
            const b = try self.getBuilder();
            try b.write("const _val");
            try emitNum(b, i);
            try b.write(" = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(arg);
        {
            const b = try self.getBuilder();
            try b.write("; const _bytes");
            try emitNum(b, i);
            try b.write(" = std.mem.asBytes(&_val");
            try emitNum(b, i);
            try b.write("); @memcpy(_buf[_offset..][0.._bytes");
            try emitNum(b, i);
            try b.write(".len], _bytes");
            try emitNum(b, i);
            try b.write("); _offset += _bytes");
            try emitNum(b, i);
            try b.write(".len; ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    }
    {
        const b = try self.getBuilder();
        try b.writeFmt("break :{s}; ", .{label});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.emitInlineBlockEnd();
}

fn genUnpackFrom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("struct_unpack_from", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _fmt = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _data = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.write("; const _offset: usize = ");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
            if (a.len > 2) {
                const b4 = try c.getBuilder();
                try b4.write("@intCast(");
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
                try c.genExpr(a[2]);
                const b5 = try c.getBuilder();
                try b5.write(")");
                const output5 = b5.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output5);
            } else {
                const b4 = try c.getBuilder();
                try b4.write("0");
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
            }
            {
                const b6 = try c.getBuilder();
                try b6.writeFmt("; _ = _fmt; const _val = std.mem.bytesToValue(i32, _data[_offset..][0..4]); break :{s} .{{_val}}; ", .{label});
                const output6 = b6.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output6);
            }
        }
    }.emit);
}

fn genIterUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("struct { pub fn next(__self: *@This()) ?i32 { _ = __self; return null; } }{}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("struct_iter_unpack", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _fmt = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _data = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; _ = _fmt; _ = _data; break :{s} struct {{ items: []const u8, pos: usize = 0, pub fn next(__self: *@This()) ?i32 {{ if (__self.pos + 4 <= __self.items.len) {{ const val = std.mem.bytesToValue(i32, __self.items[__self.pos..][0..4]); __self.pos += 4; return val; }} return null; }} }}{{ .items = _data }}; ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}
