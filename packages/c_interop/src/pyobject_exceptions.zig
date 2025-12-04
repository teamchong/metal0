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
const exception_types = @import("exception_types.zig");
const traits = @import("pyobject_traits.zig");

// Re-export exception types
pub const ValueError = exception_types.ValueError;
pub const TypeError = exception_types.TypeError;
pub const RuntimeError = exception_types.RuntimeError;
pub const AttributeError = exception_types.AttributeError;
pub const KeyError = exception_types.KeyError;
pub const IndexError = exception_types.IndexError;
pub const OSError = exception_types.OSError;
pub const FileNotFoundError = exception_types.FileNotFoundError;
pub const SyntaxError = exception_types.SyntaxError;
pub const ImportError = exception_types.ImportError;

// Use exception_types for impl
const exception_impl = struct {
    pub fn ExceptionImpl(comptime Config: type) type {
        // Delegate to exception_types
        return exception_types.exception_impl.ExceptionImpl(Config);
    }
};

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
    _ = traits.incref(exc_value);

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
        traits.decref(exc);
    }

    // DECREF traceback
    if (global_exception_state.exc_traceback) |tb| {
        traits.decref(tb);
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

/// Set MemoryError exception
export fn PyErr_NoMemory() callconv(.c) ?*cpython.PyObject {
    PyErr_SetString(&PyExc_MemoryError, "out of memory");
    return null;
}

/// Set exception without value (type only)
export fn PyErr_SetNone(exc_type: *cpython.PyTypeObject) callconv(.c) void {
    global_exception_state = .{
        .exc_type = exc_type,
        .exc_value = null,
        .exc_traceback = null,
    };
}

/// Issue a warning
export fn PyErr_WarnEx(category: *cpython.PyTypeObject, message: [*:0]const u8, stack_level: isize) callconv(.c) c_int {
    _ = stack_level;
    std.debug.print("{s}: {s}\n", .{ category.tp_name, std.mem.span(message) });
    return 0; // Success - warning issued
}

/// Write current exception to stderr and clear it
export fn PyErr_WriteUnraisable(obj: ?*cpython.PyObject) callconv(.c) void {
    if (global_exception_state.exc_type) |exc_type| {
        std.debug.print("Exception ignored in: ", .{});
        if (obj) |o| {
            const obj_type = cpython.Py_TYPE(o);
            std.debug.print("<{s} object>\n", .{obj_type.tp_name});
        } else {
            std.debug.print("<unknown>\n", .{});
        }
        std.debug.print("{s}\n", .{exc_type.tp_name});
    }
    PyErr_Clear();
}

/// Check if argument is bad type
export fn PyErr_BadArgument() callconv(.c) c_int {
    PyErr_SetString(&PyExc_TypeError, "bad argument type for built-in operation");
    return 0;
}

/// Report internal call error
export fn PyErr_BadInternalCall() callconv(.c) void {
    PyErr_SetString(&PyExc_RuntimeError, "bad internal call");
}

/// Check for pending signals (stub)
export fn PyErr_CheckSignals() callconv(.c) c_int {
    return 0; // No signals
}

/// Set errno-based exception
export fn PyErr_SetFromErrno(exc_type: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    const errno_val = std.c._errno().*;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "errno {d}", .{errno_val}) catch "errno error";
    PyErr_SetString(exc_type, @ptrCast(msg.ptr));
    return null;
}

/// Set errno-based exception with filename
export fn PyErr_SetFromErrnoWithFilename(exc_type: *cpython.PyTypeObject, filename: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const errno_val = std.c._errno().*;
    var buf: [512]u8 = undefined;
    const fname = if (filename) |f| std.mem.span(f) else "(null)";
    const msg = std.fmt.bufPrint(&buf, "[Errno {d}] {s}", .{ errno_val, fname }) catch "errno error";
    PyErr_SetString(exc_type, @ptrCast(msg.ptr));
    return null;
}

/// Create new exception class
/// name: must be "module.classname" format
/// base: base exception type (or null for Exception)
/// dict: optional class dict (or null)
export fn PyErr_NewException(name: [*:0]const u8, base: ?*cpython.PyObject, dict: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyErr_NewExceptionWithDoc(name, null, base, dict);
}

/// Create new exception class with docstring
export fn PyErr_NewExceptionWithDoc(name: [*:0]const u8, doc: ?[*:0]const u8, base: ?*cpython.PyObject, dict: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = doc;
    _ = dict;

    // Create a new type object for the exception
    const type_obj = allocator.create(cpython.PyTypeObject) catch return null;

    // Get base type
    const base_type: *cpython.PyTypeObject = if (base) |b| @ptrCast(@alignCast(b)) else &PyExc_Exception;

    type_obj.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
            .ob_size = 0,
        },
        .tp_name = name,
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
        .tp_base = base_type,
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

    return @ptrCast(&type_obj.ob_base.ob_base);
}

