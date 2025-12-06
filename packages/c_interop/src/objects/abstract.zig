/// Abstract Object Interface
///
/// Implements CPython's Objects/abstract.c
/// Provides generic operations on objects (PyNumber_*, PySequence_*, PyMapping_*)
///
/// Reference: cpython/Objects/abstract.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub const PyObject = cpython.PyObject;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Get the number methods from an object's type
inline fn getNumberMethods(o: *PyObject) ?*cpython.PyNumberMethods {
    const tp = cpython.Py_TYPE(o);
    return tp.tp_as_number;
}

/// Get the sequence methods from an object's type
inline fn getSequenceMethods(o: *PyObject) ?*cpython.PySequenceMethods {
    const tp = cpython.Py_TYPE(o);
    return tp.tp_as_sequence;
}

/// Get the mapping methods from an object's type
inline fn getMappingMethods(o: *PyObject) ?*cpython.PyMappingMethods {
    const tp = cpython.Py_TYPE(o);
    return tp.tp_as_mapping;
}

// ============================================================================
// NUMBER PROTOCOL
// ============================================================================

/// PyNumber_Check - Returns 1 if object provides numeric methods
pub export fn PyNumber_Check(o: ?*PyObject) callconv(.c) c_int {
    if (o == null) return 0;
    const nm = getNumberMethods(o.?) orelse return 0;
    return if (nm.nb_add != null or nm.nb_subtract != null or nm.nb_multiply != null or nm.nb_int != null or nm.nb_float != null or nm.nb_index != null) 1 else 0;
}

/// PyNumber_Add - Return o1 + o2
pub export fn PyNumber_Add(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_add) |add_fn| {
            return add_fn(o1.?, o2.?);
        }
    }
    if (getNumberMethods(o2.?)) |nm| {
        if (nm.nb_add) |add_fn| {
            return add_fn(o2.?, o1.?);
        }
    }
    return null;
}

/// PyNumber_Subtract - Return o1 - o2
pub export fn PyNumber_Subtract(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_subtract) |sub_fn| {
            return sub_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Multiply - Return o1 * o2
pub export fn PyNumber_Multiply(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_multiply) |mul_fn| {
            return mul_fn(o1.?, o2.?);
        }
    }
    if (getNumberMethods(o2.?)) |nm| {
        if (nm.nb_multiply) |mul_fn| {
            return mul_fn(o2.?, o1.?);
        }
    }
    return null;
}

