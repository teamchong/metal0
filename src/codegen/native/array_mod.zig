/// Python array module - Efficient arrays of numeric values
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

/// Get Zig type from Python array typecode
fn getZigType(typecode: u8) []const u8 {
    return switch (typecode) {
        'b' => "i8", // signed char
        'B' => "u8", // unsigned char
        'u' => "u16", // Py_UNICODE (deprecated, use u16)
        'h' => "i16", // signed short
        'H' => "u16", // unsigned short
        'i' => "i32", // signed int
        'I' => "u32", // unsigned int
        'l' => "i64", // signed long
        'L' => "u64", // unsigned long
        'q' => "i64", // signed long long
        'Q' => "u64", // unsigned long long
        'f' => "f32", // float
        'd' => "f64", // double
        else => "i64", // default to i64
    };
}

/// Generate array struct definition for a specific typecode
fn genArrayStructDef(self: *h.NativeCodegen, typecode: u8) !void {
    const zig_type = getZigType(typecode);
    const b = try self.getBuilder();

    try b.write("struct { typecode: u8 = '");
    try b.write(&[_]u8{typecode});
    try b.write("', items: std.ArrayListUnmanaged(");
    try b.write(zig_type);
    try b.write(") = .{}, ");

    // append method - accepts optional allocator for compatibility with list.append dispatch
    try b.write("pub fn append(__self: *@This(), _: std.mem.Allocator, x: ");
    try b.write(zig_type);
    try b.write(") !void { try __self.items.append(__global_allocator, x); } ");

    // extend method
    try b.write("pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(__global_allocator, x) catch @panic(\"array extend OOM\"); } ");

    // insert method
    try b.write("pub fn insert(__self: *@This(), i: usize, x: ");
    try b.write(zig_type);
    try b.write(") void { __self.items.insert(__global_allocator, i, x) catch @panic(\"array insert OOM\"); } ");

    // remove method
    try b.write("pub fn remove(__self: *@This(), x: ");
    try b.write(zig_type);
    try b.write(") void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } } ");

    // pop method
    try b.write("pub fn pop(__self: *@This()) ");
    try b.write(zig_type);
    try b.write(" { return __self.items.pop(); } ");

    // index method
    try b.write("pub fn index(__self: *@This(), x: ");
    try b.write(zig_type);
    try b.write(") ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; } ");

    // count method
    try b.write("pub fn count(__self: *@This(), x: ");
    try b.write(zig_type);
    try b.write(") usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; } ");

    // reverse method
    try b.write("pub fn reverse(__self: *@This()) void { std.mem.reverse(");
    try b.write(zig_type);
    try b.write(", __self.items.items); } ");

    // tobytes method
    try b.write("pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } ");

    // tolist method
    try b.write("pub fn tolist(__self: *@This()) []");
    try b.write(zig_type);
    try b.write(" { return __self.items.items; } ");

    // frombytes method - critical for 'B' arrays
    try b.write("pub fn frombytes(__self: *@This(), s: []const u8) void { ");
    if (typecode == 'B' or typecode == 'b') {
        // For byte arrays, copy directly (use __byte to avoid shadowing outer 'b' param)
        try b.write("for (s) |__byte| __self.items.append(__global_allocator, ");
        if (typecode == 'b') {
            try b.write("@as(i8, @bitCast(__byte))");
        } else {
            try b.write("__byte");
        }
        try b.write(") catch @panic(\"array frombytes OOM\"); } ");
    } else {
        // For other types, reinterpret bytes
        try b.write("const typed_slice = std.mem.bytesAsSlice(");
        try b.write(zig_type);
        try b.write(", s); for (typed_slice) |v| __self.items.append(__global_allocator, v) catch @panic(\"array frombytes OOM\"); } ");
    }

    // fromlist method
    try b.write("pub fn fromlist(__self: *@This(), list: []");
    try b.write(zig_type);
    try b.write(") void { for (list) |x| __self.append(__global_allocator, x) catch @panic(\"array fromlist OOM\"); } ");

    // buffer_info method
    try b.write("pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } ");

    // byteswap method
    try b.write("pub fn byteswap(__self: *@This()) void { _ = __self; } ");

    // __len__ method
    try b.write("pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } ");

    // __getitem__ method
    try b.write("pub fn __getitem__(__self: *@This(), i: usize) ");
    try b.write(zig_type);
    try b.write(" { return __self.items.items[i]; } ");

    // __setitem__ method
    try b.write("pub fn __setitem__(__self: *@This(), i: usize, v: ");
    try b.write(zig_type);
    try b.write(") void { __self.items.items[i] = v; } ");

    // itemsize method
    try b.write("pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(");
    try b.write(zig_type);
    try b.write("); } ");

    try b.write("}{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Extract typecode from first argument if it's a string constant
fn extractTypecode(arg: ast.Node) ?u8 {
    if (arg == .constant) {
        if (arg.constant.value == .string) {
            const str = arg.constant.value.string;
            if (str.len == 1) {
                return str[0];
            }
        }
    }
    return null;
}

/// Custom handler for array.array(typecode, initializer?) that uses the typecode to determine element type
fn genArray(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try self.withInlineBlock("arr", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            // Determine typecode - default to 'l' if not a constant
            const tc: u8 = if (a.len > 0) extractTypecode(a[0]) orelse 'l' else 'l';

            // Discard arguments (still need to evaluate them for side effects)
            if (a.len > 0) {
                {
                    const b = try c.getBuilder();
                    try b.write("runtime.discard(");
                    const output1 = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output1);
                }
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.write(")");
                    const output2 = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
                if (a.len > 1) {
                    {
                        const b = try c.getBuilder();
                        try b.write("; ");
                        // For initializers, populate the array from the bytes
                        try b.write("var __arr_init = ");
                        const output3 = b.getBodyAndClear();
                        try c.output.appendSlice(c.allocator, output3);
                    }
                    try genArrayStructDef(c, tc);
                    {
                        const b = try c.getBuilder();
                        try b.write("; __arr_init.frombytes(");
                        const output4 = b.getBodyAndClear();
                        try c.output.appendSlice(c.allocator, output4);
                    }
                    try c.genExpr(a[1]);
                    {
                        const b = try c.getBuilder();
                        try b.writeFmt("); break :{s} __arr_init", .{label});
                        const output5 = b.getBodyAndClear();
                        try c.output.appendSlice(c.allocator, output5);
                    }
                    return;
                }
            }

            {
                const b = try c.getBuilder();
                try b.writeFmt("break :{s} ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
            try genArrayStructDef(c, tc);
        }
    }.emit);
}

/// Inline struct definition for default array.array (typecode 'l')
const array_struct_def_default = "struct { typecode: u8 = 'l', items: std.ArrayListUnmanaged(i64) = .{}, pub fn append(__self: *@This(), _: std.mem.Allocator, x: i64) !void { try __self.items.append(__global_allocator, x); } pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(__global_allocator, x) catch unreachable; } pub fn insert(__self: *@This(), i: usize, x: i64) void { __self.items.insert(__global_allocator, i, x) catch unreachable; } pub fn remove(__self: *@This(), x: i64) void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } } pub fn pop(__self: *@This()) i64 { return __self.items.pop(); } pub fn index(__self: *@This(), x: i64) ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; } pub fn count(__self: *@This(), x: i64) usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; } pub fn reverse(__self: *@This()) void { std.mem.reverse(i64, __self.items.items); } pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } pub fn tolist(__self: *@This()) []i64 { return __self.items.items; } pub fn frombytes(__self: *@This(), s: []const u8) void { _ = __self; _ = s; } pub fn fromlist(__self: *@This(), list: []i64) void { for (list) |x| __self.append(__global_allocator, x) catch unreachable; } pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } pub fn byteswap(__self: *@This()) void { _ = __self; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __getitem__(__self: *@This(), i: usize) i64 { return __self.items.items[i]; } pub fn __setitem__(__self: *@This(), i: usize, v: i64) void { __self.items.items[i] = v; } pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(i64); } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "array", genArray },
    .{ "typecodes", h.c("\"bBuhHiIlLqQfd\"") },
    .{ "ArrayType", h.c(array_struct_def_default) },
});
