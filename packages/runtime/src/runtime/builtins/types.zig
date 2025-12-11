/// Type builtins (str, bytes, bytearray, memoryview, bigint operations)
const std = @import("std");
const PythonError = @import("../../runtime.zig").PythonError;
const repr_mod = @import("repr.zig");
const PyBytes = repr_mod.PyBytes;

/// str() builtin
pub fn str(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .array and @typeInfo(Child).array.child == u8) {
            return value;
        }
    }
    return "";
}

/// bytes() builtin
pub fn bytes(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// bytearray() builtin
pub fn bytearray(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// memoryview() builtin
pub fn memoryview(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// bytes() callable version
pub fn bytes_callable(value: []const u8) []const u8 {
    return value;
}

/// bytearray() callable version
pub fn bytearray_callable(value: []const u8) []const u8 {
    return value;
}

/// str() callable version
pub fn str_callable(value: []const u8) []const u8 {
    return value;
}

/// memoryview() callable version
pub fn memoryview_callable(value: []const u8) []const u8 {
    return value;
}

/// compile() builtin - not supported in AOT context
pub fn compile(source: []const u8, filename: []const u8, mode: []const u8) PythonError!void {
    _ = source;
    _ = filename;
    _ = mode;
    return PythonError.ValueError;
}

/// exec() builtin - not supported in AOT context
pub fn exec(code: anytype) PythonError!void {
    _ = code;
    return PythonError.ValueError;
}

/// struct.pack() stub - no args version
pub fn structPackNoArgs() PythonError![]const u8 {
    return PythonError.TypeError;
}

/// struct.pack_into() stub - no args version
pub fn structPackIntoNoArgs() PythonError!void {
    return PythonError.TypeError;
}

/// Compare operation enum for BigInt
pub const CompareOp = enum { lt, le, eq, ne, gt, ge };

/// BigInt divmod
pub fn bigIntDivmod(a: anytype, b: anytype, allocator: std.mem.Allocator) struct { @TypeOf(a), @TypeOf(a) } {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "divFloor")) {
        const q = a.divFloor(b, allocator) catch return .{ a, a };
        const r = a.mod(b, allocator) catch return .{ a, a };
        return .{ q, r };
    }
    return .{ a, a };
}

/// BigInt comparison
pub fn bigIntCompare(a: anytype, b: anytype, op: CompareOp) bool {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "compare")) {
        const cmp = a.compare(b);
        return switch (op) {
            .lt => cmp < 0,
            .le => cmp <= 0,
            .eq => cmp == 0,
            .ne => cmp != 0,
            .gt => cmp > 0,
            .ge => cmp >= 0,
        };
    }
    return false;
}