/// PyNumber_TrueDivide - Return o1 / o2
pub export fn PyNumber_TrueDivide(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_true_divide) |div_fn| {
            return div_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_FloorDivide - Return o1 // o2
pub export fn PyNumber_FloorDivide(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_floor_divide) |div_fn| {
            return div_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Remainder - Return o1 % o2
pub export fn PyNumber_Remainder(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_remainder) |rem_fn| {
            return rem_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Power - Return pow(o1, o2, o3)
pub export fn PyNumber_Power(o1: ?*PyObject, o2: ?*PyObject, o3: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_power) |pow_fn| {
            return pow_fn(o1.?, o2.?, o3);
        }
    }
    return null;
}

/// PyNumber_Negative - Return -o
pub export fn PyNumber_Negative(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_negative) |neg_fn| {
            return neg_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Positive - Return +o
pub export fn PyNumber_Positive(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_positive) |pos_fn| {
            return pos_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Absolute - Return abs(o)
pub export fn PyNumber_Absolute(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_absolute) |abs_fn| {
            return abs_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Invert - Return ~o
pub export fn PyNumber_Invert(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_invert) |inv_fn| {
            return inv_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Long - Return int(o)
pub export fn PyNumber_Long(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_int) |int_fn| {
            return int_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Float - Return float(o)
pub export fn PyNumber_Float(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_float) |float_fn| {
            return float_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Index - Return operator.index(o)
pub export fn PyNumber_Index(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_index) |index_fn| {
            return index_fn(o.?);
        }
    }
    return null;
}

/// PyNumber_Lshift - Return o1 << o2
pub export fn PyNumber_Lshift(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_lshift) |lsh_fn| {
            return lsh_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Rshift - Return o1 >> o2
pub export fn PyNumber_Rshift(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_rshift) |rsh_fn| {
            return rsh_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_And - Return o1 & o2
pub export fn PyNumber_And(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_and) |and_fn| {
            return and_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Xor - Return o1 ^ o2
pub export fn PyNumber_Xor(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_xor) |xor_fn| {
            return xor_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Or - Return o1 | o2
pub export fn PyNumber_Or(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_or) |or_fn| {
            return or_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_Divmod - Return divmod(o1, o2)
pub export fn PyNumber_Divmod(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_divmod) |divmod_fn| {
            return divmod_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PyNumber_MatrixMultiply - Return o1 @ o2
pub export fn PyNumber_MatrixMultiply(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_matrix_multiply) |matmul_fn| {
            return matmul_fn(o1.?, o2.?);
        }
    }
    return null;
}

// In-place operations
pub export fn PyNumber_InPlaceAdd(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_add) |iadd_fn| return iadd_fn(o1.?, o2.?);
        if (nm.nb_add) |add_fn| return add_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceSubtract(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_subtract) |isub_fn| return isub_fn(o1.?, o2.?);
        if (nm.nb_subtract) |sub_fn| return sub_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceMultiply(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_multiply) |imul_fn| return imul_fn(o1.?, o2.?);
        if (nm.nb_multiply) |mul_fn| return mul_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceFloorDivide(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_floor_divide) |ifd_fn| return ifd_fn(o1.?, o2.?);
        if (nm.nb_floor_divide) |fd_fn| return fd_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceTrueDivide(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_true_divide) |itd_fn| return itd_fn(o1.?, o2.?);
        if (nm.nb_true_divide) |td_fn| return td_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceRemainder(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_remainder) |irem_fn| return irem_fn(o1.?, o2.?);
        if (nm.nb_remainder) |rem_fn| return rem_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlacePower(o1: ?*PyObject, o2: ?*PyObject, o3: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_power) |ipow_fn| return ipow_fn(o1.?, o2.?, o3);
        if (nm.nb_power) |pow_fn| return pow_fn(o1.?, o2.?, o3);
    }
    return null;
}

pub export fn PyNumber_InPlaceLshift(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_lshift) |ilsh_fn| return ilsh_fn(o1.?, o2.?);
        if (nm.nb_lshift) |lsh_fn| return lsh_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceRshift(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_rshift) |irsh_fn| return irsh_fn(o1.?, o2.?);
        if (nm.nb_rshift) |rsh_fn| return rsh_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceAnd(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_and) |iand_fn| return iand_fn(o1.?, o2.?);
        if (nm.nb_and) |and_fn| return and_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceXor(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_xor) |ixor_fn| return ixor_fn(o1.?, o2.?);
        if (nm.nb_xor) |xor_fn| return xor_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceOr(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_or) |ior_fn| return ior_fn(o1.?, o2.?);
        if (nm.nb_or) |or_fn| return or_fn(o1.?, o2.?);
    }
    return null;
}

pub export fn PyNumber_InPlaceMatrixMultiply(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getNumberMethods(o1.?)) |nm| {
        if (nm.nb_inplace_matrix_multiply) |imm_fn| return imm_fn(o1.?, o2.?);
        if (nm.nb_matrix_multiply) |mm_fn| return mm_fn(o1.?, o2.?);
    }
    return null;
}

/// PyNumber_AsSsize_t - Convert to Py_ssize_t with overflow checking
pub export fn PyNumber_AsSsize_t(o: ?*PyObject, exc: ?*PyObject) callconv(.c) isize {
    _ = exc;
    if (o == null) return -1;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_index) |index_fn| {
            const idx_obj = index_fn(o.?) orelse return -1;
            const long = @import("longobject.zig");
            return long.PyLong_AsSsize_t(idx_obj);
        }
    }
    return -1;
}

// ============================================================================
// SEQUENCE PROTOCOL
// ============================================================================

/// PySequence_Check - Returns 1 if object provides sequence methods
pub export fn PySequence_Check(o: ?*PyObject) callconv(.c) c_int {
    if (o == null) return 0;
    const sm = getSequenceMethods(o.?) orelse return 0;
    return if (sm.sq_item != null) 1 else 0;
}

/// PySequence_Size - Return length of sequence
pub export fn PySequence_Size(o: ?*PyObject) callconv(.c) isize {
    if (o == null) return -1;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_length) |len_fn| {
            return len_fn(o.?);
        }
    }
    return -1;
}

