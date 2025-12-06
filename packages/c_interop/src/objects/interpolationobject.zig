/// Interpolation Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/interpolationobject.c
/// t-string Interpolation object for PEP 750 template strings
///
/// Reference: cpython/Objects/interpolationobject.c
/// Memory layout matches CPython 3.14+ exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// interpolationobject - t-string interpolation
/// Reference: cpython/Objects/interpolationobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *value;
///     PyObject *expression;
///     PyObject *conversion;
///     PyObject *format_spec;
/// } interpolationobject;
pub const interpolationobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    value: ?*cpython.PyObject, // 8 bytes - the interpolated value
    expression: ?*cpython.PyObject, // 8 bytes - the source expression string
    conversion: ?*cpython.PyObject, // 8 bytes - conversion specifier ('s', 'r', 'a', or None)
    format_spec: ?*cpython.PyObject, // 8 bytes - format specification string
};

// Verify interpolationobject size: 16 + 4*8 = 48 bytes
comptime {
    if (@sizeOf(interpolationobject) != 48) {
        @compileError("interpolationobject size mismatch with CPython");
    }
}

// ============================================================================
// INTERPOLATION TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for interpolation
fn interpolation_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const interp: *interpolationobject = @ptrCast(@alignCast(self_obj.?));

    // Untrack from GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_UnTrack(@ptrCast(interp));

    // Clear references
    _ = interpolation_clear(self_obj);

    // Free the object
    const ptr: [*]u8 = @ptrCast(interp);
    allocator.free(ptr[0..@sizeOf(interpolationobject)]);
}

/// Traverse for interpolation (GC)
fn interpolation_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const interp: *interpolationobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (interp.value) |value| {
            const result = v(value, arg);
            if (result != 0) return result;
        }
        if (interp.expression) |expr| {
            const result = v(expr, arg);
            if (result != 0) return result;
        }
        if (interp.conversion) |conv| {
            const result = v(conv, arg);
            if (result != 0) return result;
        }
        if (interp.format_spec) |fspec| {
            const result = v(fspec, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for interpolation (GC)
fn interpolation_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const interp: *interpolationobject = @ptrCast(@alignCast(self_obj.?));

    if (interp.value) |value| {
        value.ob_refcnt -= 1;
        interp.value = null;
    }
    if (interp.expression) |expr| {
        expr.ob_refcnt -= 1;
        interp.expression = null;
    }
    if (interp.conversion) |conv| {
        conv.ob_refcnt -= 1;
        interp.conversion = null;
    }
    if (interp.format_spec) |fspec| {
        fspec.ob_refcnt -= 1;
        interp.format_spec = null;
    }
    return 0;
}

/// Repr for interpolation
fn interpolation_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const interp: *interpolationobject = @ptrCast(@alignCast(self_obj.?));

    // Format: Interpolation(value, expression='...', conversion=..., format_spec='...')
    _ = interp;
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("Interpolation(...)");
}

/// Hash for interpolation (unhashable)
fn interpolation_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    _ = self_obj;
    // Interpolation objects are unhashable
    return -1;
}

