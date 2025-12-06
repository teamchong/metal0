/// Object Implementation - Core Object Operations
///
/// Implements CPython's Objects/object.c
/// Core object operations: comparison, repr, str, hash, etc.
///
/// Reference: cpython/Objects/object.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS - Rich Comparison Operators
// ============================================================================

pub const Py_LT: c_int = 0;
pub const Py_LE: c_int = 1;
pub const Py_EQ: c_int = 2;
pub const Py_NE: c_int = 3;
pub const Py_GT: c_int = 4;
pub const Py_GE: c_int = 5;

// ============================================================================
// REFERENCE COUNTING
// ============================================================================

/// Increment reference count
pub export fn Py_IncRef(op: ?*cpython.PyObject) void {
    if (op) |obj| {
        obj.ob_refcnt += 1;
    }
}

/// Decrement reference count
pub export fn Py_DecRef(op: ?*cpython.PyObject) void {
    if (op) |obj| {
        obj.ob_refcnt -= 1;
        if (obj.ob_refcnt == 0) {
            _Py_Dealloc(obj);
        }
    }
}

/// New reference (returns same object with incremented refcount)
pub export fn Py_NewRef(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op) |obj| {
        obj.ob_refcnt += 1;
        return obj;
    }
    return null;
}

/// XNewRef (handles null)
pub export fn Py_XNewRef(op: ?*cpython.PyObject) ?*cpython.PyObject {
    return Py_NewRef(op);
}

/// Clear reference (decref and set to null)
pub export fn Py_CLEAR(op: *?*cpython.PyObject) void {
    if (op.*) |obj| {
        op.* = null;
        Py_DecRef(obj);
    }
}

/// Set reference (decref old, assign new, incref new)
pub export fn Py_SETREF(op: *?*cpython.PyObject, new_op: ?*cpython.PyObject) void {
    const old = op.*;
    op.* = new_op;
    Py_DecRef(old);
}

/// XSetRef (like SETREF but increfs new)
pub export fn Py_XSETREF(op: *?*cpython.PyObject, new_op: ?*cpython.PyObject) void {
    const old = op.*;
    if (new_op) |new| {
        new.ob_refcnt += 1;
    }
    op.* = new_op;
    Py_DecRef(old);
}

// ============================================================================
// DEALLOCATION
// ============================================================================

/// Call the dealloc function for an object
pub export fn _Py_Dealloc(op: ?*cpython.PyObject) void {
    if (op == null) return;
    const obj = op.?;

    if (obj.ob_type.tp_dealloc) |dealloc| {
        dealloc(obj);
    }
}

/// Destructor for _Py_NoneStruct
fn none_dealloc(self: ?*cpython.PyObject) callconv(.C) void {
    _ = self;
    // None is a singleton, should never be deallocated
}

/// Repr for None
fn none_repr(self: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("None");
}

/// None type object
pub export var _PyNone_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "NoneType",
    .tp_basicsize = @sizeOf(cpython.PyObject),
    .tp_itemsize = 0,
    .tp_dealloc = none_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = none_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
};

/// The None singleton object
pub export var _Py_NoneStruct: cpython.PyObject = .{
    .ob_refcnt = 1,
    .ob_type = &_PyNone_Type,
};

/// Destructor for NotImplemented
fn notimpl_dealloc(self: ?*cpython.PyObject) callconv(.C) void {
    _ = self;
    // NotImplemented is a singleton
}

/// Repr for NotImplemented
fn notimpl_repr(self: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("NotImplemented");
}

/// NotImplemented type object
pub export var _PyNotImplemented_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "NotImplementedType",
    .tp_basicsize = @sizeOf(cpython.PyObject),
    .tp_itemsize = 0,
    .tp_dealloc = notimpl_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = notimpl_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
};

/// The NotImplemented singleton object
pub export var _Py_NotImplementedStruct: cpython.PyObject = .{
    .ob_refcnt = 1,
    .ob_type = &_PyNotImplemented_Type,
};

// ============================================================================
// OBJECT REPRESENTATION
// ============================================================================