/// PySequence_Length - Alias for PySequence_Size
pub const PySequence_Length = PySequence_Size;

/// PySequence_Concat - Return o1 + o2
pub export fn PySequence_Concat(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getSequenceMethods(o1.?)) |sm| {
        if (sm.sq_concat) |concat_fn| {
            return concat_fn(o1.?, o2.?);
        }
    }
    return null;
}

/// PySequence_Repeat - Return o * count
pub export fn PySequence_Repeat(o: ?*PyObject, count: isize) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_repeat) |repeat_fn| {
            return repeat_fn(o.?, count);
        }
    }
    return null;
}

/// PySequence_GetItem - Return o[i]
pub export fn PySequence_GetItem(o: ?*PyObject, i: isize) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_item) |item_fn| {
            return item_fn(o.?, i);
        }
    }
    return null;
}

/// PySequence_SetItem - Set o[i] = v
pub export fn PySequence_SetItem(o: ?*PyObject, i: isize, v: ?*PyObject) callconv(.c) c_int {
    if (o == null) return -1;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_ass_item) |setitem_fn| {
            return setitem_fn(o.?, i, v);
        }
    }
    return -1;
}

/// PySequence_DelItem - Delete o[i]
pub export fn PySequence_DelItem(o: ?*PyObject, i: isize) callconv(.c) c_int {
    if (o == null) return -1;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_ass_item) |setitem_fn| {
            return setitem_fn(o.?, i, null);
        }
    }
    return -1;
}

/// PySequence_Contains - Return 1 if o contains value
pub export fn PySequence_Contains(o: ?*PyObject, value: ?*PyObject) callconv(.c) c_int {
    if (o == null or value == null) return -1;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_contains) |contains_fn| {
            return contains_fn(o.?, value.?);
        }
    }
    return -1;
}

/// PySequence_Index - Return first index of value in o
pub export fn PySequence_Index(o: ?*PyObject, value: ?*PyObject) callconv(.c) isize {
    if (o == null or value == null) return -1;
    const len = PySequence_Size(o);
    if (len < 0) return -1;

    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(o, i) orelse continue;
        const eq = PyObject_RichCompareBool(item, value.?, Py_EQ);
        if (eq == 1) return i;
    }
    return -1;
}

/// PySequence_Count - Return count of value in o
pub export fn PySequence_Count(o: ?*PyObject, value: ?*PyObject) callconv(.c) isize {
    if (o == null or value == null) return -1;
    const len = PySequence_Size(o);
    if (len < 0) return -1;

    var count: isize = 0;
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(o, i) orelse continue;
        const eq = PyObject_RichCompareBool(item, value.?, Py_EQ);
        if (eq == 1) count += 1;
    }
    return count;
}

/// PySequence_List - Return list(o)
pub export fn PySequence_List(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const list = @import("listobject.zig");
    const len = PySequence_Size(o);
    if (len < 0) return null;

    const result = list.PyList_New(len) orelse return null;
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(o, i) orelse continue;
        _ = list.PyList_SetItem(result, i, item);
    }
    return result;
}

/// PySequence_Tuple - Return tuple(o)
pub export fn PySequence_Tuple(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tuple = @import("tupleobject.zig");
    const len = PySequence_Size(o);
    if (len < 0) return null;

    const result = tuple.PyTuple_New(len) orelse return null;
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(o, i) orelse continue;
        _ = tuple.PyTuple_SetItem(result, i, item);
    }
    return result;
}

/// PySequence_InPlaceConcat - Return o1 += o2
pub export fn PySequence_InPlaceConcat(o1: ?*PyObject, o2: ?*PyObject) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    if (getSequenceMethods(o1.?)) |sm| {
        if (sm.sq_inplace_concat) |iconcat_fn| return iconcat_fn(o1.?, o2.?);
        if (sm.sq_concat) |concat_fn| return concat_fn(o1.?, o2.?);
    }
    return null;
}

/// PySequence_InPlaceRepeat - Return o *= count
pub export fn PySequence_InPlaceRepeat(o: ?*PyObject, count: isize) callconv(.c) ?*PyObject {
    if (o == null) return null;
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_inplace_repeat) |irepeat_fn| return irepeat_fn(o.?, count);
        if (sm.sq_repeat) |repeat_fn| return repeat_fn(o.?, count);
    }
    return null;
}

