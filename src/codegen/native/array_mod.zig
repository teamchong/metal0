/// Python array module - Efficient arrays of numeric values
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

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

    try b.emitRaw("struct { typecode: u8 = '");
    try b.emitRaw(&[_]u8{typecode});
    try b.emitRaw("', items: std.ArrayListUnmanaged(");
    try b.emitRaw(zig_type);
    try b.emitRaw(") = .{}, ");

    // append method - accepts optional allocator for compatibility with list.append dispatch
    try b.emitRaw("pub fn append(__self: *@This(), _: std.mem.Allocator, __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") !void { try __self.items.append(__global_allocator, __val); } ");

    // extend method
    try b.emitRaw("pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |__item| __self.append(__global_allocator, __item) catch @panic(\"array extend OOM\"); } ");

    // insert method
    try b.emitRaw("pub fn insert(__self: *@This(), __idx: usize, __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") void { __self.items.insert(__global_allocator, __idx, __val) catch @panic(\"array insert OOM\"); } ");

    // remove method
    try b.emitRaw("pub fn remove(__self: *@This(), __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") void { for (__self.items.items, 0..) |__v, __i| { if (__v == __val) { _ = __self.items.orderedRemove(__i); return; } } } ");

    // pop method
    try b.emitRaw("pub fn pop(__self: *@This()) ");
    try b.emitRaw(zig_type);
    try b.emitRaw(" { return __self.items.pop(); } ");

    // index method
    try b.emitRaw("pub fn index(__self: *@This(), __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") ?usize { for (__self.items.items, 0..) |__v, __i| { if (__v == __val) return __i; } return null; } ");

    // count method
    try b.emitRaw("pub fn count(__self: *@This(), __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") usize { var __cnt: usize = 0; for (__self.items.items) |__v| { if (__v == __val) __cnt += 1; } return __cnt; } ");

    // reverse method
    try b.emitRaw("pub fn reverse(__self: *@This()) void { std.mem.reverse(");
    try b.emitRaw(zig_type);
    try b.emitRaw(", __self.items.items); } ");

    // tobytes method
    try b.emitRaw("pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } ");

    // tolist method
    try b.emitRaw("pub fn tolist(__self: *@This()) []");
    try b.emitRaw(zig_type);
    try b.emitRaw(" { return __self.items.items; } ");

    // frombytes method - critical for 'B' arrays
    try b.emitRaw("pub fn frombytes(__self: *@This(), __bytes: []const u8) void { ");
    if (typecode == 'B' or typecode == 'b') {
        // For byte arrays, copy directly (use __byte to avoid shadowing outer 'b' param)
        try b.emitRaw("for (__bytes) |__byte| __self.items.append(__global_allocator, ");
        if (typecode == 'b') {
            try b.emitRaw("@as(i8, @bitCast(__byte))");
        } else {
            try b.emitRaw("__byte");
        }
        try b.emitRaw(") catch @panic(\"array frombytes OOM\"); } ");
    } else {
        // For other types, reinterpret bytes
        try b.emitRaw("const typed_slice = std.mem.bytesAsSlice(");
        try b.emitRaw(zig_type);
        try b.emitRaw(", __bytes); for (typed_slice) |__v| __self.items.append(__global_allocator, __v) catch @panic(\"array frombytes OOM\"); } ");
    }

    // fromlist method
    try b.emitRaw("pub fn fromlist(__self: *@This(), list: []");
    try b.emitRaw(zig_type);
    try b.emitRaw(") void { for (list) |__item| __self.append(__global_allocator, __item) catch @panic(\"array fromlist OOM\"); } ");

    // buffer_info method
    try b.emitRaw("pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } ");

    // byteswap method
    try b.emitRaw("pub fn byteswap(__self: *@This()) void { _ = __self; } ");

    // __len__ method
    try b.emitRaw("pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } ");

    // __getitem__ method
    try b.emitRaw("pub fn __getitem__(__self: *@This(), __idx: usize) ");
    try b.emitRaw(zig_type);
    try b.emitRaw(" { return __self.items.items[__idx]; } ");

    // __setitem__ method
    try b.emitRaw("pub fn __setitem__(__self: *@This(), __idx: usize, __val: ");
    try b.emitRaw(zig_type);
    try b.emitRaw(") void { __self.items.items[__idx] = __val; } ");

    // itemsize method
    try b.emitRaw("pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(");
    try b.emitRaw(zig_type);
    try b.emitRaw("); } ");

    try b.emitRaw("}{}");
    const output = try b.getBodyDupe();
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
                try c.emitCallCtx("runtime.discard", a[0], struct {
                    pub fn f(s: *h.NativeCodegen, e: ast.Node) h.CodegenError!void {
                        try s.genExpr(e);
                    }
                }.f);
                if (a.len > 1) {
                    // For initializers, populate the array from the bytes
                    try c.emit("; var __arr_init = ");
                    try genArrayStructDef(c, tc);
                    try c.emit("; __arr_init.frombytes(");
                    try c.genExpr(a[1]);
                    try c.emitFmt("); break :{s} __arr_init", .{label});
                    return;
                }
                try c.emit("; ");
            }

            try c.emitFmt("break :{s} ", .{label});
            try genArrayStructDef(c, tc);
        }
    }.emit);
}

/// Inline struct definition for default array.array (typecode 'l')
const array_struct_def_default = "struct { typecode: u8 = 'l', items: std.ArrayListUnmanaged(i64) = .{}, pub fn append(__self: *@This(), _: std.mem.Allocator, __val: i64) !void { try __self.items.append(__global_allocator, __val); } pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |__item| __self.append(__global_allocator, __item) catch unreachable; } pub fn insert(__self: *@This(), __idx: usize, __val: i64) void { __self.items.insert(__global_allocator, __idx, __val) catch unreachable; } pub fn remove(__self: *@This(), __val: i64) void { for (__self.items.items, 0..) |__v, __i| { if (__v == __val) { _ = __self.items.orderedRemove(__i); return; } } } pub fn pop(__self: *@This()) i64 { return __self.items.pop(); } pub fn index(__self: *@This(), __val: i64) ?usize { for (__self.items.items, 0..) |__v, __i| { if (__v == __val) return __i; } return null; } pub fn count(__self: *@This(), __val: i64) usize { var __cnt: usize = 0; for (__self.items.items) |__v| { if (__v == __val) __cnt += 1; } return __cnt; } pub fn reverse(__self: *@This()) void { std.mem.reverse(i64, __self.items.items); } pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } pub fn tolist(__self: *@This()) []i64 { return __self.items.items; } pub fn frombytes(__self: *@This(), __bytes: []const u8) void { _ = __self; _ = __bytes; } pub fn fromlist(__self: *@This(), list: []i64) void { for (list) |__item| __self.append(__global_allocator, __item) catch unreachable; } pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } pub fn byteswap(__self: *@This()) void { _ = __self; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __getitem__(__self: *@This(), __idx: usize) i64 { return __self.items.items[__idx]; } pub fn __setitem__(__self: *@This(), __idx: usize, __val: i64) void { __self.items.items[__idx] = __val; } pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(i64); } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "array", genArray },
    .{ "typecodes", h.c("\"bBuhHiIlLqQfd\"") },
    .{ "ArrayType", h.c(array_struct_def_default) },
});
