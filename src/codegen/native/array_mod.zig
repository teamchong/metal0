/// Python array module - Efficient arrays of numeric values
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("ast");

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

    try self.emit("struct { typecode: u8 = '");
    try self.emit(&[_]u8{typecode});
    try self.emit("', items: std.ArrayList(");
    try self.emit(zig_type);
    try self.emit(") = .{}, ");

    // append method
    try self.emit("pub fn append(__self: *@This(), x: ");
    try self.emit(zig_type);
    try self.emit(") void { __self.items.append(__global_allocator, x) catch {}; } ");

    // extend method
    try self.emit("pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(x); } ");

    // insert method
    try self.emit("pub fn insert(__self: *@This(), i: usize, x: ");
    try self.emit(zig_type);
    try self.emit(") void { __self.items.insert(__global_allocator, i, x) catch {}; } ");

    // remove method
    try self.emit("pub fn remove(__self: *@This(), x: ");
    try self.emit(zig_type);
    try self.emit(") void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } } ");

    // pop method
    try self.emit("pub fn pop(__self: *@This()) ");
    try self.emit(zig_type);
    try self.emit(" { return __self.items.pop(); } ");

    // index method
    try self.emit("pub fn index(__self: *@This(), x: ");
    try self.emit(zig_type);
    try self.emit(") ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; } ");

    // count method
    try self.emit("pub fn count(__self: *@This(), x: ");
    try self.emit(zig_type);
    try self.emit(") usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; } ");

    // reverse method
    try self.emit("pub fn reverse(__self: *@This()) void { std.mem.reverse(");
    try self.emit(zig_type);
    try self.emit(", __self.items.items); } ");

    // tobytes method
    try self.emit("pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } ");

    // tolist method
    try self.emit("pub fn tolist(__self: *@This()) []");
    try self.emit(zig_type);
    try self.emit(" { return __self.items.items; } ");

    // frombytes method - critical for 'B' arrays
    try self.emit("pub fn frombytes(__self: *@This(), s: []const u8) void { ");
    if (typecode == 'B' or typecode == 'b') {
        // For byte arrays, copy directly (use __byte to avoid shadowing outer 'b' param)
        try self.emit("for (s) |__byte| __self.items.append(__global_allocator, ");
        if (typecode == 'b') {
            try self.emit("@as(i8, @bitCast(__byte))");
        } else {
            try self.emit("__byte");
        }
        try self.emit(") catch {}; } ");
    } else {
        // For other types, reinterpret bytes
        try self.emit("const typed_slice = std.mem.bytesAsSlice(");
        try self.emit(zig_type);
        try self.emit(", s); for (typed_slice) |v| __self.items.append(__global_allocator, v) catch {}; } ");
    }

    // fromlist method
    try self.emit("pub fn fromlist(__self: *@This(), list: []");
    try self.emit(zig_type);
    try self.emit(") void { for (list) |x| __self.append(x); } ");

    // buffer_info method
    try self.emit("pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } ");

    // byteswap method
    try self.emit("pub fn byteswap(__self: *@This()) void { _ = __self; } ");

    // __len__ method
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } ");

    // __getitem__ method
    try self.emit("pub fn __getitem__(__self: *@This(), i: usize) ");
    try self.emit(zig_type);
    try self.emit(" { return __self.items.items[i]; } ");

    // __setitem__ method
    try self.emit("pub fn __setitem__(__self: *@This(), i: usize, v: ");
    try self.emit(zig_type);
    try self.emit(") void { __self.items.items[i] = v; } ");

    // itemsize method
    try self.emit("pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(");
    try self.emit(zig_type);
    try self.emit("); } ");

    try self.emit("}{}");
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
    // Determine typecode - default to 'l' if not a constant
    const typecode: u8 = if (args.len > 0) extractTypecode(args[0]) orelse 'l' else 'l';

    const id = try h.emitUniqueBlockStart(self, "arr");

    // Discard arguments (still need to evaluate them for side effects)
    if (args.len > 0) {
        try self.emit("runtime.discard(");
        try self.genExpr(args[0]);
        try self.emit(")");
        if (args.len > 1) {
            try self.emit("; ");
            // For initializers, populate the array from the bytes
            try self.emit("var __arr_init = ");
            try genArrayStructDef(self, typecode);
            try self.emit("; __arr_init.frombytes(");
            try self.genExpr(args[1]);
            try self.emitFmt("); break :arr_{d} __arr_init; }}", .{id});
            return;
        }
    }

    try h.emitBlockBreak(self, "arr", id);
    try genArrayStructDef(self, typecode);
    try self.emit("; }");
}

/// Inline struct definition for default array.array (typecode 'l')
const array_struct_def_default = "struct { typecode: u8 = 'l', items: std.ArrayList(i64) = .{}, pub fn append(__self: *@This(), x: i64) void { __self.items.append(__global_allocator, x) catch {}; } pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(x); } pub fn insert(__self: *@This(), i: usize, x: i64) void { __self.items.insert(__global_allocator, i, x) catch {}; } pub fn remove(__self: *@This(), x: i64) void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } } pub fn pop(__self: *@This()) i64 { return __self.items.pop(); } pub fn index(__self: *@This(), x: i64) ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; } pub fn count(__self: *@This(), x: i64) usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; } pub fn reverse(__self: *@This()) void { std.mem.reverse(i64, __self.items.items); } pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } pub fn tolist(__self: *@This()) []i64 { return __self.items.items; } pub fn frombytes(__self: *@This(), s: []const u8) void { _ = __self; _ = s; } pub fn fromlist(__self: *@This(), list: []i64) void { for (list) |x| __self.append(x); } pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } pub fn byteswap(__self: *@This()) void { _ = __self; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __getitem__(__self: *@This(), i: usize) i64 { return __self.items.items[i]; } pub fn __setitem__(__self: *@This(), i: usize, v: i64) void { __self.items.items[i] = v; } pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(i64); } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "array", genArray },
    .{ "typecodes", h.c("\"bBuhHiIlLqQfd\"") },
    .{ "ArrayType", h.c(array_struct_def_default) },
});