/// Set syntax error location
export fn PyErr_SyntaxLocation(filename: [*:0]const u8, lineno: c_int) callconv(.c) void {
    PyErr_SyntaxLocationEx(filename, lineno, -1);
}

/// Set syntax error location with column
export fn PyErr_SyntaxLocationEx(filename: [*:0]const u8, lineno: c_int, col_offset: c_int) callconv(.c) void {
    _ = filename;
    _ = lineno;
    _ = col_offset;
    // TODO: Set location info on current SyntaxError exception
}

/// Raise interrupt exception
export fn PyErr_SetInterrupt() callconv(.c) void {
    // TODO: Set keyboard interrupt flag
}

// ============================================================================
//                         PYEXCEPTION_* C API FUNCTIONS
// ============================================================================

/// Get the __cause__ attribute of an exception
export fn PyException_GetCause(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Cast to exception type and get cause field
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));
    if (base_exc.cause) |cause| {
        _ = traits.incref(@ptrCast(cause));
        return @ptrCast(cause);
    }
    return null;
}

/// Set the __cause__ attribute of an exception (explicit chaining)
export fn PyException_SetCause(exc: *cpython.PyObject, cause: ?*cpython.PyObject) callconv(.c) void {
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));

    // DECREF old cause
    if (base_exc.cause) |old_cause| {
        traits.decref(@ptrCast(old_cause));
    }

    // Set new cause (steals reference)
    base_exc.cause = @ptrCast(cause);
}

/// Get the __context__ attribute of an exception
export fn PyException_GetContext(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));
    if (base_exc.context) |context| {
        _ = traits.incref(@ptrCast(context));
        return @ptrCast(context);
    }
    return null;
}

/// Set the __context__ attribute of an exception (implicit chaining)
export fn PyException_SetContext(exc: *cpython.PyObject, context: ?*cpython.PyObject) callconv(.c) void {
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));

    // DECREF old context
    if (base_exc.context) |old_context| {
        traits.decref(@ptrCast(old_context));
    }

    // Set new context (steals reference)
    base_exc.context = @ptrCast(context);
}

/// Get the __traceback__ attribute of an exception
export fn PyException_GetTraceback(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));
    if (base_exc.traceback) |tb| {
        _ = traits.incref(@ptrCast(tb));
        return @ptrCast(tb);
    }
    return null;
}

/// Set the __traceback__ attribute of an exception
export fn PyException_SetTraceback(exc: *cpython.PyObject, tb: ?*cpython.PyObject) callconv(.c) c_int {
    const base_exc: *PyBaseException = @ptrCast(@alignCast(exc));

    // DECREF old traceback
    if (base_exc.traceback) |old_tb| {
        traits.decref(@ptrCast(old_tb));
    }

    // Set new traceback
    if (tb) |new_tb| {
        _ = traits.incref(new_tb);
    }
    base_exc.traceback = @ptrCast(tb);
    return 0;
}

/// Get the args attribute of an exception
export fn PyException_GetArgs(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // For now, return None - full implementation would need args field in exception
    _ = exc;
    return @import("pyobject_none.zig").Py_None();
}

/// Set the args attribute of an exception
export fn PyException_SetArgs(exc: *cpython.PyObject, args: *cpython.PyObject) callconv(.c) void {
    // Stub - full implementation would set args field
    _ = exc;
    _ = args;
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

// ============================================================================
//                         ADDITIONAL EXCEPTION TYPES
// ============================================================================

// Use comptime to generate remaining exception types with minimal boilerplate
fn makeExceptionType(comptime name: [:0]const u8, comptime base: *cpython.PyTypeObject, comptime doc: [:0]const u8) cpython.PyTypeObject {
    return .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
            .ob_size = 0,
        },
        .tp_name = name,
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
        .tp_doc = doc,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = null,
        .tp_weaklistoffset = 0,
        .tp_iter = null,
        .tp_iternext = null,
        .tp_methods = null,
        .tp_members = null,
        .tp_getset = null,
        .tp_base = base,
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
}

