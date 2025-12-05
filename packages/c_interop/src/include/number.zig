/// CPython Number Protocol Implementation
///
/// This implements the number protocol for arithmetic operations.
/// Critical for NumPy array arithmetic (+, -, *, /, etc.)

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyErr_SetString = traits.externs.PyErr_SetString;

/// Check if object is a number
export fn PyNumber_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |_| {
        return 1;
    }
    
    return 0;
}

/// Add two numbers
export fn PyNumber_Add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_add) |add_func| {
            return add_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for +");
    return null;
}

/// Subtract two numbers
export fn PyNumber_Subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_subtract) |sub_func| {
            return sub_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for -");
    return null;
}

/// Multiply two numbers
export fn PyNumber_Multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_multiply) |mul_func| {
            return mul_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for *");
    return null;
}

/// Matrix multiply (NumPy @)
export fn PyNumber_MatrixMultiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_matrix_multiply) |matmul_func| {
            return matmul_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for @");
    return null;
}

/// Floor division
export fn PyNumber_FloorDivide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_floor_divide) |div_func| {
            return div_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for //");
    return null;
}

/// True division
export fn PyNumber_TrueDivide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_true_divide) |div_func| {
            return div_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for /");
    return null;
}

/// Remainder
export fn PyNumber_Remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_remainder) |mod_func| {
            return mod_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for %");
    return null;
}

/// Divmod
export fn PyNumber_Divmod(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_divmod) |divmod_func| {
            return divmod_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for divmod()");
    return null;
}

/// Power
export fn PyNumber_Power(a: *cpython.PyObject, b: *cpython.PyObject, c: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_power) |pow_func| {
            return pow_func(a, b, c orelse @ptrFromInt(0));
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for **");
    return null;
}

/// Negative
export fn PyNumber_Negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_negative) |neg_func| {
            return neg_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "bad operand type for unary -");
    return null;
}

/// Positive
export fn PyNumber_Positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_positive) |pos_func| {
            return pos_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "bad operand type for unary +");
    return null;
}

/// Absolute value
export fn PyNumber_Absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_absolute) |abs_func| {
            return abs_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "bad operand type for abs()");
    return null;
}

/// Invert
export fn PyNumber_Invert(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_invert) |invert_func| {
            return invert_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "bad operand type for unary ~");
    return null;
}

/// Left shift
export fn PyNumber_Lshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_lshift) |lshift_func| {
            return lshift_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for <<");
    return null;
}

/// Right shift
export fn PyNumber_Rshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_rshift) |rshift_func| {
            return rshift_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for >>");
    return null;
}

/// Bitwise AND
export fn PyNumber_And(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_and) |and_func| {
            return and_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for &");
    return null;
}

/// Bitwise XOR
export fn PyNumber_Xor(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_xor) |xor_func| {
            return xor_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for ^");
    return null;
}

/// Bitwise OR
export fn PyNumber_Or(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_or) |or_func| {
            return or_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "unsupported operand type(s) for |");
    return null;
}

/// In-place add
export fn PyNumber_InPlaceAdd(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_add) |iadd_func| {
            return iadd_func(a, b);
        }
    }
    
    // Fallback to regular add
    return PyNumber_Add(a, b);
}

/// In-place subtract
export fn PyNumber_InPlaceSubtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_subtract) |isub_func| {
            return isub_func(a, b);
        }
    }
    
    // Fallback to regular subtract
    return PyNumber_Subtract(a, b);
}

/// In-place multiply
export fn PyNumber_InPlaceMultiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_multiply) |imul_func| {
            return imul_func(a, b);
        }
    }

    // Fallback to regular multiply
    return PyNumber_Multiply(a, b);
}

/// In-place floor divide
export fn PyNumber_InPlaceFloorDivide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_floor_divide) |idiv_func| {
            return idiv_func(a, b);
        }
    }

    // Fallback to regular floor divide
    return PyNumber_FloorDivide(a, b);
}

/// In-place true divide
export fn PyNumber_InPlaceTrueDivide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_true_divide) |idiv_func| {
            return idiv_func(a, b);
        }
    }

    // Fallback to regular true divide
    return PyNumber_TrueDivide(a, b);
}

/// In-place remainder
export fn PyNumber_InPlaceRemainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_remainder) |imod_func| {
            return imod_func(a, b);
        }
    }

    // Fallback to regular remainder
    return PyNumber_Remainder(a, b);
}

/// In-place power
export fn PyNumber_InPlacePower(a: *cpython.PyObject, b: *cpython.PyObject, c: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_power) |ipow_func| {
            return ipow_func(a, b, c orelse @ptrFromInt(0));
        }
    }

    // Fallback to regular power
    return PyNumber_Power(a, b, c);
}

