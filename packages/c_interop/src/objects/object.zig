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
fn none_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    _ = self;
    // None is a singleton, should never be deallocated
}

/// Repr for None
fn none_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
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
fn notimpl_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    _ = self;
    // NotImplemented is a singleton
}

/// Repr for NotImplemented
fn notimpl_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
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

    const pyunicode = @import("unicodeobject.zig");

    // Get the UTF-8 content
    var size: isize = 0;
    const utf8 = pyunicode.PyUnicode_AsUTF8AndSize(repr, &size);
    if (utf8 == null) return repr; // Return repr as-is on error

    // Check if there are non-ASCII chars
    const data = utf8.?[0..@intCast(size)];
    var has_non_ascii = false;
    for (data) |c| {
        if (c > 127) {
            has_non_ascii = true;
            break;
        }
    }

    if (!has_non_ascii) return repr; // All ASCII, return repr as-is

    // Build ASCII representation with \uxxxx escapes
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;

    while (i < data.len and pos + 10 < buf.len) {
        const c = data[i];
        if (c <= 127) {
            buf[pos] = c;
            pos += 1;
            i += 1;
        } else {
            // Decode UTF-8 and convert to \uxxxx
            var codepoint: u21 = 0;
            if ((c & 0xE0) == 0xC0 and i + 1 < data.len) {
                // 2-byte UTF-8
                codepoint = (@as(u21, c & 0x1F) << 6) | @as(u21, data[i + 1] & 0x3F);
                i += 2;
            } else if ((c & 0xF0) == 0xE0 and i + 2 < data.len) {
                // 3-byte UTF-8
                codepoint = (@as(u21, c & 0x0F) << 12) | (@as(u21, data[i + 1] & 0x3F) << 6) | @as(u21, data[i + 2] & 0x3F);
                i += 3;
            } else if ((c & 0xF8) == 0xF0 and i + 3 < data.len) {
                // 4-byte UTF-8
                codepoint = (@as(u21, c & 0x07) << 18) | (@as(u21, data[i + 1] & 0x3F) << 12) | (@as(u21, data[i + 2] & 0x3F) << 6) | @as(u21, data[i + 3] & 0x3F);
                i += 4;
            } else {
                i += 1;
                continue;
            }

            // Format as \uxxxx or \Uxxxxxxxx
            if (codepoint <= 0xFFFF) {
                buf[pos] = '\\';
                buf[pos + 1] = 'u';
                const hex_chars = "0123456789abcdef";
                buf[pos + 2] = hex_chars[(codepoint >> 12) & 0xF];
                buf[pos + 3] = hex_chars[(codepoint >> 8) & 0xF];
                buf[pos + 4] = hex_chars[(codepoint >> 4) & 0xF];
                buf[pos + 5] = hex_chars[codepoint & 0xF];
                pos += 6;
            } else {
                buf[pos] = '\\';
                buf[pos + 1] = 'U';
                const hex_chars = "0123456789abcdef";
                buf[pos + 2] = hex_chars[(codepoint >> 28) & 0xF];
                buf[pos + 3] = hex_chars[(codepoint >> 24) & 0xF];
                buf[pos + 4] = hex_chars[(codepoint >> 20) & 0xF];
                buf[pos + 5] = hex_chars[(codepoint >> 16) & 0xF];
                buf[pos + 6] = hex_chars[(codepoint >> 12) & 0xF];
                buf[pos + 7] = hex_chars[(codepoint >> 8) & 0xF];
                buf[pos + 8] = hex_chars[(codepoint >> 4) & 0xF];
                buf[pos + 9] = hex_chars[codepoint & 0xF];
                pos += 10;
            }
        }
    }

    cpython.Py_DECREF(repr);
    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

