/// Template Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/templateobject.c
/// t-string Template object for PEP 750 template strings
///
/// Reference: cpython/Objects/templateobject.c
/// Memory layout matches CPython 3.14+ exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// templateobject - t-string template
/// Reference: cpython/Objects/templateobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *strings;
///     PyObject *interpolations;
/// } templateobject;
pub const templateobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    strings: ?*cpython.PyObject, // 8 bytes - tuple of string parts
    interpolations: ?*cpython.PyObject, // 8 bytes - tuple of Interpolation objects
};

// Verify templateobject size: 16 + 2*8 = 32 bytes
comptime {
    if (@sizeOf(templateobject) != 32) {
        @compileError("templateobject size mismatch with CPython");
    }
}

/// templateiterobject - Template iterator
/// Reference: cpython/Objects/templateobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *stringsiter;
///     PyObject *interpolationsiter;
///     int from_strings;
/// } templateiterobject;
pub const templateiterobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    stringsiter: ?*cpython.PyObject, // 8 bytes - iterator over strings
    interpolationsiter: ?*cpython.PyObject, // 8 bytes - iterator over interpolations
    from_strings: c_int, // 4 bytes - flag for alternating iteration
    _pad: [4]u8, // 4 bytes padding
};

// Verify templateiterobject size: 16 + 8 + 8 + 4 + 4 = 40 bytes
comptime {
    if (@sizeOf(templateiterobject) != 40) {
        @compileError("templateiterobject size mismatch with CPython");
    }
}

// ============================================================================
// TEMPLATE TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for template
fn template_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const tmpl: *templateobject = @ptrCast(@alignCast(self_obj.?));

    // Untrack from GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_UnTrack(@ptrCast(tmpl));

    // Clear references
    _ = template_clear(self_obj);

    // Free the object
    const ptr: [*]u8 = @ptrCast(tmpl);
    allocator.free(ptr[0..@sizeOf(templateobject)]);
}

/// Traverse for template (GC)
fn template_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const tmpl: *templateobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (tmpl.strings) |strings| {
            const result = v(strings, arg);
            if (result != 0) return result;
        }
        if (tmpl.interpolations) |interps| {
            const result = v(interps, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for template (GC)
fn template_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const tmpl: *templateobject = @ptrCast(@alignCast(self_obj.?));

    if (tmpl.strings) |strings| {
        strings.ob_refcnt -= 1;
        tmpl.strings = null;
    }
    if (tmpl.interpolations) |interps| {
        interps.ob_refcnt -= 1;
        tmpl.interpolations = null;
    }
    return 0;
}

/// Repr for template
fn template_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;

    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("Template(...)");
}

/// Iter for template - returns iterator that alternates strings and interpolations
fn template_iter(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const tmpl: *templateobject = @ptrCast(@alignCast(self_obj));

    const mem = allocator.alignedAlloc(u8, @alignOf(templateiterobject), @sizeOf(templateiterobject)) catch return null;
    const it: *templateiterobject = @ptrCast(@alignCast(mem.ptr));

    // Get iterators for strings and interpolations
    var strings_iter: ?*cpython.PyObject = null;
    var interps_iter: ?*cpython.PyObject = null;

    if (tmpl.strings) |strings| {
        if (strings.ob_type.tp_iter) |iter_fn| {
            strings_iter = iter_fn(strings);
        }
    }
    if (tmpl.interpolations) |interps| {
        if (interps.ob_type.tp_iter) |iter_fn| {
            interps_iter = iter_fn(interps);
        }
    }

    it.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyTemplateIter_Type,
        },
        .stringsiter = strings_iter,
        .interpolationsiter = interps_iter,
        .from_strings = 1, // Start with strings
        ._pad = [_]u8{0} ** 4,
    };

    // Track in GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_Track(@ptrCast(it));

    return @ptrCast(it);
}

