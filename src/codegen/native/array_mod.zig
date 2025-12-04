/// Python array module - Efficient arrays of numeric values
const std = @import("std");
const h = @import("mod_helper.zig");

/// Inline struct definition for array.array - shared between array and ArrayType
const array_struct_def = "struct { typecode: u8 = 'l', items: std.ArrayList(i64) = .{}, pub fn append(__self: *@This(), x: i64) void { __self.items.append(__global_allocator, x) catch {}; } pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(x); } pub fn insert(__self: *@This(), i: usize, x: i64) void { __self.items.insert(__global_allocator, i, x) catch {}; } pub fn remove(__self: *@This(), x: i64) void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } } pub fn pop(__self: *@This()) i64 { return __self.items.pop(); } pub fn index(__self: *@This(), x: i64) ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; } pub fn count(__self: *@This(), x: i64) usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; } pub fn reverse(__self: *@This()) void { std.mem.reverse(i64, __self.items.items); } pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); } pub fn tolist(__self: *@This()) []i64 { return __self.items.items; } pub fn frombytes(__self: *@This(), s: []const u8) void { _ = __self; _ = s; } pub fn fromlist(__self: *@This(), list: []i64) void { for (list) |x| __self.append(x); } pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; } pub fn byteswap(__self: *@This()) void { _ = __self; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __getitem__(__self: *@This(), i: usize) i64 { return __self.items.items[i]; } pub fn __setitem__(__self: *@This(), i: usize, v: i64) void { __self.items.items[i] = v; } pub fn itemsize(__self: *@This()) usize { _ = __self; return @sizeOf(i64); } }{}";

/// Custom handler for array.array(typecode, initializer?) that actually uses the arguments
fn genArray(self: *h.NativeCodegen, args: []@import("ast").Node) h.CodegenError!void {
    // Generate: arr_blk: { runtime.discard(typecode); runtime.discard(initializer); break :arr_blk <struct>{}; }
    // Uses runtime.discard() to properly consume arguments without "pointless discard" errors
    const id = try h.emitUniqueBlockStart(self, "arr");
    if (args.len > 0) {
        try self.emit("runtime.discard(");
        try self.genExpr(args[0]);
        try self.emit(")");
        if (args.len > 1) {
            try self.emit("; runtime.discard(");
            try self.genExpr(args[1]);
            try self.emit(")");
        }
    }
    try h.emitBlockBreak(self, "arr", id);
    try self.emit(array_struct_def);
    try self.emit("; }");
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "array", genArray },
    .{ "typecodes", h.c("\"bBuhHiIlLqQfd\"") },
    .{ "ArrayType", h.c(array_struct_def) },
});
