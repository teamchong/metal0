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

    // Try to extract format string at compile time for type information
    // String values in AST include Python quotes, e.g., "f" is stored as '"f"'
    const format_str: ?[]const u8 = switch (args[0]) {
        .constant => |c| switch (c.value) {
            .string => |s| if (s.len >= 2) s[1 .. s.len - 1] else s,
            else => null,
        },
        else => null,
    };

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

        // Determine type from format string if available
        const format_char: u8 = if (format_str) |fmt| blk2: {
            if (i < fmt.len) break :blk2 fmt[i] else break :blk2 'i';
        } else 'i';

        // Choose type based on format character
        switch (format_char) {
            'f' => {
                // Float: use f32
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": f32 = @floatCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'd' => {
                // Double: use f64
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": f64 = @floatCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'h' => {
                // Short: use i16
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": i16 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'H' => {
                // Unsigned short: use u16
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": u16 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'b' => {
                // Signed byte: use i8
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": i8 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'B' => {
                // Unsigned byte: use u8
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": u8 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'I', 'L' => {
                // Unsigned int/long: use u32
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": u32 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'q' => {
                // Long long: use i64
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": i64 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            'Q' => {
                // Unsigned long long: use u64
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": u64 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
            else => {
                // Default: i32 (for 'i', 'l', etc.)
                try self.emit("const _val");
                try emitNum(self, i);
                try self.emit(": i32 = @intCast(");
                try self.genExpr(arg);
                try self.emit(");\n");
            },
        }

        try self.emitIndent();
        try self.emit("const _bytes");
        try emitNum(self, i);
        try self.emit(" = std.mem.asBytes(&_val");
        try emitNum(self, i);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("@memcpy(_buf[_pos..][0.._bytes");
        try emitNum(self, i);
        try self.emit(".len], _bytes");
        try emitNum(self, i);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("_pos += _bytes");
        try emitNum(self, i);
        try self.emit(".len;\n");
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

    // Try to extract format string at compile time
    const format_str: ?[]const u8 = switch (args[0]) {
        .constant => |c| switch (c.value) {
            .string => |s| if (s.len >= 2) s[1 .. s.len - 1] else s,
            else => null,
        },
        else => null,
    };

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

    if (format_str) |fmt| {
        // Compile-time known format - generate proper unpacking
        try self.emitIndent();
        try self.emit("var _pos: usize = 0;\n");

        for (fmt, 0..) |c, i| {
            try self.emitIndent();
            switch (c) {
                'f' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": f32 = std.mem.bytesToValue(f32, _data[_pos..][0..4]);\n");
                    try self.emitIndent();
                    try self.emit("_pos += 4;\n");
                },
                'd' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": f64 = std.mem.bytesToValue(f64, _data[_pos..][0..8]);\n");
                    try self.emitIndent();
                    try self.emit("_pos += 8;\n");
                },
                'h' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(i16, _data[_pos..][0..2]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 2;\n");
                },
                'H' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(u16, _data[_pos..][0..2]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 2;\n");
                },
                'b' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(i8, _data[_pos..][0..1]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 1;\n");
                },
                'B' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(u8, _data[_pos..][0..1]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 1;\n");
                },
                'I', 'L' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(u32, _data[_pos..][0..4]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 4;\n");
                },
                'q' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = std.mem.bytesToValue(i64, _data[_pos..][0..8]);\n");
                    try self.emitIndent();
                    try self.emit("_pos += 8;\n");
                },
                'Q' => {
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(u64, _data[_pos..][0..8]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 8;\n");
                },
                else => {
                    // Default: i32
                    try self.emit("const _val");
                    try emitNum(self, i);
                    try self.emit(": i64 = @intCast(std.mem.bytesToValue(i32, _data[_pos..][0..4]));\n");
                    try self.emitIndent();
                    try self.emit("_pos += 4;\n");
                },
            }
        }

        // Build tuple with all values
        try self.emitIndent();
        try self.emit("break :struct_unpack_blk .{");
        for (0..fmt.len) |i| {
            if (i > 0) try self.emit(", ");
            try self.emit("_val");
            try emitNum(self, i);
        }
        try self.emit("};\n");
    } else {
        // Runtime format - return first value as simple case
        try self.emitIndent();
        try self.emit("const _val = std.mem.bytesToValue(i32, _data[0..4]);\n");
        try self.emitIndent();
        try self.emit("break :struct_unpack_blk .{_val};\n");
    }

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