/// In-place left shift
export fn PyNumber_InPlaceLshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_lshift) |ilshift_func| {
            return ilshift_func(a, b);
        }
    }

    // Fallback to regular left shift
    return PyNumber_Lshift(a, b);
}

/// In-place right shift
export fn PyNumber_InPlaceRshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_rshift) |irshift_func| {
            return irshift_func(a, b);
        }
    }

    // Fallback to regular right shift
    return PyNumber_Rshift(a, b);
}

/// In-place AND
export fn PyNumber_InPlaceAnd(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_and) |iand_func| {
            return iand_func(a, b);
        }
    }

    // Fallback to regular AND
    return PyNumber_And(a, b);
}

/// In-place XOR
export fn PyNumber_InPlaceXor(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_xor) |ixor_func| {
            return ixor_func(a, b);
        }
    }

    // Fallback to regular XOR
    return PyNumber_Xor(a, b);
}

/// In-place OR
export fn PyNumber_InPlaceOr(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_or) |ior_func| {
            return ior_func(a, b);
        }
    }

    // Fallback to regular OR
    return PyNumber_Or(a, b);
}

/// In-place matrix multiply
export fn PyNumber_InPlaceMatrixMultiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);

    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_inplace_matrix_multiply) |imatmul_func| {
            return imatmul_func(a, b);
        }
    }

    // Fallback to regular matrix multiply
    return PyNumber_MatrixMultiply(a, b);
}

/// Convert to long
export fn PyNumber_Long(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_int) |int_func| {
            return int_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "int() argument must be a number");
    return null;
}

/// Convert to float
export fn PyNumber_Float(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_float) |float_func| {
            return float_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "float() argument must be a number");
    return null;
}

/// Get index value
export fn PyNumber_Index(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_index) |index_func| {
            return index_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object cannot be interpreted as an integer");
    return null;
}

/// Convert to C ssize_t
export fn PyNumber_AsSsize_t(obj: *cpython.PyObject, exc: ?*cpython.PyObject) callconv(.c) isize {
    _ = exc;
    const pylong = @import("../objects/longobject.zig");

    // Try to convert to long first
    const long_obj = PyNumber_Long(obj);
    if (long_obj == null) return -1;
    defer if (long_obj) |l| Py_DECREF(l);

    // Extract value
    return pylong.PyLong_AsSsize_t(long_obj.?);
}

/// Check if object can be used as an index
export fn PyIndex_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_as_number) |number_procs| {
        if (number_procs.nb_index != null) return 1;
    }
    return 0;
}

/// Convert integer to string in given base (2, 8, 10, or 16)
export fn PyNumber_ToBase(n: *cpython.PyObject, base: c_int) callconv(.c) ?*cpython.PyObject {
    const pylong = @import("../objects/longobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    // First ensure we have an integer
    const flags = cpython.Py_TYPE(n).tp_flags;
    if ((flags & cpython.Py_TPFLAGS_LONG_SUBCLASS) == 0) {
        PyErr_SetString(@ptrFromInt(0), "expected integer");
        return null;
    }

    // Get the value
    const value = pylong.PyLong_AsLong(n);

    // Format buffer
    var buf: [128]u8 = undefined;
    var len: usize = 0;

    // Format based on base
    if (base == 2) {
        // Binary
        const fmt = std.fmt.bufPrint(&buf, "0b{b}", .{@as(u64, @intCast(if (value < 0) -value else value))}) catch return null;
        len = fmt.len;
    } else if (base == 8) {
        // Octal
        const fmt = std.fmt.bufPrint(&buf, "0o{o}", .{@as(u64, @intCast(if (value < 0) -value else value))}) catch return null;
        len = fmt.len;
    } else if (base == 16) {
        // Hex
        const fmt = std.fmt.bufPrint(&buf, "0x{x}", .{@as(u64, @intCast(if (value < 0) -value else value))}) catch return null;
        len = fmt.len;
    } else {
        // Decimal (base 10)
        const fmt = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return null;
        len = fmt.len;
    }

    // Handle negative sign
    if (value < 0 and base != 10) {
        // Move content right and add minus sign
        var temp: [128]u8 = undefined;
        temp[0] = '-';
        @memcpy(temp[1 .. len + 1], buf[0..len]);
        @memcpy(buf[0 .. len + 1], temp[0 .. len + 1]);
        len += 1;
    }

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

// Tests
test "PyNumber function exports" {
    // Just verify functions exist and can be referenced
    _ = PyNumber_Check;
    _ = PyNumber_Add;
    _ = PyNumber_Multiply;
    _ = PyNumber_MatrixMultiply;
}
