/// Legacy Compatibility Layer
/// Provides backwards compatibility for old type_id system and legacy reference counting

const std = @import("std");
const cpython = @import("../cpython.zig");
const pyobject_cast = @import("pyobject_cast.zig");
const hashmap_helper = @import("utils.hashmap_helper");

pub const PyObject = cpython.PyObject;
pub const PyLongObject = cpython.PyLongObject;
pub const PyFloatObject = cpython.PyFloatObject;
pub const PyBoolObject = cpython.PyBoolObject;
pub const PyListObject = cpython.PyListObject;
pub const PyTupleObject = cpython.PyTupleObject;
pub const PyDictObject = cpython.PyDictObject;
pub const PyUnicodeObject = cpython.PyUnicodeObject;
pub const Py_IS_TYPE = cpython.Py_IS_TYPE;
pub const Py_INCREF = cpython.Py_INCREF;

// =============================================================================
// Legacy TypeId enum
// =============================================================================

pub const TypeId = enum {
    int,
    float,
    bool,
    string,
    list,
    tuple,
    dict,
    none,
    file,
    regex,
    bytes,
    bigint,

    /// Convert PyObject to legacy TypeId
    pub fn fromPyObject(obj: *PyObject) TypeId {
        if (Py_IS_TYPE(obj, &cpython.PyLong_Type)) return .int;
        if (Py_IS_TYPE(obj, &cpython.PyFloat_Type)) return .float;
        if (Py_IS_TYPE(obj, &cpython.PyBool_Type)) return .bool;
        if (Py_IS_TYPE(obj, &cpython.PyUnicode_Type)) return .string;
        if (Py_IS_TYPE(obj, &cpython.PyList_Type)) return .list;
        if (Py_IS_TYPE(obj, &cpython.PyTuple_Type)) return .tuple;
        if (Py_IS_TYPE(obj, &cpython.PyDict_Type)) return .dict;
        if (Py_IS_TYPE(obj, &cpython.PyNone_Type)) return .none;
        if (Py_IS_TYPE(obj, &cpython.PyBytes_Type)) return .bytes;
        if (Py_IS_TYPE(obj, &cpython.PyBigInt_Type)) return .bigint;
        return .none; // Default fallback
    }
};

/// Legacy type_id accessor for backwards compatibility
pub fn getTypeId(obj: *PyObject) TypeId {
    return TypeId.fromPyObject(obj);
}

// =============================================================================
// Legacy Reference Counting
// =============================================================================

/// Legacy incref - bridges to Py_INCREF
pub fn incref(obj: *PyObject) void {
    Py_INCREF(obj);
}

/// Legacy decref with allocator - uses new type-based deallocation
pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    if (obj.ob_refcnt <= 0) {
        std.debug.print("WARNING: Attempting to decref object with ref_count already 0\n", .{});
        return;
    }
    obj.ob_refcnt -= 1;
    if (obj.ob_refcnt == 0) deallocByType(obj, allocator);
}

fn deallocByType(obj: *PyObject, allocator: std.mem.Allocator) void {
    const cast = pyobject_cast.cast;
    switch (getTypeId(obj)) {
        .int => allocator.destroy(cast(PyLongObject, obj)),
        .float => allocator.destroy(cast(PyFloatObject, obj)),
        .bool => allocator.destroy(cast(PyBoolObject, obj)),
        .list => deallocList(cast(PyListObject, obj), allocator),
        .tuple => deallocTuple(cast(PyTupleObject, obj), allocator),
        .string => deallocString(cast(PyUnicodeObject, obj), allocator),
        .dict => deallocDict(cast(PyDictObject, obj), allocator),
        .none => {}, // Never free None singleton
        else => {},
    }
}

fn deallocList(list_obj: *PyListObject, allocator: std.mem.Allocator) void {
    const size: usize = @intCast(list_obj.ob_base.ob_size);
    for (0..size) |i| decref(list_obj.ob_item[i], allocator);
    if (list_obj.allocated > 0) {
        allocator.free(list_obj.ob_item[0..@intCast(list_obj.allocated)]);
    }
    allocator.destroy(list_obj);
}

fn deallocTuple(tuple_obj: *PyTupleObject, allocator: std.mem.Allocator) void {
    const size: usize = @intCast(tuple_obj.ob_base.ob_size);
    for (0..size) |i| decref(tuple_obj.ob_item[i], allocator);
    allocator.free(tuple_obj.ob_item[0..size]);
    allocator.destroy(tuple_obj);
}

fn deallocString(str_obj: *PyUnicodeObject, allocator: std.mem.Allocator) void {
    const len: usize = @intCast(str_obj.length);
    if (len > 0) allocator.free(str_obj.data[0..len]);
    allocator.destroy(str_obj);
}

fn deallocDict(dict_obj: *PyDictObject, allocator: std.mem.Allocator) void {
    if (dict_obj.ma_keys) |keys_ptr| {
        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            decref(entry.value_ptr.*, allocator);
        }
        map.deinit();
        allocator.destroy(map);
    }
    allocator.destroy(dict_obj);
}