/// Rich comparison for template
fn template_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return &object_mod._Py_NotImplementedStruct;
    }

    // Must be another Template
    if (other.ob_type != &_PyTemplate_Type) {
        if (op == object_mod.Py_EQ) return pybool.Py_False;
        return pybool.Py_True;
    }

    const t1: *templateobject = @ptrCast(@alignCast(self_obj));
    const t2: *templateobject = @ptrCast(@alignCast(other));

    // Compare strings tuple
    var equal = true;
    if (t1.strings != t2.strings) {
        if (t1.strings == null or t2.strings == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(t1.strings, t2.strings, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    // Compare interpolations tuple
    if (equal and t1.interpolations != t2.interpolations) {
        if (t1.interpolations == null or t2.interpolations == null) {
            equal = false;
        } else {
            const cmp = object_mod.PyObject_RichCompareBool(t1.interpolations, t2.interpolations, object_mod.Py_EQ);
            if (cmp != 1) equal = false;
        }
    }

    if (op == object_mod.Py_EQ) {
        return if (equal) pybool.Py_True else pybool.Py_False;
    } else {
        return if (equal) pybool.Py_False else pybool.Py_True;
    }
}

/// New for template
fn template_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(templateobject), @sizeOf(templateobject)) catch return null;
    const tmpl: *templateobject = @ptrCast(@alignCast(mem.ptr));

    tmpl.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyTemplate_Type,
        },
        .strings = null,
        .interpolations = null,
    };

    // Parse args if provided
    if (args) |a| {
        const tuple = @import("tupleobject.zig");
        const size = tuple.PyTuple_Size(a);

        // Process args to build strings and interpolations
        // Odd args are strings, even args are interpolations
        var strings_count: usize = 0;
        var interps_count: usize = 0;

        var i: isize = 0;
        while (i < size) : (i += 1) {
            const item = tuple.PyTuple_GetItem(a, i);
            if (item) |it| {
                const pyunicode = @import("unicodeobject.zig");
                if (pyunicode.PyUnicode_Check(it) != 0) {
                    strings_count += 1;
                } else {
                    interps_count += 1;
                }
            }
        }

        // Create tuples for strings and interpolations
        if (strings_count > 0) {
            tmpl.strings = tuple.PyTuple_New(@intCast(strings_count));
        }
        if (interps_count > 0) {
            tmpl.interpolations = tuple.PyTuple_New(@intCast(interps_count));
        }

        // Fill the tuples
        var str_idx: isize = 0;
        var interp_idx: isize = 0;
        i = 0;
        while (i < size) : (i += 1) {
            const item = tuple.PyTuple_GetItem(a, i);
            if (item) |it| {
                const pyunicode = @import("unicodeobject.zig");
                if (pyunicode.PyUnicode_Check(it) != 0) {
                    if (tmpl.strings) |strings| {
                        it.ob_refcnt += 1;
                        tuple.PyTuple_SetItem(strings, str_idx, it);
                        str_idx += 1;
                    }
                } else {
                    if (tmpl.interpolations) |interps| {
                        it.ob_refcnt += 1;
                        tuple.PyTuple_SetItem(interps, interp_idx, it);
                        interp_idx += 1;
                    }
                }
            }
        }
    }

    // Track in GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_Track(@ptrCast(tmpl));

    return @ptrCast(tmpl);
}

/// _PyTemplate_Type - the Template type object
pub export var _PyTemplate_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "string.templatelib.Template",
    .tp_basicsize = @sizeOf(templateobject),
    .tp_itemsize = 0,
    .tp_dealloc = template_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = template_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Unhashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Template object for t-string template literals",
    .tp_traverse = template_traverse,
    .tp_clear = template_clear,
    .tp_richcompare = template_richcompare,
    .tp_weaklistoffset = 0,
    .tp_iter = template_iter,
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
    .tp_new = template_new,
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
// TEMPLATE ITERATOR IMPLEMENTATION
// ============================================================================

/// Dealloc for template iterator
fn templateiter_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const it: *templateiterobject = @ptrCast(@alignCast(self_obj.?));

    // Untrack from GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_UnTrack(@ptrCast(it));

    // Clear references
    _ = templateiter_clear(self_obj);

    // Free the object
    const ptr: [*]u8 = @ptrCast(it);
    allocator.free(ptr[0..@sizeOf(templateiterobject)]);
}

