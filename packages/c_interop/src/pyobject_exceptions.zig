/// Core Python exception types using comptime exception_impl
///
/// Pattern: Reuse exception_impl with different configs
/// - 10 core exception types
/// - All share same implementation
/// - Only difference: config (name, extra fields)
///
/// RESULT: 20 lines per exception instead of 200!

const std = @import("std");
const cpython = @import("cpython_object.zig");
const exception_impl = @import("collections");  // Will be added to build

const allocator = std.heap.c_allocator;

// ============================================================================
//                         CORE EXCEPTION TYPES
// ============================================================================

/// BaseException - root of exception hierarchy
const BaseExceptionConfig = struct {
    pub const name = "BaseException";
    pub const doc = "Common base class for all exceptions";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyBaseException = exception_impl.ExceptionImpl(BaseExceptionConfig);

/// Exception - base for all built-in exceptions
const ExceptionConfig = struct {
    pub const name = "Exception";
    pub const doc = "Common base class for all non-exit exceptions";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyException = exception_impl.ExceptionImpl(ExceptionConfig);

/// ValueError - invalid value
const ValueErrorConfig = struct {
    pub const name = "ValueError";
    pub const doc = "Inappropriate argument value (of correct type)";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyValueError = exception_impl.ExceptionImpl(ValueErrorConfig);

/// TypeError - wrong type
const TypeErrorConfig = struct {
    pub const name = "TypeError";
    pub const doc = "Inappropriate argument type";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyTypeError = exception_impl.ExceptionImpl(TypeErrorConfig);

/// RuntimeError - generic runtime error
const RuntimeErrorConfig = struct {
    pub const name = "RuntimeError";
    pub const doc = "Unspecified run-time error";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyRuntimeError = exception_impl.ExceptionImpl(RuntimeErrorConfig);

/// AttributeError - attribute not found
const AttributeErrorConfig = struct {
    pub const name = "AttributeError";
    pub const doc = "Attribute not found";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyAttributeError = exception_impl.ExceptionImpl(AttributeErrorConfig);

/// KeyError - key not found in mapping
const KeyErrorConfig = struct {
    pub const name = "KeyError";
    pub const doc = "Mapping key not found";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyKeyError = exception_impl.ExceptionImpl(KeyErrorConfig);

/// IndexError - index out of range
const IndexErrorConfig = struct {
    pub const name = "IndexError";
    pub const doc = "Sequence index out of range";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyIndexError = exception_impl.ExceptionImpl(IndexErrorConfig);

/// MemoryError - out of memory
const MemoryErrorConfig = struct {
    pub const name = "MemoryError";
    pub const doc = "Out of memory";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyMemoryError = exception_impl.ExceptionImpl(MemoryErrorConfig);

/// NotImplementedError - feature not implemented
const NotImplementedErrorConfig = struct {
    pub const name = "NotImplementedError";
    pub const doc = "Method or function hasn't been implemented yet";
    pub const has_cause = true;
    pub const has_context = true;
};

pub const PyNotImplementedError = exception_impl.ExceptionImpl(NotImplementedErrorConfig);

// ============================================================================
//                         EXCEPTION STATE MANAGEMENT
// ============================================================================

/// Thread-local exception state
const ExceptionState = struct {
    exc_type: ?*cpython.PyTypeObject,
    exc_value: ?*cpython.PyObject,
    exc_traceback: ?*cpython.PyObject,
};

// Global exception state (TODO: make thread-local)
var global_exception_state: ExceptionState = .{
    .exc_type = null,
    .exc_value = null,
    .exc_traceback = null,
};

// ============================================================================
//                         PYERR_* C API FUNCTIONS
// ============================================================================

/// Set exception with string message
export fn PyErr_SetString(exc_type: *cpython.PyTypeObject, message: [*:0]const u8) callconv(.c) void {
    // Convert C string to PyUnicode
    const msg_str = std.mem.span(message);
    const py_msg = @import("pyobject_unicode.zig").PyUnicode_FromString(message);

    // Create exception instance
    // TODO: Use proper exception type based on exc_type
    const exc = allocator.create(PyValueError) catch {
        // Failed to allocate exception - just set type
        global_exception_state = .{
            .exc_type = exc_type,
            .exc_value = null,
            .exc_traceback = null,
        };
        return;
    };

    exc.* = PyValueError{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = @ptrCast(exc_type),
        },
        .message = @ptrCast(py_msg),
        .traceback = null,
        .cause = null,
        .context = null,
    };

    global_exception_state = .{
        .exc_type = exc_type,
        .exc_value = @ptrCast(&exc.ob_base),
        .exc_traceback = null,
    };
}

/// Set exception with object
export fn PyErr_SetObject(exc_type: *cpython.PyTypeObject, exc_value: *cpython.PyObject) callconv(.c) void {
    // INCREF the exception value
    exc_value.ob_refcnt += 1;

    // Clear previous exception
    PyErr_Clear();

    global_exception_state = .{
        .exc_type = exc_type,
        .exc_value = exc_value,
        .exc_traceback = null,
    };
}

/// Check if exception occurred
export fn PyErr_Occurred() callconv(.c) ?*cpython.PyTypeObject {
    return global_exception_state.exc_type;
}

/// Clear current exception
export fn PyErr_Clear() callconv(.c) void {
    // DECREF exception value
    if (global_exception_state.exc_value) |exc| {
        exc.ob_refcnt -= 1;
        // TODO: Dealloc if refcnt == 0
    }

    // DECREF traceback
    if (global_exception_state.exc_traceback) |tb| {
        tb.ob_refcnt -= 1;
    }

    global_exception_state = .{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
    };
}

/// Print current exception
export fn PyErr_Print() callconv(.c) void {
    if (global_exception_state.exc_type) |exc_type| {
        const type_name = exc_type.tp_name;

        if (global_exception_state.exc_value) |exc_value| {
            // Try to get string representation
            const str_obj = cpython.PyObject_Str(exc_value);
            if (str_obj) |s| {
                const msg = @import("pyobject_unicode.zig").PyUnicode_AsUTF8(s);
                std.debug.print("{s}: {s}\n", .{ type_name, std.mem.span(msg) });
            } else {
                std.debug.print("{s}\n", .{type_name});
            }
        } else {
            std.debug.print("{s}\n", .{type_name});
        }

        // Print traceback if available
        if (global_exception_state.exc_traceback) |_| {
            std.debug.print("  (traceback not implemented)\n", .{});
        }
    }

    PyErr_Clear();
}

/// Format and set exception
export fn PyErr_Format(exc_type: *cpython.PyTypeObject, format: [*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    // TODO: Implement actual formatting with varargs
    // For now: just use format string as message
    PyErr_SetString(exc_type, format);
    return null;
}

/// Check if exception matches type
export fn PyErr_ExceptionMatches(exc: *cpython.PyTypeObject) callconv(.c) c_int {
    if (global_exception_state.exc_type) |current_type| {
        return if (current_type == exc) 1 else 0;
    }
    return 0;
}

/// Check if object is exception instance
export fn PyErr_GivenExceptionMatches(err: *cpython.PyObject, exc: *cpython.PyObject) callconv(.c) c_int {
    const err_type = cpython.Py_TYPE(err);
    const exc_type = @as(*cpython.PyTypeObject, @ptrCast(exc));
    return if (err_type == exc_type) 1 else 0;
}

/// Restore exception state (for exception handling)
export fn PyErr_Restore(exc_type: ?*cpython.PyTypeObject, exc_value: ?*cpython.PyObject, exc_tb: ?*cpython.PyObject) callconv(.c) void {
    PyErr_Clear();

    global_exception_state = .{
        .exc_type = exc_type,
        .exc_value = exc_value,
        .exc_traceback = exc_tb,
    };
}

/// Fetch exception state (transfers ownership)
export fn PyErr_Fetch(p_type: *?*cpython.PyTypeObject, p_value: *?*cpython.PyObject, p_tb: *?*cpython.PyObject) callconv(.c) void {
    p_type.* = global_exception_state.exc_type;
    p_value.* = global_exception_state.exc_value;
    p_tb.* = global_exception_state.exc_traceback;

    // Clear state without DECREFing (ownership transferred)
    global_exception_state = .{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
    };
}

/// Normalize exception (ensure exc_value is instance of exc_type)
export fn PyErr_NormalizeException(p_type: *?*cpython.PyTypeObject, p_value: *?*cpython.PyObject, p_tb: *?*cpython.PyObject) callconv(.c) void {
    // TODO: Implement normalization
    // For now: no-op
    _ = p_type;
    _ = p_value;
    _ = p_tb;
}

// ============================================================================
//                         TYPE OBJECTS
// ============================================================================

pub var PyExc_BaseException: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "BaseException",
    .tp_basicsize = @sizeOf(PyBaseException),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = BaseExceptionConfig.doc,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_Exception: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "Exception",
    .tp_basicsize = @sizeOf(PyException),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = ExceptionConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_BaseException,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_ValueError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "ValueError",
    .tp_basicsize = @sizeOf(PyValueError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = ValueErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_TypeError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "TypeError",
    .tp_basicsize = @sizeOf(PyTypeError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = TypeErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_RuntimeError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "RuntimeError",
    .tp_basicsize = @sizeOf(PyRuntimeError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = RuntimeErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_KeyError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "KeyError",
    .tp_basicsize = @sizeOf(PyKeyError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = KeyErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_AttributeError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "AttributeError",
    .tp_basicsize = @sizeOf(PyAttributeError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = AttributeErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_IndexError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "IndexError",
    .tp_basicsize = @sizeOf(PyIndexError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = IndexErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_MemoryError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "MemoryError",
    .tp_basicsize = @sizeOf(PyMemoryError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = MemoryErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_Exception,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyExc_NotImplementedError: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "NotImplementedError",
    .tp_basicsize = @sizeOf(PyNotImplementedError),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
    .tp_doc = NotImplementedErrorConfig.doc,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyExc_RuntimeError,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};