pub var PyExc_StopIteration: cpython.PyTypeObject = makeExceptionType("StopIteration", &PyExc_Exception, "Signal the end from iterator.__next__().");
pub var PyExc_StopAsyncIteration: cpython.PyTypeObject = makeExceptionType("StopAsyncIteration", &PyExc_Exception, "Signal the end from iterator.__anext__().");
pub var PyExc_GeneratorExit: cpython.PyTypeObject = makeExceptionType("GeneratorExit", &PyExc_BaseException, "Request that a generator exit.");
pub var PyExc_ArithmeticError: cpython.PyTypeObject = makeExceptionType("ArithmeticError", &PyExc_Exception, "Base class for arithmetic errors.");
pub var PyExc_LookupError: cpython.PyTypeObject = makeExceptionType("LookupError", &PyExc_Exception, "Base class for lookup errors.");
pub var PyExc_AssertionError: cpython.PyTypeObject = makeExceptionType("AssertionError", &PyExc_Exception, "Assertion failed.");
pub var PyExc_BufferError: cpython.PyTypeObject = makeExceptionType("BufferError", &PyExc_Exception, "Buffer error.");
pub var PyExc_EOFError: cpython.PyTypeObject = makeExceptionType("EOFError", &PyExc_Exception, "Read beyond end of file.");
pub var PyExc_FloatingPointError: cpython.PyTypeObject = makeExceptionType("FloatingPointError", &PyExc_ArithmeticError, "Floating point operation failed.");
pub var PyExc_NameError: cpython.PyTypeObject = makeExceptionType("NameError", &PyExc_Exception, "Name not found globally.");
pub var PyExc_RecursionError: cpython.PyTypeObject = makeExceptionType("RecursionError", &PyExc_RuntimeError, "Recursion limit exceeded.");
pub var PyExc_ReferenceError: cpython.PyTypeObject = makeExceptionType("ReferenceError", &PyExc_Exception, "Weak ref target has been garbage collected.");
pub var PyExc_SyntaxError: cpython.PyTypeObject = makeExceptionType("SyntaxError", &PyExc_Exception, "Invalid syntax.");
pub var PyExc_SystemError: cpython.PyTypeObject = makeExceptionType("SystemError", &PyExc_Exception, "Internal error in the Python interpreter.");
pub var PyExc_UnicodeError: cpython.PyTypeObject = makeExceptionType("UnicodeError", &PyExc_ValueError, "Unicode related error.");
pub var PyExc_UnicodeDecodeError: cpython.PyTypeObject = makeExceptionType("UnicodeDecodeError", &PyExc_UnicodeError, "Unicode decoding error.");
pub var PyExc_UnicodeEncodeError: cpython.PyTypeObject = makeExceptionType("UnicodeEncodeError", &PyExc_UnicodeError, "Unicode encoding error.");
pub var PyExc_Warning: cpython.PyTypeObject = makeExceptionType("Warning", &PyExc_Exception, "Base class for warnings.");
pub var PyExc_UserWarning: cpython.PyTypeObject = makeExceptionType("UserWarning", &PyExc_Warning, "User-defined warning.");
pub var PyExc_DeprecationWarning: cpython.PyTypeObject = makeExceptionType("DeprecationWarning", &PyExc_Warning, "Deprecated feature warning.");
pub var PyExc_BytesWarning: cpython.PyTypeObject = makeExceptionType("BytesWarning", &PyExc_Warning, "Bytes warning.");
pub var PyExc_ResourceWarning: cpython.PyTypeObject = makeExceptionType("ResourceWarning", &PyExc_Warning, "Resource warning.");
pub var PyExc_ZeroDivisionError: cpython.PyTypeObject = makeExceptionType("ZeroDivisionError", &PyExc_ArithmeticError, "Division by zero.");
pub var PyExc_OverflowError: cpython.PyTypeObject = makeExceptionType("OverflowError", &PyExc_ArithmeticError, "Result too large to be represented.");
pub var PyExc_ImportError: cpython.PyTypeObject = makeExceptionType("ImportError", &PyExc_Exception, "Import can't find module.");
pub var PyExc_ModuleNotFoundError: cpython.PyTypeObject = makeExceptionType("ModuleNotFoundError", &PyExc_ImportError, "Module not found.");
pub var PyExc_OSError: cpython.PyTypeObject = makeExceptionType("OSError", &PyExc_Exception, "OS system call failed.");
pub var PyExc_FileNotFoundError: cpython.PyTypeObject = makeExceptionType("FileNotFoundError", &PyExc_OSError, "File not found.");
pub var PyExc_FileExistsError: cpython.PyTypeObject = makeExceptionType("FileExistsError", &PyExc_OSError, "File already exists.");
pub var PyExc_PermissionError: cpython.PyTypeObject = makeExceptionType("PermissionError", &PyExc_OSError, "Not permitted.");
pub var PyExc_TimeoutError: cpython.PyTypeObject = makeExceptionType("TimeoutError", &PyExc_OSError, "Timeout expired.");
pub var PyExc_ConnectionError: cpython.PyTypeObject = makeExceptionType("ConnectionError", &PyExc_OSError, "Connection error.");
pub var PyExc_BrokenPipeError: cpython.PyTypeObject = makeExceptionType("BrokenPipeError", &PyExc_ConnectionError, "Broken pipe.");
pub var PyExc_ConnectionResetError: cpython.PyTypeObject = makeExceptionType("ConnectionResetError", &PyExc_ConnectionError, "Connection reset.");
pub var PyExc_ConnectionRefusedError: cpython.PyTypeObject = makeExceptionType("ConnectionRefusedError", &PyExc_ConnectionError, "Connection refused.");
pub var PyExc_ConnectionAbortedError: cpython.PyTypeObject = makeExceptionType("ConnectionAbortedError", &PyExc_ConnectionError, "Connection aborted.");