// ============================================================================
// MAPPING PROTOCOL
// ============================================================================

/// PyMapping_Check - Returns 1 if object provides mapping methods
pub export fn PyMapping_Check(o: ?*PyObject) callconv(.c) c_int {
    if (o == null) return 0;
    const mm = getMappingMethods(o.?) orelse return 0;
    return if (mm.mp_subscript != null) 1 else 0;
}

/// PyMapping_Size - Return len(o)
pub export fn PyMapping_Size(o: ?*PyObject) callconv(.c) isize {
    if (o == null) return -1;
    if (getMappingMethods(o.?)) |mm| {
        if (mm.mp_length) |len_fn| {
            return len_fn(o.?);
        }
    }
    return -1;
}

/// PyMapping_Length - Alias for PyMapping_Size
pub const PyMapping_Length = PyMapping_Size;

/// PyMapping_GetItemString - Return o[key] where key is a C string
pub export fn PyMapping_GetItemString(o: ?*PyObject, key: [*:0]const u8) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const unicode = @import("../include/unicodeobject.zig");
    const key_obj = unicode.PyUnicode_FromString(key) orelse return null;
    return PyObject_GetItem(o, key_obj);
}

/// PyMapping_SetItemString - Set o[key] = v where key is a C string
pub export fn PyMapping_SetItemString(o: ?*PyObject, key: [*:0]const u8, v: ?*PyObject) callconv(.c) c_int {
    if (o == null) return -1;
    const unicode = @import("../include/unicodeobject.zig");
    const key_obj = unicode.PyUnicode_FromString(key) orelse return -1;
    return PyObject_SetItem(o, key_obj, v);
}

/// PyMapping_HasKey - Return 1 if o has key
pub export fn PyMapping_HasKey(o: ?*PyObject, key: ?*PyObject) callconv(.c) c_int {
    if (o == null or key == null) return 0;
    const result = PyObject_GetItem(o, key);
    return if (result != null) 1 else 0;
}

/// PyMapping_HasKeyString - Return 1 if o has key (C string)
pub export fn PyMapping_HasKeyString(o: ?*PyObject, key: [*:0]const u8) callconv(.c) c_int {
    if (o == null) return 0;
    const result = PyMapping_GetItemString(o, key);
    return if (result != null) 1 else 0;
}

/// PyMapping_Keys - Return list of keys
pub export fn PyMapping_Keys(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_getattro) |getattro| {
        const unicode = @import("../include/unicodeobject.zig");
        const keys_str = unicode.PyUnicode_FromString("keys") orelse return null;
        const method = getattro(o.?, keys_str) orelse return null;
        return PyObject_CallNoArgs(method);
    }
    return null;
}

/// PyMapping_Values - Return list of values
pub export fn PyMapping_Values(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_getattro) |getattro| {
        const unicode = @import("../include/unicodeobject.zig");
        const values_str = unicode.PyUnicode_FromString("values") orelse return null;
        const method = getattro(o.?, values_str) orelse return null;
        return PyObject_CallNoArgs(method);
    }
    return null;
}

/// PyMapping_Items - Return list of (key, value) pairs
pub export fn PyMapping_Items(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_getattro) |getattro| {
        const unicode = @import("../include/unicodeobject.zig");
        const items_str = unicode.PyUnicode_FromString("items") orelse return null;
        const method = getattro(o.?, items_str) orelse return null;
        return PyObject_CallNoArgs(method);
    }
    return null;
}

// ============================================================================
// OBJECT PROTOCOL
// ============================================================================

/// PyObject_Call - Call callable with args and kwargs
pub export fn PyObject_Call(callable: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) callconv(.c) ?*PyObject {
    if (callable == null) return null;
    const tp = cpython.Py_TYPE(callable.?);
    if (tp.tp_call) |call_fn| {
        return call_fn(callable.?, args, kwargs);
    }
    return null;
}

/// PyObject_CallObject - Call callable with args tuple
pub export fn PyObject_CallObject(callable: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
    return PyObject_Call(callable, args, null);
}

/// PyObject_CallNoArgs - Call callable with no arguments
pub export fn PyObject_CallNoArgs(callable: ?*PyObject) callconv(.c) ?*PyObject {
    if (callable == null) return null;
    const tp = cpython.Py_TYPE(callable.?);
    if (tp.tp_call) |call_fn| {
        const tuple = @import("tupleobject.zig");
        const empty_args = tuple.PyTuple_New(0) orelse return null;
        return call_fn(callable.?, empty_args, null);
    }
    return null;
}