/// Traverse for template iterator (GC)
fn templateiter_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const it: *templateiterobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (it.stringsiter) |strings| {
            const result = v(strings, arg);
            if (result != 0) return result;
        }
        if (it.interpolationsiter) |interps| {
            const result = v(interps, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for template iterator (GC)
fn templateiter_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const it: *templateiterobject = @ptrCast(@alignCast(self_obj.?));

    if (it.stringsiter) |strings| {
        strings.ob_refcnt -= 1;
        it.stringsiter = null;
    }
    if (it.interpolationsiter) |interps| {
        interps.ob_refcnt -= 1;
        it.interpolationsiter = null;
    }
    return 0;
}

/// Next for template iterator
fn templateiter_next(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const it: *templateiterobject = @ptrCast(@alignCast(self_obj));

    if (it.from_strings != 0) {
        // Get next string
        if (it.stringsiter) |strings_it| {
            if (strings_it.ob_type.tp_iternext) |next_fn| {
                const item = next_fn(strings_it);
                it.from_strings = 0; // Next time get interpolation

                if (item) |i| {
                    // Skip empty strings
                    const pyunicode = @import("unicodeobject.zig");
                    if (pyunicode.PyUnicode_GET_LENGTH(i) == 0) {
                        i.ob_refcnt -= 1;
                        // Get interpolation instead
                        if (it.interpolationsiter) |interps_it| {
                            if (interps_it.ob_type.tp_iternext) |interp_next| {
                                it.from_strings = 1; // Next time get string again
                                return interp_next(interps_it);
                            }
                        }
                        return null;
                    }
                    return item;
                }
            }
        }
        return null;
    } else {
        // Get next interpolation
        if (it.interpolationsiter) |interps_it| {
            if (interps_it.ob_type.tp_iternext) |next_fn| {
                it.from_strings = 1; // Next time get string
                return next_fn(interps_it);
            }
        }
        return null;
    }
}

/// _PyTemplateIter_Type - the TemplateIter type object
pub export var _PyTemplateIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "string.templatelib.TemplateIter",
    .tp_basicsize = @sizeOf(templateiterobject),
    .tp_itemsize = 0,
    .tp_dealloc = templateiter_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Template iterator object",
    .tp_traverse = templateiter_traverse,
    .tp_clear = templateiter_clear,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null, // Returns self
    .tp_iternext = templateiter_next,
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

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Check if object is a Template
pub export fn _PyTemplate_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &_PyTemplate_Type) 1 else 0;
}

/// Check if object is exactly a Template (not subclass)
pub export fn _PyTemplate_CheckExact(op: ?*cpython.PyObject) c_int {
    return _PyTemplate_Check(op);
}

/// Check if object is a TemplateIter
pub export fn _PyTemplateIter_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &_PyTemplateIter_Type) 1 else 0;
}

/// Check if object is exactly a TemplateIter (not subclass)
pub export fn _PyTemplateIter_CheckExact(op: ?*cpython.PyObject) c_int {
    return _PyTemplateIter_Check(op);
}

/// Create a new Template object
pub export fn _PyTemplate_New(strings: ?*cpython.PyObject, interpolations: ?*cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(templateobject), @sizeOf(templateobject)) catch return null;
    const tmpl: *templateobject = @ptrCast(@alignCast(mem.ptr));

    tmpl.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyTemplate_Type,
        },
        .strings = strings,
        .interpolations = interpolations,
    };

    if (strings) |s| s.ob_refcnt += 1;
    if (interpolations) |i| i.ob_refcnt += 1;

    // Track in GC
    const obmalloc = @import("obmalloc.zig");
    obmalloc.PyObject_GC_Track(@ptrCast(tmpl));

    return @ptrCast(tmpl);
}

/// Get the strings tuple from a Template
pub export fn _PyTemplate_GetStrings(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyTemplate_Check(op) == 0) return null;

    const tmpl: *templateobject = @ptrCast(@alignCast(op.?));
    if (tmpl.strings) |s| {
        s.ob_refcnt += 1;
        return s;
    }
    return null;
}

/// Get the interpolations tuple from a Template
pub export fn _PyTemplate_GetInterpolations(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    if (_PyTemplate_Check(op) == 0) return null;

    const tmpl: *templateobject = @ptrCast(@alignCast(op.?));
    if (tmpl.interpolations) |i| {
        i.ob_refcnt += 1;
        return i;
    }
    return null;
}
