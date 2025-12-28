/// Type constructor callables (list, tuple, dict, set, frozenset, deque, defaultdict)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const cpython = @import("../../cpython.zig");
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

/// int() type constructor - factory that returns 0 (for defaultdict(int))
pub const int = struct {
    pub fn call(_: @This()) i64 {
        return 0;
    }
}{};

/// list() type constructor
pub const list = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyList.create(allocator);
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyList_Check(pyobj)) {
                const source: *runtime_core.PyListObject = @ptrCast(@alignCast(pyobj));
                const result = try PyList.create(allocator);
                const size: usize = @intCast(source.ob_base.ob_size);
                for (0..size) |i| {
                    const item = source.ob_item[i];
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyList_Check(pyobj)) {
                const source: *runtime_core.PyListObject = @ptrCast(@alignCast(pyobj));
                const size: usize = @intCast(source.ob_base.ob_size);
                const result = try PyTuple.create(allocator, size);
                for (0..size) |i| {
                    const item = source.ob_item[i];
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyList_Check(pyobj)) {
                return try PySet.fromList(allocator, pyobj);
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyList_Check(pyobj)) {
                return try PySet.frozensetFromList(allocator, pyobj);
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyList_Check(pyobj)) {
                return try PyDeque.fromList(allocator, pyobj, null);
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(key_seq));
            if (runtime_core.PyList_Check(pyobj)) {
                const key_list: *runtime_core.PyListObject = @ptrCast(@alignCast(pyobj));
                const size: usize = @intCast(key_list.ob_base.ob_size);
                for (0..size) |i| {
                    const key = key_list.ob_item[i];
                    // Get string representation of key
                    if (runtime_core.PyUnicode_Check(key)) {
                        const str_data: *runtime_core.PyUnicodeObject = @ptrCast(@alignCast(key));
                        const key_len: usize = @intCast(str_data.length);
                        const key_str = str_data.data[0..key_len];
                        const V = @TypeOf(value);
                        if (comptime isPyObjectType(V)) {
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
        if (comptime isPyObjectType(T)) {
            const pyobj: *cpython.PyObject = @ptrCast(@alignCast(arg));
            if (runtime_core.PyDict_Check(pyobj)) {
                // Copy dict
                const result = try PyDict.create(allocator);
                var it = PyDict.iterator(pyobj);
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
