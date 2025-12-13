/// Type constructor callables (list, tuple, dict, set, frozenset, deque, defaultdict)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const pylist = @import("../../Objects/listobject.zig");
const pytuple = @import("../../Objects/tupleobject.zig");
const pyset = @import("../../Objects/setobject.zig");
const pydeque = @import("../../Objects/dequeobject.zig");
const pydict = @import("../../Objects/dictobject.zig");

const PyObject = runtime_core.PyObject;
const PyList = pylist.PyList;
const PyTuple = pytuple.PyTuple;
const PySet = pyset.PySet;
const PyDeque = pydeque.PyDeque;
const PyDict = pydict.PyDict;
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

/// dict() type constructor
pub const dict = struct {
    /// Type methods (dict.fromkeys, etc.)
    pub fn fromkeys(_: @This(), allocator: std.mem.Allocator, key_seq: anytype, value: anytype) !*PyObject {
        const result = try PyDict.create(allocator);
        const T = @TypeOf(key_seq);
        if (T == *PyObject) {
            if (key_seq.type_id == .list) {
                const key_list: *PyList = @ptrCast(@alignCast(key_seq.data));
                for (key_list.items.items) |key| {
                    // Get string representation of key
                    if (key.type_id == .str) {
                        const str_data: *runtime_core.PyStringObject = @ptrCast(@alignCast(key.data));
                        const key_str = str_data.value;
                        const V = @TypeOf(value);
                        if (V == *PyObject) {
                            try PyDict.set(result, key_str, value);
                        }
                    }
                }
            }
        }
        return result;
    }

    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyDict.create(allocator);
        if (T == *PyObject) {
            if (runtime_core.PyDict_Check(arg)) {
                // Copy dict
                const result = try PyDict.create(allocator);
                const source = arg;
                var it = PyDict.iterator(source);
                while (it.next()) |entry| {
                    try PyDict.set(result, entry.key_ptr.*, entry.value_ptr.*);
                }
                return result;
            }
        }
        return try PyDict.create(allocator);
    }

    /// Metadata for introspection
    pub const __name__ = "dict";
    pub const __qualname__ = "dict";
    pub const __module__ = "builtins";
    pub const __self__ = @This();

    /// Get the items method (for dict.items)
    pub const items = struct {
        pub const __qualname__ = "dict.items";
        pub const __name__ = "items";
    }{};

    /// Get the keys method (for dict.keys)
    pub const keys = struct {
        pub const __qualname__ = "dict.keys";
        pub const __name__ = "keys";
    }{};

    /// Get the values method (for dict.values)
    pub const values = struct {
        pub const __qualname__ = "dict.values";
        pub const __name__ = "values";
    }{};
}{};

/// defaultdict() type constructor - dict with default factory
pub const defaultdict = struct {
    /// The default factory function (None if not set)
    default_factory: ?*const fn (std.mem.Allocator) anyerror!*PyObject = null,

    /// Type methods
    pub fn call(_: @This(), allocator: std.mem.Allocator, default_factory: anytype) !*PyObject {
        _ = default_factory;
        // Create a dict with default factory support
        return try PyDict.create(allocator);
    }

    /// Metadata for introspection
    pub const __name__ = "defaultdict";
    pub const __qualname__ = "defaultdict";
    pub const __module__ = "collections";

    /// __missing__ method - called when key not found
    pub fn @"__missing__"(_: @This(), _: std.mem.Allocator, _: anytype) !*PyObject {
        return error.KeyError;
    }
}{};
