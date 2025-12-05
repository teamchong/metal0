/// CPython Struct Sequence API
///
/// Implements named tuple-like structures used by CPython for things like:
/// - os.stat_result
/// - time.struct_time
/// - sys.flags
///
/// Reference: cpython/Include/structseq.h

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

/// Field descriptor for struct sequence
pub const PyStructSequence_Field = extern struct {
    name: ?[*:0]const u8,
    doc: ?[*:0]const u8,
};

/// Descriptor for defining a struct sequence type
pub const PyStructSequence_Desc = extern struct {
    name: [*:0]const u8,
    doc: ?[*:0]const u8,
    fields: [*]PyStructSequence_Field,
    n_in_sequence: isize, // Number of fields visible in sequence interface
};

/// Struct sequence object - extends PyTupleObject
pub const PyStructSequence = extern struct {
    ob_base: cpython.PyVarObject,
    ob_item: [*]?*cpython.PyObject,
};

/// Create a new struct sequence type from descriptor
/// Returns new type object or null on error
export fn PyStructSequence_NewType(desc: *PyStructSequence_Desc) callconv(.c) ?*cpython.PyTypeObject {
    // Allocate type object
    const type_obj = allocator.create(cpython.PyTypeObject) catch return null;

    // Count fields
    var n_fields: usize = 0;
    while (desc.fields[n_fields].name != null) : (n_fields += 1) {}

    // Initialize type object
    type_obj.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &cpython.PyType_Type },
            .ob_size = 0,
        },
        .tp_name = desc.name,
        .tp_basicsize = @sizeOf(PyStructSequence),
        .tp_itemsize = @sizeOf(?*cpython.PyObject),
        .tp_dealloc = structseq_dealloc,
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
        .tp_doc = desc.doc,
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

    return type_obj;
}

/// Initialize a struct sequence type (for existing type objects)
/// Returns 0 on success, -1 on error
export fn PyStructSequence_InitType(type_obj: *cpython.PyTypeObject, desc: *PyStructSequence_Desc) callconv(.c) c_int {
    return PyStructSequence_InitType2(type_obj, desc);
}

/// Initialize a struct sequence type (version 2)
/// Returns 0 on success, -1 on error
export fn PyStructSequence_InitType2(type_obj: *cpython.PyTypeObject, desc: *PyStructSequence_Desc) callconv(.c) c_int {
    type_obj.tp_name = desc.name;
    type_obj.tp_doc = desc.doc;
    type_obj.tp_basicsize = @sizeOf(PyStructSequence);
    type_obj.tp_itemsize = @sizeOf(?*cpython.PyObject);
    type_obj.tp_dealloc = structseq_dealloc;
    type_obj.tp_flags = cpython.Py_TPFLAGS_DEFAULT;
    return 0;
}

/// Create a new struct sequence instance
/// Returns new instance or null on error
export fn PyStructSequence_New(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    // Calculate size needed based on type's itemsize
    const n_items: usize = @intCast(type_obj.tp_basicsize / @sizeOf(?*cpython.PyObject));

    const total_size = @sizeOf(PyStructSequence) + n_items * @sizeOf(?*cpython.PyObject);
    const memory = allocator.alloc(u8, total_size) catch return null;

    const seq: *PyStructSequence = @ptrCast(@alignCast(memory.ptr));
    seq.ob_base.ob_base.ob_refcnt = 1;
    seq.ob_base.ob_base.ob_type = type_obj;
    seq.ob_base.ob_size = @intCast(n_items);

    // Initialize items to null
    const items: [*]?*cpython.PyObject = @ptrCast(@alignCast(memory.ptr + @sizeOf(PyStructSequence)));
    for (0..n_items) |i| {
        items[i] = null;
    }
    seq.ob_item = items;

    return @ptrCast(&seq.ob_base.ob_base);
}

/// Get item from struct sequence
/// Returns borrowed reference
export fn PyStructSequence_GetItem(seq: *cpython.PyObject, pos: isize) callconv(.c) ?*cpython.PyObject {
    const ss: *PyStructSequence = @ptrCast(@alignCast(seq));
    if (pos < 0 or pos >= ss.ob_base.ob_size) return null;
    return ss.ob_item[@intCast(pos)];
}

/// Set item in struct sequence (steals reference)
export fn PyStructSequence_SetItem(seq: *cpython.PyObject, pos: isize, obj: ?*cpython.PyObject) callconv(.c) void {
    const ss: *PyStructSequence = @ptrCast(@alignCast(seq));
    if (pos < 0 or pos >= ss.ob_base.ob_size) return;

    const idx: usize = @intCast(pos);
    if (ss.ob_item[idx]) |old| {
        traits.decref(old);
    }
    ss.ob_item[idx] = obj;
}

/// Get item from struct sequence (macro version - same as GetItem)
export fn PyStructSequence_GET_ITEM(seq: *cpython.PyObject, pos: isize) callconv(.c) ?*cpython.PyObject {
    return PyStructSequence_GetItem(seq, pos);
}

/// Set item in struct sequence (macro version - same as SetItem)
export fn PyStructSequence_SET_ITEM(seq: *cpython.PyObject, pos: isize, obj: ?*cpython.PyObject) callconv(.c) void {
    PyStructSequence_SetItem(seq, pos, obj);
}

/// Unnamed field marker
pub const PyStructSequence_UnnamedField: [*:0]const u8 = "";

// Internal dealloc function
fn structseq_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const ss: *PyStructSequence = @ptrCast(@alignCast(obj));
    const n_items: usize = @intCast(ss.ob_base.ob_size);

    // Decref all items
    for (0..n_items) |i| {
        if (ss.ob_item[i]) |item| {
            traits.decref(item);
        }
    }

    // Free the struct sequence
    const total_size = @sizeOf(PyStructSequence) + n_items * @sizeOf(?*cpython.PyObject);
    const memory: [*]u8 = @ptrCast(@alignCast(ss));
    allocator.free(memory[0..total_size]);
}

// Tests
test "struct sequence exports" {
    _ = PyStructSequence_NewType;
    _ = PyStructSequence_New;
    _ = PyStructSequence_GetItem;
    _ = PyStructSequence_SetItem;
}