/// Get repr of object
pub export fn PyObject_Repr(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) {
        const pyunicode = @import("unicodeobject.zig");
        return pyunicode.PyUnicode_FromString("<NULL>");
    }

    const obj = op.?;

    if (obj.ob_type.tp_repr) |repr_func| {
        return repr_func(obj);
    }

    // Default repr: <type_name object at 0xaddress>
    return null;
}

/// Get str of object
pub export fn PyObject_Str(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) {
        const pyunicode = @import("unicodeobject.zig");
        return pyunicode.PyUnicode_FromString("<NULL>");
    }

    const obj = op.?;

    // If tp_str is defined, use it
    if (obj.ob_type.tp_str) |str_func| {
        return str_func(obj);
    }

    // Fall back to repr
    return PyObject_Repr(obj);
}

/// Get ASCII repr of object
pub export fn PyObject_ASCII(op: ?*cpython.PyObject) ?*cpython.PyObject {
    const repr = PyObject_Repr(op);
    if (repr == null) return null;

    // TODO: Convert non-ASCII chars to \uxxxx escapes
    return repr;
}

/// Get bytes representation
pub export fn PyObject_Bytes(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    // Check for __bytes__ method
    // TODO: Call __bytes__ if it exists

    // For bytes objects, return as-is
    const pybytes = @import("bytesobject.zig");
    if (pybytes.PyBytes_Check(op.?) != 0) {
        op.?.ob_refcnt += 1;
        return op;
    }

    return null;
}

// ============================================================================
// COMPARISON
// ============================================================================

/// Rich comparison
pub export fn PyObject_RichCompare(v: ?*cpython.PyObject, w: ?*cpython.PyObject, op: c_int) ?*cpython.PyObject {
    if (v == null or w == null) return null;

    const obj_v = v.?;
    const obj_w = w.?;

    // Try v's comparison first
    if (obj_v.ob_type.tp_richcompare) |cmp| {
        const result = cmp(obj_v, obj_w, op);
        if (result != null and result != &_Py_NotImplementedStruct) {
            return result;
        }
    }

    // Try w's comparison with swapped op
    if (obj_w.ob_type.tp_richcompare) |cmp| {
        const swapped_op: c_int = switch (op) {
            Py_LT => Py_GT,
            Py_LE => Py_GE,
            Py_GT => Py_LT,
            Py_GE => Py_LE,
            else => op, // EQ, NE stay the same
        };
        const result = cmp(obj_w, obj_v, swapped_op);
        if (result != null and result != &_Py_NotImplementedStruct) {
            return result;
        }
    }

    // Default comparison for EQ/NE based on identity
    if (op == Py_EQ or op == Py_NE) {
        const pybool = @import("boolobject.zig");
        const same = (v == w);
        if (op == Py_EQ) {
            return if (same) pybool.Py_True else pybool.Py_False;
        } else {
            return if (same) pybool.Py_False else pybool.Py_True;
        }
    }

    return &_Py_NotImplementedStruct;
}

/// Rich comparison returning bool
pub export fn PyObject_RichCompareBool(v: ?*cpython.PyObject, w: ?*cpython.PyObject, op: c_int) c_int {
    // Quick identity check
    if (v == w) {
        if (op == Py_EQ) return 1;
        if (op == Py_NE) return 0;
    }

    const result = PyObject_RichCompare(v, w, op);
    if (result == null) return -1;

    // Check if result is truthy
    const is_true = PyObject_IsTrue(result);
    result.?.ob_refcnt -= 1;
    return is_true;
}

// ============================================================================
// HASH
// ============================================================================

/// Hash of object
pub export fn PyObject_Hash(op: ?*cpython.PyObject) isize {
    if (op == null) return -1;

    const obj = op.?;

    if (obj.ob_type.tp_hash) |hash_func| {
        const hash = hash_func(obj);
        if (hash == -1) {
            // -1 is reserved for errors, use -2 instead
            return -2;
        }
        return hash;
    }

    // If no hash function, object is unhashable
    return -1;
}

