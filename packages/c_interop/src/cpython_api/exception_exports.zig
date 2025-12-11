/// Exception Type Exports
/// C extensions access exception types via global symbol lookup.

const cpython = @import("../include/object.zig");
const exceptions = @import("../objects/exceptions.zig");

export fn _get_PyExc_BaseException() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_BaseException;
}

export fn _get_PyExc_Exception() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_Exception;
}

export fn _get_PyExc_TypeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_TypeError;
}

export fn _get_PyExc_ValueError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ValueError;
}

export fn _get_PyExc_RuntimeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RuntimeError;
}

export fn _get_PyExc_AttributeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_AttributeError;
}

export fn _get_PyExc_KeyError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_KeyError;
}

export fn _get_PyExc_IndexError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_IndexError;
}

export fn _get_PyExc_MemoryError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_MemoryError;
}

export fn _get_PyExc_NotImplementedError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_NotImplementedError;
}

export fn _get_PyExc_StopIteration() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_StopIteration;
}

export fn _get_PyExc_OverflowError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_OverflowError;
}

export fn _get_PyExc_ZeroDivisionError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ZeroDivisionError;
}

export fn _get_PyExc_FloatingPointError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_FloatingPointError;
}

export fn _get_PyExc_OSError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_OSError;
}

export fn _get_PyExc_IOError() callconv(.c) *cpython.PyTypeObject {
    // IOError is alias for OSError in Python 3
    return &exceptions.PyExc_OSError;
}

export fn _get_PyExc_ImportError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ImportError;
}

export fn _get_PyExc_NameError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_NameError;
}

export fn _get_PyExc_RecursionError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RecursionError;
}

export fn _get_PyExc_SystemError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_SystemError;
}

export fn _get_PyExc_UnicodeDecodeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UnicodeDecodeError;
}

export fn _get_PyExc_UnicodeEncodeError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UnicodeEncodeError;
}

export fn _get_PyExc_BufferError() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_BufferError;
}

export fn _get_PyExc_DeprecationWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_DeprecationWarning;
}

export fn _get_PyExc_RuntimeWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_RuntimeWarning;
}

export fn _get_PyExc_UserWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_UserWarning;
}

export fn _get_PyExc_FutureWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_FutureWarning;
}

export fn _get_PyExc_ImportWarning() callconv(.c) *cpython.PyTypeObject {
    return &exceptions.PyExc_ImportWarning;
}
