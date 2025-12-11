/// Type constructor callables (list, tuple, set, frozenset, deque)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const pylist = @import("../../Objects/listobject.zig");
const pytuple = @import("../../Objects/tupleobject.zig");
const pyset = @import("../../Objects/setobject.zig");
const pydeque = @import("../../Objects/dequeobject.zig");

const PyObject = runtime_core.PyObject;
const PyList = pylist.PyList;
const PyTuple = pytuple.PyTuple;
const PySet = pyset.PySet;
const PyDeque = pydeque.PyDeque;
const incref = runtime_core.incref;

/// list() type constructor
pub const list = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyList.create(allocator);
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyList.create(allocator);
                for (source.items.items) |item| {
                    incref(item);
                    try PyList.append(result, item);
                }
                return result;
            }
        }
        return try PyList.create(allocator);
    }
}{};

/// tuple() type constructor
pub const tuple = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyTuple.create(allocator, 0);
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyTuple.create(allocator, source.items.items.len);
                for (source.items.items, 0..) |item, i| {
                    incref(item);
                    PyTuple.setItem(result, i, item);
                }
                return result;
            }
        }
        return try PyTuple.create(allocator, 0);
    }
}{};

/// set() type constructor
pub const set = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PySet.create(allocator);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PySet.fromList(allocator, arg);
            }
        }
        return try PySet.create(allocator);
    }
}{};

/// frozenset() type constructor
pub const frozenset = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PySet.createFrozenset(allocator);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PySet.frozensetFromList(allocator, arg);
            }
        }
        return try PySet.createFrozenset(allocator);
    }
}{};

/// deque() type constructor
pub const deque = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyDeque.create(allocator, null);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PyDeque.fromList(allocator, arg, null);
            }
        }
        return try PyDeque.create(allocator, null);
    }
}{};