/// Rich comparison for interpolation
fn interpolation_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return &object_mod._Py_NotImplementedStruct;
    }

    // Must be another Interpolation
    if (other.ob_type != &_PyInterpolation_Type) {
        if (op == object_mod.Py_EQ) return pybool.Py_False;
        return pybool.Py_True;
    }

    const i1: *interpolationobject = @ptrCast(@alignCast(self_obj));
    const i2: *interpolationobject = @ptrCast(@alignCast(other));

    // Compare all fields
    var equal = true;

    // Compare value
    if (i1.value != i2.value) {
        if (i1.value == null or i2.value == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(i1.value, i2.value, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    // Compare expression
    if (equal and i1.expression != i2.expression) {
        if (i1.expression == null or i2.expression == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(i1.expression, i2.expression, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    // Compare conversion
    if (equal and i1.conversion != i2.conversion) {
        if (i1.conversion == null or i2.conversion == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(i1.conversion, i2.conversion, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    // Compare format_spec
    if (equal and i1.format_spec != i2.format_spec) {
        if (i1.format_spec == null or i2.format_spec == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(i1.format_spec, i2.format_spec, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    if (op == object_mod.Py_EQ) {
        return if (equal) pybool.Py_True else pybool.Py_False;
    } else {
        return if (equal) pybool.Py_False else pybool.Py_True;
    }
}

/// New for interpolation
fn interpolation_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(interpolationobject), @sizeOf(interpolationobject)) catch return null;
    const interp: *interpolationobject = @ptrCast(@alignCast(mem.ptr));

    interp.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyInterpolation_Type,
        },
        .value = null,
        .expression = null,
        .conversion = null,
        .format_spec = null,
    };

    // Track in GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_Track(@ptrCast(interp));

    return @ptrCast(interp);
}

/// _PyInterpolation_Type - the Interpolation type object
pub export var _PyInterpolation_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "string.templatelib.Interpolation",
    .tp_basicsize = @sizeOf(interpolationobject),
    .tp_itemsize = 0,
    .tp_dealloc = interpolation_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = interpolation_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = interpolation_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Interpolation object for t-string template literals",
    .tp_traverse = interpolation_traverse,
    .tp_clear = interpolation_clear,
    .tp_richcompare = interpolation_richcompare,
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
    .tp_new = interpolation_new,
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

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Check if object is an Interpolation
pub export fn _PyInterpolation_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &_PyInterpolation_Type) 1 else 0;
}

/// Check if object is exactly an Interpolation (not subclass)
pub export fn _PyInterpolation_CheckExact(op: ?*cpython.PyObject) c_int {
    return _PyInterpolation_Check(op);
}

/// Create a new Interpolation object
pub export fn _PyInterpolation_New(value: ?*cpython.PyObject, expression: ?*cpython.PyObject, conversion: ?*cpython.PyObject, format_spec: ?*cpython.PyObject) ?*cpython.PyObject {
    const obj = interpolation_new(&_PyInterpolation_Type, null, null);
    if (obj == null) return null;

    const interp: *interpolationobject = @ptrCast(@alignCast(obj.?));

    if (value) |v| {
        v.ob_refcnt += 1;
        interp.value = v;
    }
    if (expression) |e| {
        e.ob_refcnt += 1;
        interp.expression = e;
    }
    if (conversion) |c| {
        c.ob_refcnt += 1;
        interp.conversion = c;
    }
    if (format_spec) |f| {
        f.ob_refcnt += 1;
        interp.format_spec = f;
    }

    return obj;
}

/// Get the value from an Interpolation
pub export fn _PyInterpolation_GetValue(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyInterpolation_Check(op) == 0) return null;

    const interp: *interpolationobject = @ptrCast(@alignCast(op.?));
    if (interp.value) |v| {
        v.ob_refcnt += 1;
        return v;
    }
    return null;
}

/// Get the expression from an Interpolation
pub export fn _PyInterpolation_GetExpression(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyInterpolation_Check(op) == 0) return null;

    const interp: *interpolationobject = @ptrCast(@alignCast(op.?));
    if (interp.expression) |e| {
        e.ob_refcnt += 1;
        return e;
    }
    return null;
}

/// Get the conversion from an Interpolation
pub export fn _PyInterpolation_GetConversion(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyInterpolation_Check(op) == 0) return null;

    const interp: *interpolationobject = @ptrCast(@alignCast(op.?));
    if (interp.conversion) |c| {
        c.ob_refcnt += 1;
        return c;
    }
    return null;
}

/// Get the format_spec from an Interpolation
pub export fn _PyInterpolation_GetFormatSpec(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyInterpolation_Check(op) == 0) return null;

    const interp: *interpolationobject = @ptrCast(@alignCast(op.?));
    if (interp.format_spec) |f| {
        f.ob_refcnt += 1;
        return f;
    }
    return null;
}