/// PyObject_Type - Return type(o)
pub export fn PyObject_Type(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    cpython.Py_INCREF(@ptrCast(&tp.ob_base.ob_base));
    return @ptrCast(&tp.ob_base.ob_base);
}

/// PyObject_Size - Return len(o)
pub export fn PyObject_Size(o: ?*PyObject) callconv(.c) isize {
    if (o == null) return -1;
    if (getMappingMethods(o.?)) |mm| {
        if (mm.mp_length) |len_fn| {
            return len_fn(o.?);
        }
    }
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_length) |len_fn| {
            return len_fn(o.?);
        }
    }
    return -1;
}

/// PyObject_Length - Alias for PyObject_Size
pub const PyObject_Length = PyObject_Size;

/// PyObject_GetItem - Return o[key]
pub export fn PyObject_GetItem(o: ?*PyObject, key: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null or key == null) return null;
    if (getMappingMethods(o.?)) |mm| {
        if (mm.mp_subscript) |subscript_fn| {
            return subscript_fn(o.?, key.?);
        }
    }
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_item) |item_fn| {
            const long = @import("longobject.zig");
            if (long.PyLong_Check(key.?) != 0) {
                const idx = long.PyLong_AsLong(key.?);
                return item_fn(o.?, @intCast(idx));
            }
        }
    }
    return null;
}

/// PyObject_SetItem - Set o[key] = v
pub export fn PyObject_SetItem(o: ?*PyObject, key: ?*PyObject, v: ?*PyObject) callconv(.c) c_int {
    if (o == null or key == null) return -1;
    if (getMappingMethods(o.?)) |mm| {
        if (mm.mp_ass_subscript) |ass_subscript_fn| {
            return ass_subscript_fn(o.?, key.?, v);
        }
    }
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_ass_item) |ass_item_fn| {
            const long = @import("longobject.zig");
            if (long.PyLong_Check(key.?) != 0) {
                const idx = long.PyLong_AsLong(key.?);
                return ass_item_fn(o.?, @intCast(idx), v);
            }
        }
    }
    return -1;
}

/// PyObject_DelItem - Delete o[key]
pub export fn PyObject_DelItem(o: ?*PyObject, key: ?*PyObject) callconv(.c) c_int {
    return PyObject_SetItem(o, key, null);
}

/// PyObject_GetIter - Return iter(o)
pub export fn PyObject_GetIter(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_iter) |iter_fn| {
        return iter_fn(o.?);
    }
    return null;
}

/// PyObject_IsTrue - Return 1 if o is true
pub export fn PyObject_IsTrue(o: ?*PyObject) callconv(.c) c_int {
    if (o == null) return -1;
    if (getNumberMethods(o.?)) |nm| {
        if (nm.nb_bool) |bool_fn| {
            return bool_fn(o.?);
        }
    }
    if (getSequenceMethods(o.?)) |sm| {
        if (sm.sq_length) |len_fn| {
            return if (len_fn(o.?) != 0) 1 else 0;
        }
    }
    if (getMappingMethods(o.?)) |mm| {
        if (mm.mp_length) |len_fn| {
            return if (len_fn(o.?) != 0) 1 else 0;
        }
    }
    return 1;
}

/// PyObject_Not - Return 0 if o is true, 1 if false
pub export fn PyObject_Not(o: ?*PyObject) callconv(.c) c_int {
    const result = PyObject_IsTrue(o);
    if (result < 0) return result;
    return if (result != 0) 0 else 1;
}

/// PyObject_Hash - Return hash(o)
pub export fn PyObject_Hash(o: ?*PyObject) callconv(.c) isize {
    if (o == null) return -1;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_hash) |hash_fn| {
        return hash_fn(o.?);
    }
    return @intCast(@intFromPtr(o.?));
}

/// PyObject_Repr - Return repr(o)
pub export fn PyObject_Repr(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_repr) |repr_fn| {
        return repr_fn(o.?);
    }
    return null;
}

/// PyObject_Str - Return str(o)
pub export fn PyObject_Str(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_str) |str_fn| {
        return str_fn(o.?);
    }
    if (tp.tp_repr) |repr_fn| {
        return repr_fn(o.?);
    }
    return null;
}