/// Hash that doesn't raise exceptions, returns -1 for unhashable
pub export fn PyObject_HashNotImplemented(self: ?*cpython.PyObject) callconv(.C) isize {
    _ = self;
    return -1;
}

// ============================================================================
// TRUTH VALUE
// ============================================================================

/// Check if object is true
pub export fn PyObject_IsTrue(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;

    const obj = op.?;

    // None is always false
    if (obj == &_Py_NoneStruct) {
        return 0;
    }

    // Check nb_bool
    if (obj.ob_type.tp_as_number) |num| {
        if (num.nb_bool) |bool_func| {
            return bool_func(obj);
        }
    }

    // Check sq_length (empty sequences are false)
    if (obj.ob_type.tp_as_sequence) |seq| {
        if (seq.sq_length) |len_func| {
            const len = len_func(obj);
            return if (len > 0) 1 else 0;
        }
    }

    // Check mp_length (empty mappings are false)
    if (obj.ob_type.tp_as_mapping) |map| {
        if (map.mp_length) |len_func| {
            const len = len_func(obj);
            return if (len > 0) 1 else 0;
        }
    }

    // By default, objects are true
    return 1;
}

/// Check if object is false
pub export fn PyObject_Not(op: ?*cpython.PyObject) c_int {
    const res = PyObject_IsTrue(op);
    if (res < 0) return res;
    return if (res != 0) 0 else 1;
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is an instance of a type
pub export fn PyObject_TypeCheck(op: ?*cpython.PyObject, type_obj: ?*cpython.PyTypeObject) c_int {
    if (op == null or type_obj == null) return 0;

    const obj = op.?;
    const target_type = type_obj.?;

    // Direct type match
    if (obj.ob_type == target_type) return 1;

    // Check MRO (Method Resolution Order)
    // TODO: Walk the MRO to check for subclass

    return 0;
}

/// Get type of object
pub export fn PyObject_Type(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    const type_obj: *cpython.PyObject = @ptrCast(op.?.ob_type);
    type_obj.ob_refcnt += 1;
    return type_obj;
}

// ============================================================================
// ATTRIBUTE ACCESS
// ============================================================================

/// Get attribute by string name
pub export fn PyObject_GetAttrString(op: ?*cpython.PyObject, name: ?[*:0]const u8) ?*cpython.PyObject {
    if (op == null or name == null) return null;

    const pyunicode = @import("unicodeobject.zig");
    const name_obj = pyunicode.PyUnicode_FromString(name.?);
    if (name_obj == null) return null;

    const result = PyObject_GetAttr(op, name_obj);
    name_obj.?.ob_refcnt -= 1;
    return result;
}

/// Get attribute by object name
pub export fn PyObject_GetAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null or name == null) return null;

    const obj = op.?;

    if (obj.ob_type.tp_getattro) |getattro| {
        return getattro(obj, name.?);
    }

    // Fall back to tp_getattr
    if (obj.ob_type.tp_getattr) |getattr| {
        // Need to convert name to C string
        const pyunicode = @import("unicodeobject.zig");
        const cstr = pyunicode.PyUnicode_AsUTF8(name.?);
        if (cstr == null) return null;
        return getattr(obj, @constCast(cstr.?));
    }

    return null;
}

/// Check if object has attribute
pub export fn PyObject_HasAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject) c_int {
    const result = PyObject_GetAttr(op, name);
    if (result == null) return 0;
    result.?.ob_refcnt -= 1;
    return 1;
}

/// Check if object has attribute by string name
pub export fn PyObject_HasAttrString(op: ?*cpython.PyObject, name: ?[*:0]const u8) c_int {
    const result = PyObject_GetAttrString(op, name);
    if (result == null) return 0;
    result.?.ob_refcnt -= 1;
    return 1;
}

/// Set attribute by object name
pub export fn PyObject_SetAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject, value: ?*cpython.PyObject) c_int {
    if (op == null or name == null) return -1;

    const obj = op.?;

    if (obj.ob_type.tp_setattro) |setattro| {
        return setattro(obj, name.?, value);
    }

    // Fall back to tp_setattr
    if (obj.ob_type.tp_setattr) |setattr| {
        const pyunicode = @import("unicodeobject.zig");
        const cstr = pyunicode.PyUnicode_AsUTF8(name.?);
        if (cstr == null) return -1;
        return setattr(obj, @constCast(cstr.?), value);
    }

    return -1;
}