/// Get bytes representation
pub export fn PyObject_Bytes(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;

    const pybytes = @import("bytesobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    // For bytes objects, return as-is
    if (pybytes.PyBytes_Check(op.?) != 0) {
        cpython.Py_INCREF(op.?);
        return op;
    }

    // Check for __bytes__ method
    const bytes_name = pyunicode.PyUnicode_FromString("__bytes__");
    if (bytes_name != null) {
        defer cpython.Py_DECREF(bytes_name.?);

        const bytes_method = PyObject_GetAttr(op, bytes_name);
        if (bytes_method != null) {
            defer cpython.Py_DECREF(bytes_method.?);

            // Call __bytes__ with no args
            const pytuple = @import("tupleobject.zig");
            const call = @import("call.zig");
            const empty_args = pytuple.PyTuple_New(0);
            if (empty_args != null) {
                defer cpython.Py_DECREF(empty_args.?);
                return call.PyObject_Call(bytes_method.?, empty_args.?, null);
            }
        }
    }

    // For string objects, encode to UTF-8 bytes
    if (pyunicode.PyUnicode_Check(op.?) != 0) {
        var size: isize = 0;
        const utf8 = pyunicode.PyUnicode_AsUTF8AndSize(op, &size);
        if (utf8 != null and size >= 0) {
            return pybytes.PyBytes_FromStringAndSize(utf8, size);
        }
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
            return if (same) pybool.Py_True() else pybool.Py_False();
        } else {
            return if (same) pybool.Py_False() else pybool.Py_True();
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
pub export fn PyObject_HashNotImplemented(self: ?*cpython.PyObject) callconv(.c) isize {
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
    // Walk through tp_mro tuple to find if target_type is a base class
    if (obj.ob_type.tp_mro) |mro| {
        const pytuple = @import("tupleobject.zig");
        const mro_size = pytuple.PyTuple_Size(mro);
        var i: isize = 0;
        while (i < mro_size) : (i += 1) {
            const base = pytuple.PyTuple_GetItem(mro, i);
            if (base != null) {
                const base_type: *cpython.PyTypeObject = @ptrCast(@alignCast(base.?));
                if (base_type == target_type) return 1;
            }
        }
    }

    // Also check tp_base chain
    var base = obj.ob_type.tp_base;
    while (base != null) {
        if (base == target_type) return 1;
        base = base.?.tp_base;
    }

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
    const pydict = @import("dictobject.zig");

    // Search type's __dict__ first (for methods and class attributes)
    if (type_obj.tp_dict) |type_dict| {
        const descr = pydict.PyDict_GetItem(type_dict, name.?);
        if (descr != null) {
            // Check if it's a descriptor (has __get__)
            const descr_type = descr.?.ob_type;
            if (descr_type.tp_descr_get) |descr_get| {
                // Call the descriptor's __get__ method
                return descr_get(descr.?, obj, @ptrCast(type_obj));
            }
            // Not a descriptor, return the value
            cpython.Py_INCREF(descr.?);
            return descr;
        }
    }

    // Search instance's __dict__ if it has one
    if (type_obj.tp_dictoffset != 0) {
        const offset: usize = @intCast(type_obj.tp_dictoffset);
        const obj_bytes: [*]u8 = @ptrCast(obj);
        const dict_ptr: *?*cpython.PyObject = @ptrCast(@alignCast(obj_bytes + offset));
        if (dict_ptr.*) |inst_dict| {
            const value = pydict.PyDict_GetItem(inst_dict, name.?);
            if (value != null) {
                cpython.Py_INCREF(value.?);
                return value;
            }
        }
    }

    // Walk MRO to find attribute in base classes
    if (type_obj.tp_mro) |mro| {
        const pytuple = @import("tupleobject.zig");
        const mro_size = pytuple.PyTuple_Size(mro);
        var i: isize = 1; // Skip first (the type itself, already checked)
        while (i < mro_size) : (i += 1) {
            const base = pytuple.PyTuple_GetItem(mro, i);
            if (base != null) {
                const base_type: *cpython.PyTypeObject = @ptrCast(@alignCast(base.?));
                if (base_type.tp_dict) |base_dict| {
                    const value = pydict.PyDict_GetItem(base_dict, name.?);
                    if (value != null) {
                        // Check if descriptor
                        if (value.?.ob_type.tp_descr_get) |descr_get| {
                            return descr_get(value.?, obj, @ptrCast(type_obj));
                        }
                        cpython.Py_INCREF(value.?);
                        return value;
                    }
                }
            }
        }
    }

    return null;
}

/// Generic setattr implementation
pub export fn PyObject_GenericSetAttr(op: ?*cpython.PyObject, name: ?*cpython.PyObject, value: ?*cpython.PyObject) c_int {
    if (op == null or name == null) return -1;

    const obj = op.?;
    const type_obj = obj.ob_type;
    const pydict = @import("dictobject.zig");

    // First check for a data descriptor in the type dict
    if (type_obj.tp_dict) |type_dict| {
        const descr = pydict.PyDict_GetItem(type_dict, name.?);
        if (descr != null) {
            // Check if it's a data descriptor (has __set__)
            const descr_type = descr.?.ob_type;
            if (descr_type.tp_descr_set) |descr_set| {
                // Call the descriptor's __set__ method
                return descr_set(descr.?, obj, value);
            }
        }
    }

    // Set in instance's __dict__
    if (type_obj.tp_dictoffset != 0) {
        const offset: usize = @intCast(type_obj.tp_dictoffset);
        const obj_bytes: [*]u8 = @ptrCast(obj);
        const dict_ptr: *?*cpython.PyObject = @ptrCast(@alignCast(obj_bytes + offset));

        // Create instance dict if it doesn't exist
        if (dict_ptr.* == null) {
            dict_ptr.* = pydict.PyDict_New();
            if (dict_ptr.* == null) return -1;
        }

        if (value == null) {
            // Delete attribute
            return pydict.PyDict_DelItem(dict_ptr.*.?, name.?);
        } else {
            // Set attribute
            return pydict.PyDict_SetItem(dict_ptr.*.?, name.?, value.?);
        }
    }

    // No dict offset - cannot set attribute
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

    // Check for __call__ attribute in type dict
    const pydict = @import("dictobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    if (obj.ob_type.tp_dict) |type_dict| {
        const call_name = pyunicode.PyUnicode_FromString("__call__");
        if (call_name != null) {
            defer cpython.Py_DECREF(call_name.?);
            const call_attr = pydict.PyDict_GetItem(type_dict, call_name.?);
            if (call_attr != null) return 1;
        }
    }

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
            // Convert key to index
            const pylong = @import("longobject.zig");
            if (pylong.PyLong_Check(key.?) != 0) {
                const index = pylong.PyLong_AsLong(key.?);
                if (index >= 0) {
                    return item_func(obj, index);
                } else {
                    // Handle negative indices by getting length
                    if (seq.sq_length) |len_func| {
                        const len = len_func(obj);
                        if (len >= 0) {
                            const adj_index = len + index;
                            if (adj_index >= 0) {
                                return item_func(obj, adj_index);
                            }
                        }
                    }
                }
            }
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
            // Convert key to index
            const pylong = @import("longobject.zig");
            if (pylong.PyLong_Check(key.?) != 0) {
                const index = pylong.PyLong_AsLong(key.?);
                if (index >= 0) {
                    return ass_item(obj, index, value);
                } else {
                    // Handle negative indices
                    if (seq.sq_length) |len_func| {
                        const len = len_func(obj);
                        if (len >= 0) {
                            const adj_index = len + index;
                            if (adj_index >= 0) {
                                return ass_item(obj, adj_index, value);
                            }
                        }
                    }
                }
            }
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
            const iterobject = @import("iterobject.zig");
            return iterobject.PySeqIter_New(obj);
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
    const mem = allocator.alloc(u8, size) catch return null;
    const obj: *cpython.PyObject = @ptrCast(@alignCast(mem.ptr));

    return PyObject_Init(obj, type_obj);
}

/// Allocate var object with size
pub export fn _PyObject_NewVar(type_obj: ?*cpython.PyTypeObject, nitems: isize) ?*cpython.PyVarObject {
    if (type_obj == null) return null;

    const basicsize: usize = @intCast(type_obj.?.tp_basicsize);
    const itemsize: usize = @intCast(type_obj.?.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(nitems));

    const mem = allocator.alloc(u8, size) catch return null;
    const obj: *cpython.PyVarObject = @ptrCast(@alignCast(mem.ptr));

    return PyObject_InitVar(obj, type_obj, nitems);
}

// ============================================================================
// DIR
// ============================================================================

/// Get list of names in object's namespace
pub export fn PyObject_Dir(op: ?*cpython.PyObject) ?*cpython.PyObject {
    const pylist = @import("listobject.zig");
    const pydict = @import("dictobject.zig");
    const pyunicode = @import("unicodeobject.zig");
    const pytuple = @import("tupleobject.zig");

    // Create result list
    const result = pylist.PyList_New(0);
    if (result == null) return null;

    if (op == null) {
        // dir() with no args - return empty list for now
        return result;
    }

    const obj = op.?;
    const type_obj = obj.ob_type;

    // Check for __dir__ method first
    const dir_name = pyunicode.PyUnicode_FromString("__dir__");
    if (dir_name != null) {
        defer cpython.Py_DECREF(dir_name.?);

        const dir_method = PyObject_GetAttr(op, dir_name);
        if (dir_method != null) {
            defer cpython.Py_DECREF(dir_method.?);

            // Call __dir__()
            const call = @import("call.zig");
            const empty_args = pytuple.PyTuple_New(0);
            if (empty_args != null) {
                defer cpython.Py_DECREF(empty_args.?);
                const dir_result = call.PyObject_Call(dir_method.?, empty_args.?, null);
                if (dir_result != null) {
                    cpython.Py_DECREF(result);
                    return dir_result;
                }
            }
        }
    }

    // Build list from type dict and instance dict
    // Add keys from type's __dict__
    if (type_obj.tp_dict) |type_dict| {
        var pos: isize = 0;
        var key: ?*cpython.PyObject = null;
        var value: ?*cpython.PyObject = null;

        while (pydict.PyDict_Next(type_dict, &pos, &key, &value) != 0) {
            if (key != null) {
                cpython.Py_INCREF(key.?);
                _ = pylist.PyList_Append(result.?, key.?);
            }
        }
    }

    // Add keys from MRO base classes
    if (type_obj.tp_mro) |mro| {
        const mro_size = pytuple.PyTuple_Size(mro);
        var i: isize = 1; // Skip first (already handled)
        while (i < mro_size) : (i += 1) {
            const base = pytuple.PyTuple_GetItem(mro, i);
            if (base != null) {
                const base_type: *cpython.PyTypeObject = @ptrCast(@alignCast(base.?));
                if (base_type.tp_dict) |base_dict| {
                    var pos: isize = 0;
                    var key: ?*cpython.PyObject = null;
                    var value: ?*cpython.PyObject = null;

                    while (pydict.PyDict_Next(base_dict, &pos, &key, &value) != 0) {
                        if (key != null) {
                            cpython.Py_INCREF(key.?);
                            _ = pylist.PyList_Append(result, key.?);
                        }
                    }
                }
            }
        }
    }

    // Add keys from instance's __dict__ if it has one
    if (type_obj.tp_dictoffset != 0) {
        const offset: usize = @intCast(type_obj.tp_dictoffset);
        const obj_bytes: [*]u8 = @ptrCast(obj);
        const dict_ptr: *?*cpython.PyObject = @ptrCast(@alignCast(obj_bytes + offset));
        if (dict_ptr.*) |inst_dict| {
            var pos: isize = 0;
            var key: ?*cpython.PyObject = null;
            var value: ?*cpython.PyObject = null;

            while (pydict.PyDict_Next(inst_dict, &pos, &key, &value) != 0) {
                if (key != null) {
                    cpython.Py_INCREF(key.?);
                    _ = pylist.PyList_Append(result, key.?);
                }
            }
        }
    }

    return result;
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

    const pyunicode = @import("unicodeobject.zig");
    const pytuple = @import("tupleobject.zig");

    // Look for __format__ method
    const format_name = pyunicode.PyUnicode_FromString("__format__");
    if (format_name != null) {
        defer cpython.Py_DECREF(format_name.?);

        const format_method = PyObject_GetAttr(op, format_name);
        if (format_method != null) {
            defer cpython.Py_DECREF(format_method.?);

            // Call __format__(format_spec)
            const call = @import("call.zig");
            const args = pytuple.PyTuple_New(1);
            if (args != null) {
                defer cpython.Py_DECREF(args.?);

                // Use empty string if no format_spec
                const spec = format_spec orelse pyunicode.PyUnicode_FromString("");
                if (spec != null) {
                    if (format_spec == null) {
                        // We created spec, will be owned by tuple
                    } else {
                        cpython.Py_INCREF(spec.?);
                    }
                    _ = pytuple.PyTuple_SetItem(args.?, 0, spec.?);

                    const result = call.PyObject_Call(format_method.?, args.?, null);
                    if (result != null) {
                        return result;
                    }
                }
            }
        }
    }

    // Default to str() for objects without __format__
    return PyObject_Str(op);
}