/// PyObject_ASCII - Return ascii(o)
pub export fn PyObject_ASCII(o: ?*PyObject) callconv(.c) ?*PyObject {
    return PyObject_Repr(o);
}

/// PyObject_Bytes - Return bytes(o)
pub export fn PyObject_Bytes(o: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_getattro) |getattro| {
        const unicode = @import("../include/unicodeobject.zig");
        const bytes_str = unicode.PyUnicode_FromString("__bytes__") orelse return null;
        const method = getattro(o.?, bytes_str);
        if (method != null) {
            return PyObject_CallNoArgs(method);
        }
    }
    return null;
}

/// PyObject_RichCompare - Rich comparison
pub export fn PyObject_RichCompare(o1: ?*PyObject, o2: ?*PyObject, opid: c_int) callconv(.c) ?*PyObject {
    if (o1 == null or o2 == null) return null;
    const tp = cpython.Py_TYPE(o1.?);
    if (tp.tp_richcompare) |richcmp_fn| {
        return richcmp_fn(o1.?, o2.?, opid);
    }
    return null;
}

/// PyObject_RichCompareBool - Rich comparison returning bool
pub export fn PyObject_RichCompareBool(o1: ?*PyObject, o2: ?*PyObject, opid: c_int) callconv(.c) c_int {
    const result = PyObject_RichCompare(o1, o2, opid);
    if (result == null) return -1;
    return PyObject_IsTrue(result);
}

/// PyObject_GetAttr - Get attribute by name (PyObject)
pub export fn PyObject_GetAttr(o: ?*PyObject, name: ?*PyObject) callconv(.c) ?*PyObject {
    if (o == null or name == null) return null;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_getattro) |getattro| {
        return getattro(o.?, name.?);
    }
    return null;
}

/// PyObject_GetAttrString - Get attribute by C string name
pub export fn PyObject_GetAttrString(o: ?*PyObject, name: [*:0]const u8) callconv(.c) ?*PyObject {
    if (o == null) return null;
    const unicode = @import("../include/unicodeobject.zig");
    const name_obj = unicode.PyUnicode_FromString(name) orelse return null;
    return PyObject_GetAttr(o, name_obj);
}

/// PyObject_SetAttr - Set attribute by name (PyObject)
pub export fn PyObject_SetAttr(o: ?*PyObject, name: ?*PyObject, value: ?*PyObject) callconv(.c) c_int {
    if (o == null or name == null) return -1;
    const tp = cpython.Py_TYPE(o.?);
    if (tp.tp_setattro) |setattro| {
        return setattro(o.?, name.?, value);
    }
    return -1;
}

/// PyObject_SetAttrString - Set attribute by C string name
pub export fn PyObject_SetAttrString(o: ?*PyObject, name: [*:0]const u8, value: ?*PyObject) callconv(.c) c_int {
    if (o == null) return -1;
    const unicode = @import("../include/unicodeobject.zig");
    const name_obj = unicode.PyUnicode_FromString(name) orelse return -1;
    return PyObject_SetAttr(o, name_obj, value);
}

/// PyObject_HasAttr - Check if attribute exists
pub export fn PyObject_HasAttr(o: ?*PyObject, name: ?*PyObject) callconv(.c) c_int {
    const result = PyObject_GetAttr(o, name);
    return if (result != null) 1 else 0;
}

/// PyObject_HasAttrString - Check if attribute exists (C string)
pub export fn PyObject_HasAttrString(o: ?*PyObject, name: [*:0]const u8) callconv(.c) c_int {
    const result = PyObject_GetAttrString(o, name);
    return if (result != null) 1 else 0;
}

/// PyObject_Dir - Return dir(o)
pub export fn PyObject_Dir(o: ?*PyObject) callconv(.c) ?*PyObject {
    _ = o;
    return null;
}

/// PyCallable_Check - Return 1 if object is callable
pub export fn PyCallable_Check(o: ?*PyObject) callconv(.c) c_int {
    if (o == null) return 0;
    const tp = cpython.Py_TYPE(o.?);
    return if (tp.tp_call != null) 1 else 0;
}

// Comparison operations
pub const Py_LT = 0;
pub const Py_LE = 1;
pub const Py_EQ = 2;
pub const Py_NE = 3;
pub const Py_GT = 4;
pub const Py_GE = 5;
