/// Exception Type Exports
/// C extensions access exception types via global symbol lookup.

const cpython = @import("../include/object.zig");
const exceptions = @import("../objects/exceptions.zig");

pub export fn _get_PyExc_BaseException() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_BaseException;
}

pub export fn _get_PyExc_Exception() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_Exception;
}

pub export fn _get_PyExc_TypeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_TypeError;
}

pub export fn _get_PyExc_ValueError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ValueError;
}

pub export fn _get_PyExc_RuntimeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RuntimeError;
}

pub export fn _get_PyExc_AttributeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_AttributeError;
}

pub export fn _get_PyExc_KeyError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_KeyError;
}

pub export fn _get_PyExc_IndexError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_IndexError;
}

pub export fn _get_PyExc_MemoryError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_MemoryError;
}

pub export fn _get_PyExc_NotImplementedError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_NotImplementedError;
}

pub export fn _get_PyExc_StopIteration() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_StopIteration;
}

pub export fn _get_PyExc_OverflowError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_OverflowError;
}

pub export fn _get_PyExc_ZeroDivisionError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ZeroDivisionError;
}

pub export fn _get_PyExc_FloatingPointError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_FloatingPointError;
}

pub export fn _get_PyExc_OSError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_OSError;
}

pub export fn _get_PyExc_IOError() callconv(.c) *cpython.PyTypeObject {
    // IOError is alias for OSError in Python 3
    return &exceptions.PyExc_OSError;
}

pub export fn _get_PyExc_ImportError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ImportError;
}

pub export fn _get_PyExc_NameError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_NameError;
}

pub export fn _get_PyExc_RecursionError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RecursionError;
}

pub export fn _get_PyExc_SystemError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_SystemError;
}

pub export fn _get_PyExc_UnicodeDecodeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UnicodeDecodeError;
}

pub export fn _get_PyExc_UnicodeEncodeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UnicodeEncodeError;
}

pub export fn _get_PyExc_BufferError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_BufferError;
}

pub export fn _get_PyExc_DeprecationWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_DeprecationWarning;
}

pub export fn _get_PyExc_RuntimeWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RuntimeWarning;
}

pub export fn _get_PyExc_UserWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UserWarning;
}

pub export fn _get_PyExc_FutureWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_FutureWarning;
}

pub export fn _get_PyExc_ImportWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ImportWarning;
}