/// Set attribute by string name
pub export fn PyObject_SetAttrString(op: ?*cpython.PyObject, name: ?[*:0]const u8, value: ?*cpython.PyObject) c_int {
    if (op == null or name == null) return -1;

    const pyunicode = @import("unicodeobject.zig");
    const name_obj = pyunicode.PyUnicode_FromString(name.?);
    if (name_obj == null) return -1;

    const result = PyObject_SetAttr(op, name_obj, value);
    name_obj.?.ob_refcnt -= 1;
    return result;
}

/// Delete attribute
pub export fn PyObject_DelAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject) c_int {
    return PyObject_SetAttr(op, name, null);
}

/// Delete attribute by string name
pub export fn PyObject_DelAttrString(op: ?*cpython.PyObject, name: ?[*:0]const u8) c_int {
    return PyObject_SetAttrString(op, name, null);
}

// ============================================================================
// GENERIC ATTRIBUTE ACCESS
// ============================================================================

/// Generic getattr implementation
pub export fn PyObject_GenericGetAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null or name == null) return null;

    const obj = op.?;
    const type_obj = obj.ob_type;

    // Search type's __dict__
    if (type_obj.tp_dict) |type_dict| {
        // TODO: Search type_dict for name
        _ = type_dict;
    }

    // Search instance's __dict__ if it has one
    if (type_obj.tp_dictoffset != 0) {
        // TODO: Get instance dict and search it
    }

    return null;
}

/// Generic setattr implementation
pub export fn PyObject_GenericSetAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject, value: ?*cpython.PyObject) c_int {
    if (op == null or name == null) return -1;

    const obj = op.?;
    const type_obj = obj.ob_type;

    // Set in instance's __dict__
    if (type_obj.tp_dictoffset != 0) {
        // TODO: Get instance dict and set value
        _ = value;
    }

    return -1;
}

// ============================================================================
// CALLABLE CHECK
// ============================================================================

/// Check if object is callable
pub export fn PyCallable_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;

    const obj = op.?;

    // Check tp_call
    if (obj.ob_type.tp_call != null) return 1;

    // Check for __call__ attribute
    // TODO: Check __call__ in type dict

    return 0;
}

// ============================================================================
// SIZE AND LENGTH
// ============================================================================

/// Get length of object
pub export fn PyObject_Length(op: ?*cpython.PyObject) isize {
    return PyObject_Size(op);
}

/// Get size of object
pub export fn PyObject_Size(op: ?*cpython.PyObject) isize {
    if (op == null) return -1;

    const obj = op.?;

    // Check sequence protocol
    if (obj.ob_type.tp_as_sequence) |seq| {
        if (seq.sq_length) |len_func| {
            return len_func(obj);
        }
    }

    // Check mapping protocol
    if (obj.ob_type.tp_as_mapping) |map| {
        if (map.mp_length) |len_func| {
            return len_func(obj);
        }
    }

    return -1;
}

// ============================================================================
// ITEM ACCESS
// ============================================================================

/// Get item from object
pub export fn PyObject_GetItem(op: ?*cpython.PyObject, key: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null or key == null) return null;

    const obj = op.?;

    // Check mapping protocol
    if (obj.ob_type.tp_as_mapping) |map| {
        if (map.mp_subscript) |subscript| {
            return subscript(obj, key.?);
        }
    }

    // Check sequence protocol with integer key
    if (obj.ob_type.tp_as_sequence) |seq| {
        if (seq.sq_item) |item_func| {
            // TODO: Convert key to index
            _ = item_func;
        }
    }

    return null;
}

