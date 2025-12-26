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

/// compile() builtin - compile Python source to code object
/// Uses subprocess compilation to compile Python source code
pub fn compile(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*anyopaque {
    _ = filename; // TODO: store in code object for tracebacks
    _ = mode; // Mode is handled by the subprocess compiler
    const eval_cache = @import("../../Python/eval_cache.zig");

    // Use subprocess compilation to produce bytecode
    const program = try eval_cache.compileViaSubprocess(allocator, source);

    // Return the code object (caller is responsible for cleanup)
    return @ptrCast(program.code);
}

/// exec() builtin - execute Python code dynamically
/// Delegates to pythonrun.exec() which uses bytecode VM
pub fn exec(allocator: std.mem.Allocator, code: []const u8) !void {
    const pythonrun = @import("../../Python/pythonrun.zig");
    return pythonrun.exec(allocator, code);
}

/// exec() with globals and locals
pub fn execWithScope(allocator: std.mem.Allocator, code: []const u8, globals: ?*anyopaque, locals: ?*anyopaque) !void {
    const pythonrun = @import("../../Python/pythonrun.zig");
    const runtime = @import("../../runtime.zig");
    return pythonrun.execWithScope(allocator, code, @ptrCast(globals orelse runtime.Py_None), @ptrCast(locals));
}

/// struct.pack() stub - no args version
pub fn structPackNoArgs() PythonError![]const u8 {
    return PythonError.TypeError;
}

/// struct.pack_into() stub - no args version
pub fn structPackIntoNoArgs() PythonError!void {
    return PythonError.TypeError;
}

/// filter() stub - no args version (raises TypeError)
pub fn filterNoArgs() PythonError!void {
    return PythonError.TypeError;
}

/// map() stub - no args version (raises TypeError)
pub fn mapNoArgs() PythonError!void {
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
    const U = @TypeOf(b);

    // Get pointers to the BigInt values
    const a_ptr = if (@typeInfo(T) == .pointer) a else &a;
    const b_ptr = if (@typeInfo(U) == .pointer) b else &b;

    const PtrT = @TypeOf(a_ptr);
    const ChildT = if (@typeInfo(PtrT) == .pointer) @typeInfo(PtrT).pointer.child else PtrT;

    if (@typeInfo(ChildT) == .@"struct" and @hasDecl(ChildT, "compare")) {
        const cmp = a_ptr.compare(b_ptr);
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
