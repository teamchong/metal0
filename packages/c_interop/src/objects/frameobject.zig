/// PyFrameObject - Stack frame objects
///
/// Frame objects represent execution frames (stack frames) in Python.
/// They contain local variables, code being executed, and execution state.
///
/// Reference: cpython/Include/cpython/frameobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// PyFrameObject - Execution frame structure
/// NOTE: CPython 3.11+ uses a very different internal structure.
/// This is a simplified version for basic compatibility.
pub const PyFrameObject = extern struct {
    ob_base: cpython.PyVarObject,
    f_back: ?*PyFrameObject, // Previous stack frame (toward caller)
    f_code: ?*cpython.PyObject, // Code object being executed
    f_builtins: ?*cpython.PyObject, // Builtins namespace
    f_globals: ?*cpython.PyObject, // Global namespace
    f_locals: ?*cpython.PyObject, // Local namespace
    f_valuestack: ?*cpython.PyObject, // Points after the last local
    f_trace: ?*cpython.PyObject, // Trace function
    f_gen: ?*cpython.PyObject, // Generator/coroutine that owns this frame (if any)
    f_trace_lines: c_int, // Emit per-line trace events?
    f_trace_opcodes: c_int, // Emit per-opcode trace events?
    f_lineno: c_int, // Current line number
    f_lasti: c_int, // Last instruction index
    // In CPython 3.11+, localsplus follows here as flexible array
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyFrame_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "frame",
    .tp_basicsize = @sizeOf(PyFrameObject),
    .tp_itemsize = @sizeOf(*cpython.PyObject), // For localsplus
    .tp_dealloc = frame_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = frame_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Frame object",
    .tp_traverse = null,
    .tp_clear = frame_clear,
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

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Create a new frame object
pub export fn PyFrame_New(
    tstate: ?*anyopaque, // PyThreadState*
    code: *cpython.PyObject,
    globals: *cpython.PyObject,
    locals: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    _ = tstate;

    const frame = allocator.create(PyFrameObject) catch return null;

    frame.ob_base.ob_base.ob_refcnt = 1;
    frame.ob_base.ob_base.ob_type = &PyFrame_Type;
    frame.ob_base.ob_size = 0;
    frame.f_back = null;
    frame.f_code = traits.incref(code);
    frame.f_builtins = null;
    frame.f_globals = traits.incref(globals);
    frame.f_locals = if (locals) |l| traits.incref(l) else null;
    frame.f_valuestack = null;
    frame.f_trace = null;
    frame.f_trace_lines = 1;
    frame.f_trace_opcodes = 0;
    frame.f_lineno = 0;
    frame.f_lasti = -1;

    return @ptrCast(&frame.ob_base.ob_base);
}

/// Get code object from frame
pub export fn PyFrame_GetCode(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    if (f.f_code) |code| {
        return traits.incref(code);
    }
    return null;
}

/// Get previous frame (toward caller)
pub export fn PyFrame_GetBack(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    if (f.f_back) |back| {
        return traits.incref(@ptrCast(&back.ob_base.ob_base));
    }
    return null;
}

/// Get locals dict from frame
pub export fn PyFrame_GetLocals(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    if (f.f_locals) |locals| {
        return traits.incref(locals);
    }
    return null;
}

/// Get globals dict from frame
pub export fn PyFrame_GetGlobals(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    if (f.f_globals) |globals| {
        return traits.incref(globals);
    }
    return null;
}

/// Get builtins dict from frame
pub export fn PyFrame_GetBuiltins(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    if (f.f_builtins) |builtins| {
        return traits.incref(builtins);
    }
    return null;
}

/// Get current line number
pub export fn PyFrame_GetLineNumber(frame: *cpython.PyObject) callconv(.c) c_int {
    if (PyFrame_Check(frame) == 0) return -1;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    return f.f_lineno;
}

/// Get last instruction index
pub export fn PyFrame_GetLasti(frame: *cpython.PyObject) callconv(.c) c_int {
    if (PyFrame_Check(frame) == 0) return -1;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));
    return f.f_lasti;
}

/// Get generator that owns this frame (if any)
pub export fn PyFrame_GetGenerator(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyFrame_Check(frame) == 0) return null;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));

    // The generator field tracks which generator (if any) owns this frame
    if (f.f_gen) |gen| {
        return traits.incref(gen);
    }
    return null;
}

/// Check if object is a frame
pub export fn PyFrame_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFrame_Type) 1 else 0;
}

/// Fast locals to dict
/// Copies fast local variables to the f_locals dict for introspection
pub export fn PyFrame_FastToLocalsWithError(frame: *cpython.PyObject) callconv(.c) c_int {
    if (PyFrame_Check(frame) == 0) return -1;
    const f: *PyFrameObject = @ptrCast(@alignCast(frame));

    // Ensure we have a locals dict
    if (f.f_locals == null) {
        const pydict = @import("dictobject.zig");
        f.f_locals = pydict.PyDict_New();
        if (f.f_locals == null) return -1;
    }

    // In metal0's AOT compilation model, local variables are Zig stack variables,
    // not stored in a separate fast locals array like CPython's interpreter.
    // The f_locals dict is already the canonical source for locals.
    // Nothing to copy.

    return 0;
}

/// Fast locals to dict (ignores errors)
pub export fn PyFrame_FastToLocals(frame: *cpython.PyObject) callconv(.c) void {
    _ = PyFrame_FastToLocalsWithError(frame);
}

/// Dict to fast locals
/// Copies the f_locals dict back to fast local variables
pub export fn PyFrame_LocalsToFast(frame: *cpython.PyObject, clear: c_int) callconv(.c) void {
    _ = clear;
    if (PyFrame_Check(frame) == 0) return;

    // In metal0's AOT compilation model, local variables are Zig stack variables.
    // The f_locals dict is the canonical source, so there's nothing to copy back.
    // This function exists for CPython compatibility.
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn frame_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const frame: *PyFrameObject = @ptrCast(@alignCast(obj));

    if (frame.f_code) |c| traits.decref(c);
    if (frame.f_builtins) |b| traits.decref(b);
    if (frame.f_globals) |g| traits.decref(g);
    if (frame.f_locals) |l| traits.decref(l);
    if (frame.f_trace) |t| traits.decref(t);

    allocator.destroy(frame);
}

fn frame_clear(obj: *cpython.PyObject) callconv(.c) c_int {
    const frame: *PyFrameObject = @ptrCast(@alignCast(obj));

    if (frame.f_locals) |l| {
        traits.decref(l);
        frame.f_locals = null;
    }
    if (frame.f_trace) |t| {
        traits.decref(t);
        frame.f_trace = null;
    }

    return 0;
}

fn frame_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const frame: *PyFrameObject = @ptrCast(@alignCast(obj));
    const unicode = @import("../include/unicodeobject.zig");

    var buf: [128]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "<frame at 0x{x}, line {d}>", .{
        @intFromPtr(obj),
        frame.f_lineno,
    }) catch return null;
    return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
}

// ============================================================================
// TESTS
// ============================================================================

test "PyFrameObject layout" {
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyFrameObject, "f_back"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyFrameObject, "f_code"));
}

test "frame exports" {
    _ = PyFrame_New;
    _ = PyFrame_GetCode;
    _ = PyFrame_GetLineNumber;
    _ = PyFrame_Check;
}