/// Set item in object
pub export fn PyObject_SetItem(op: ?*cpython.PyObject, key: ?*cpython.PyObject, value: ?*cpython.PyObject) c_int {
    if (op == null or key == null) return -1;

    const obj = op.?;

    // Check mapping protocol
    if (obj.ob_type.tp_as_mapping) |map| {
        if (map.mp_ass_subscript) |ass_subscript| {
            return ass_subscript(obj, key.?, value);
        }
    }

    // Check sequence protocol with integer key
    if (obj.ob_type.tp_as_sequence) |seq| {
        if (seq.sq_ass_item) |ass_item| {
            // TODO: Convert key to index
            _ = ass_item;
        }
    }

    return -1;
}

/// Delete item from object
pub export fn PyObject_DelItem(op: ?*cpython.PyObject, key: ?*cpython.PyObject) c_int {
    return PyObject_SetItem(op, key, null);
}

// ============================================================================
// ITERATION
// ============================================================================

/// Get iterator for object
pub export fn PyObject_GetIter(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    const obj = op.?;

    if (obj.ob_type.tp_iter) |iter_func| {
        return iter_func(obj);
    }

    // Check for sequence protocol
    if (obj.ob_type.tp_as_sequence) |seq| {
        if (seq.sq_item != null) {
            // Create sequence iterator
            // TODO: Return PySeqIter_New(obj)
        }
    }

    return null;
}

/// Get aiter for object (async iteration)
pub export fn PyObject_GetAiter(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    const obj = op.?;

    if (obj.ob_type.tp_as_async) |async_methods| {
        if (async_methods.am_aiter) |aiter_func| {
            return aiter_func(obj);
        }
    }

    return null;
}

// ============================================================================
// OBJECT ALLOCATION
// ============================================================================

/// Allocate new object
pub export fn PyObject_Init(op: ?*cpython.PyObject, type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (op == null or type_obj == null) return null;

    op.?.ob_refcnt = 1;
    op.?.ob_type = type_obj.?;

    return op;
}

/// Allocate new var object
pub export fn PyObject_InitVar(op: ?*cpython.PyVarObject, type_obj: ?*cpython.PyTypeObject, size: isize) ?*cpython.PyVarObject {
    if (op == null or type_obj == null) return null;

    op.?.ob_base.ob_refcnt = 1;
    op.?.ob_base.ob_type = type_obj.?;
    op.?.ob_size = size;

    return op;
}

/// Allocate object with size
pub export fn _PyObject_New(type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (type_obj == null) return null;

    const size: usize = @intCast(type_obj.?.tp_basicsize);
    const mem = allocator.alignedAlloc(u8, @alignOf(cpython.PyObject), size) catch return null;
    const obj: *cpython.PyObject = @ptrCast(@alignCast(mem.ptr));

    return PyObject_Init(obj, type_obj);
}

/// Allocate var object with size
pub export fn _PyObject_NewVar(type_obj: ?*cpython.PyTypeObject, nitems: isize) ?*cpython.PyVarObject {
    if (type_obj == null) return null;

    const basicsize: usize = @intCast(type_obj.?.tp_basicsize);
    const itemsize: usize = @intCast(type_obj.?.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(nitems));

    const mem = allocator.alignedAlloc(u8, @alignOf(cpython.PyVarObject), size) catch return null;
    const obj: *cpython.PyVarObject = @ptrCast(@alignCast(mem.ptr));

    return PyObject_InitVar(obj, type_obj, nitems);
}

// ============================================================================
// DIR
// ============================================================================

/// Get list of names in object's namespace
pub export fn PyObject_Dir(op: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = op;

    // TODO: Implement dir() functionality
    // 1. Get type's __dir__ if it exists
    // 2. Otherwise, build list from type dict and instance dict
    return null;
}

// ============================================================================
// MISCELLANEOUS
// ============================================================================

/// Get object's id (memory address)
pub export fn PyObject_Id(op: ?*cpython.PyObject) isize {
    if (op == null) return 0;
    return @intCast(@intFromPtr(op.?));
}

/// Format object
pub export fn PyObject_Format(op: ?*cpython.PyObject, format_spec: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    // TODO: Look for __format__ method
    _ = format_spec;

    // Default to str()
    return PyObject_Str(op);
}
