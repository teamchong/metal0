/// Introspection builtins (callable, len, id, hash)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const cpython = @import("../../cpython.zig");

const PyObject = runtime_core.PyObject;
const PyValue = @import("../../Objects/object.zig").PyValue;

/// Check if a type is a PyObject by looking for CPython struct fields
fn isPyObjectType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .one) return false;
    const ChildT = info.pointer.child;
    const child_info = @typeInfo(ChildT);
    return child_info == .@"struct" and
        @hasField(ChildT, "ob_refcnt") and
        @hasField(ChildT, "ob_type");
}

/// callable() builtin - returns true if object is callable
pub fn callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .@"fn") return true;
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (@typeInfo(child) == .@"fn") return true;
    }
    if (comptime isPyObjectType(T)) {
        const pyobj: *cpython.PyObject = @ptrCast(@alignCast(obj));
        if (pyobj.ob_type.tp_flags & 0xFF == 0x10 or pyobj.ob_type.tp_flags & 0xFF == 0x11) return true;
        if (pyobj.ob_type.tp_call != null) return true;
        return false;
    }
    return false;
}

/// Helper to check if type is a slice
pub fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .slice,
        else => false,
    };
}

/// len() builtin
/// Two-Flow: Handles PyValue for uncertain types
pub fn len(obj: anytype) usize {
    const T = @TypeOf(obj);
    // Two-Flow: Handle PyValue (uncertain type wrapper)
    if (T == PyValue) {
        return obj.pyLen();
    } else if (comptime isPyObjectType(T)) {
        const pyobj: *cpython.PyObject = @ptrCast(@alignCast(obj));
        return runtime_core.pyLen(pyobj);
    } else if (comptime isSlice(T)) {
        return obj.len;
    } else if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items")) {
            return obj.items.len;
        } else if (child_info == .@"struct" and @hasDecl(Child, "len")) {
            return obj.len;
        }
    } else if (@typeInfo(T) == .@"struct") {
        if (@hasDecl(T, "len")) {
            return obj.len();
        } else if (@hasField(T, "items")) {
            return obj.items.len;
        }
    } else if (@typeInfo(T) == .array) {
        return @typeInfo(T).array.len;
    }
    return 0;
}

/// id() builtin - returns object identity (pointer address)
pub fn id(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .pointer) {
        return @intFromPtr(obj);
    }
    return 0;
}

/// hash() builtin - returns hash of object
/// Two-Flow: Handles PyValue for uncertain types
pub fn hash(obj: anytype) i64 {
    const T = @TypeOf(obj);
    // Two-Flow: Handle PyValue (uncertain type wrapper)
    if (T == PyValue) {
        return obj.pyHash();
    } else if (comptime isPyObjectType(T)) {
        const pyobj: *cpython.PyObject = @ptrCast(@alignCast(obj));
        return @intCast(runtime_core.pyHash(pyobj));
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @intCast(obj);
    } else if (T == []const u8 or T == []u8) {
        var h: u64 = 0;
        for (obj) |c| h = h *% 31 +% c;
        return @intCast(h);
    } else if (@typeInfo(T) == .@"struct") {
        return tupleHash(obj);
    }
    return 0;
}

/// Python-compatible tuple hash using xxHash algorithm
pub fn tupleHash(tup: anytype) i64 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return 0;

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    const XXPRIME_1: u64 = 11400714785074694791;
    const XXPRIME_2: u64 = 14029467366897019727;
    const XXPRIME_5: u64 = 2870177450012600261;

    var acc: u64 = XXPRIME_5;

    inline for (fields) |field| {
        const elem = @field(tup, field.name);
        const elem_hash: u64 = @bitCast(hash(elem));
        acc +%= elem_hash *% XXPRIME_2;
        acc = (acc << 31) | (acc >> 33);
        acc *%= XXPRIME_1;
    }

    acc +%= @as(u64, num_fields) ^ (XXPRIME_5 ^ 3527539);

    if (acc == @as(u64, @bitCast(@as(i64, -1)))) {
        return 1546275796;
    }

    return @bitCast(acc);
}
