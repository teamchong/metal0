/// Struct Sequence Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/structseq.c
/// structseq - tuple subclass with named fields (used by os.stat, time.struct_time, etc.)
///
/// Reference: cpython/Objects/structseq.c
///            cpython/Include/structseq.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum number of visible fields
pub const PyStructSequence_MAXFIELDS: usize = 256;

/// Marker for unnamed fields
pub const PyStructSequence_UnnamedField: ?[*:0]const u8 = null;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// PyStructSequence_Field - field descriptor
/// Reference: cpython/Include/structseq.h
///
/// typedef struct {
///     const char *name;
///     const char *doc;
/// } PyStructSequence_Field;
pub const PyStructSequence_Field = extern struct {
    name: ?[*:0]const u8, // 8 bytes - field name (NULL for unnamed)
    doc: ?[*:0]const u8, // 8 bytes - field documentation
};

// Verify PyStructSequence_Field size: 8 + 8 = 16 bytes
comptime {
    if (@sizeOf(PyStructSequence_Field) != 16) {
        @compileError("PyStructSequence_Field size mismatch with CPython");
    }
}

/// PyStructSequence_Desc - type descriptor
/// Reference: cpython/Include/structseq.h
///
/// typedef struct {
///     const char *name;
///     const char *doc;
///     PyStructSequence_Field *fields;
///     int n_in_sequence;
/// } PyStructSequence_Desc;
pub const PyStructSequence_Desc = extern struct {
    name: ?[*:0]const u8, // 8 bytes - type name
    doc: ?[*:0]const u8, // 8 bytes - type documentation
    fields: ?[*]const PyStructSequence_Field, // 8 bytes - field descriptors
    n_in_sequence: c_int, // 4 bytes - number of visible fields in sequence
    _pad: [4]u8, // 4 bytes padding
};

// Verify PyStructSequence_Desc size: 8 + 8 + 8 + 4 + 4 = 32 bytes
comptime {
    if (@sizeOf(PyStructSequence_Desc) != 32) {
        @compileError("PyStructSequence_Desc size mismatch with CPython");
    }
}

/// PyStructSequence - the actual struct sequence object
/// This is basically a tuple with named fields
/// Reference: cpython/Objects/structseq.c
///
/// The object layout is:
/// - PyTupleObject header (includes ob_item array start)
/// - Additional named fields that aren't in the tuple portion
pub const PyStructSequence = extern struct {
    ob_base: cpython.PyVarObject, // 24 bytes
    ob_hash: isize, // 8 bytes - cached hash
    ob_item: [1]*cpython.PyObject, // flexible array - at least 1 item
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Count the number of fields in a descriptor
fn count_fields(desc: *const PyStructSequence_Desc) usize {
    if (desc.fields == null) return 0;

    var count: usize = 0;
    const fields = desc.fields.?;
    while (true) {
        if (fields[count].name == null and fields[count].doc == null) break;
        count += 1;
        if (count > PyStructSequence_MAXFIELDS) break;
    }
    return count;
}

/// Count visible (in-sequence) fields
fn count_visible_fields(desc: *const PyStructSequence_Desc) usize {
    const n = desc.n_in_sequence;
    return if (n >= 0) @intCast(n) else count_fields(desc);
}

// ============================================================================
// STRUCTSEQ TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for struct sequence
fn structseq_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj.?));

    // Decref all items
    const size: usize = @intCast(@max(0, ss.ob_base.ob_size));
    for (0..size) |i| {
        const item_ptr: [*]*cpython.PyObject = &ss.ob_item;
        const item = item_ptr[i];
        item.ob_refcnt -= 1;
    }

    // Free the object
    const total_size = @sizeOf(PyStructSequence) - @sizeOf(*cpython.PyObject) + size * @sizeOf(*cpython.PyObject);
    const ptr: [*]u8 = @ptrCast(ss);
    allocator.free(ptr[0..total_size]);
}

/// Repr for struct sequence
fn structseq_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj.?));

    const type_name = ss.ob_base.ob_base.ob_type.tp_name orelse "structseq";

    // Build repr like: typename(field1=value1, field2=value2, ...)
    // For now, just return the type name
    const pyunicode = @import("unicodeobject.zig");
    _ = type_name;
    return pyunicode.PyUnicode_FromString("structseq(...)");
}

/// Hash for struct sequence
fn structseq_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj.?));

    if (ss.ob_hash != -1) {
        return ss.ob_hash;
    }

    // Hash the visible items (tuple-like hash)
    const n_visible: usize = @intCast(@max(0, ss.ob_base.ob_size));
    var hash: isize = 0x345678;
    const mult: isize = 1000003;

    for (0..n_visible) |i| {
        const item_ptr: [*]*cpython.PyObject = &ss.ob_item;
        const item = item_ptr[i];

        var item_hash: isize = -1;
        if (item.ob_type.tp_hash) |hash_fn| {
            item_hash = hash_fn(item);
        }
        if (item_hash == -1) return -1;

        hash = (hash ^ item_hash) *% mult;
    }

    hash +%= 97531;
    if (hash == -1) hash = -2;

    ss.ob_hash = hash;
    return hash;
}

/// Length for struct sequence (only visible fields)
fn structseq_length(self_obj: *cpython.PyObject) callconv(.C) isize {
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj));
    return ss.ob_base.ob_size;
}

/// Item getter for struct sequence
fn structseq_item(self_obj: *cpython.PyObject, index: isize) callconv(.C) ?*cpython.PyObject {
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj));

    const size = ss.ob_base.ob_size;
    if (index < 0 or index >= size) {
        return null;
    }

    const item_ptr: [*]*cpython.PyObject = &ss.ob_item;
    const item = item_ptr[@intCast(index)];
    item.ob_refcnt += 1;
    return item;
}

/// Sequence methods for struct sequence
var structseq_as_sequence = cpython.PySequenceMethods{
    .sq_length = structseq_length,
    .sq_concat = null,
    .sq_repeat = null,
    .sq_item = structseq_item,
    .was_sq_slice = null,
    .sq_ass_item = null, // Immutable
    .was_sq_ass_slice = null,
    .sq_contains = null,
    .sq_inplace_concat = null,
    .sq_inplace_repeat = null,
};

/// Rich comparison for struct sequence
fn structseq_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const ss: *PyStructSequence = @ptrCast(@alignCast(self_obj));
    const pybool = @import("boolobject.zig");

    // Compare types
    if (self_obj.ob_type != other.ob_type) {
        if (op == 2) return pybool.Py_False; // EQ
        if (op == 3) return pybool.Py_True; // NE
        return null;
    }

    const other_ss: *PyStructSequence = @ptrCast(@alignCast(other));

    // Compare visible elements
    const len = ss.ob_base.ob_size;
    const other_len = other_ss.ob_base.ob_size;

    if (len != other_len) {
        if (op == 2) return pybool.Py_False;
        if (op == 3) return pybool.Py_True;
    }

    const self_items: [*]*cpython.PyObject = &ss.ob_item;
    const other_items: [*]*cpython.PyObject = &other_ss.ob_item;

    const object_mod = @import("object.zig");

    for (0..@intCast(len)) |i| {
        const self_item = self_items[i];
        const other_item = other_items[i];

        if (self_item != other_item) {
            // Deep comparison using PyObject_RichCompareBool
            const cmp = object_mod.PyObject_RichCompareBool(self_item, other_item, object_mod.Py_EQ);
            if (cmp == 0) {
                // Items not equal
                if (op == 2) return pybool.Py_False; // Py_EQ
                if (op == 3) return pybool.Py_True;  // Py_NE
            } else if (cmp < 0) {
                // Comparison error
                return null;
            }
            // cmp == 1 means equal, continue to next item
        }
    }

    // All items equal
    if (op == 2) return pybool.Py_True;
    if (op == 3) return pybool.Py_False;

    return null;
}

/// New for struct sequence (base implementation)
fn structseq_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    // Struct sequences should be created via PyStructSequence_New
    return null;
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Create a new struct sequence type
pub export fn PyStructSequence_NewType(desc: ?*const PyStructSequence_Desc) ?*cpython.PyTypeObject {
    if (desc == null) return null;

    const d = desc.?;
    const n_fields = count_fields(d);
    const n_visible = count_visible_fields(d);

    // Allocate type object
    const mem = allocator.alignedAlloc(u8, @alignOf(cpython.PyTypeObject), @sizeOf(cpython.PyTypeObject)) catch return null;
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(mem.ptr));

    type_obj.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
            .ob_size = 0,
        },
        .tp_name = d.name,
        .tp_basicsize = @sizeOf(PyStructSequence) - @sizeOf(*cpython.PyObject) + @as(isize, @intCast(n_fields)) * @sizeOf(*cpython.PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = structseq_dealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = structseq_repr,
        .tp_as_number = null,
        .tp_as_sequence = &structseq_as_sequence,
        .tp_as_mapping = null,
        .tp_hash = structseq_hash,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
        .tp_doc = d.doc,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = structseq_richcompare,
        .tp_weaklistoffset = 0,
        .tp_iter = null,
        .tp_iternext = null,
        .tp_methods = null,
        .tp_members = null,
        .tp_getset = null, // TODO: Create getset for named fields
        .tp_base = null, // TODO: Set to PyTuple_Type
        .tp_dict = null,
        .tp_descr_get = null,
        .tp_descr_set = null,
        .tp_dictoffset = 0,
        .tp_init = null,
        .tp_alloc = null,
        .tp_new = structseq_new,
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

    // Store visible count in ob_size for later use
    type_obj.ob_base.ob_size = @intCast(n_visible);

    return type_obj;
}

/// Initialize a struct sequence type in-place
pub export fn PyStructSequence_InitType2(type_obj: ?*cpython.PyTypeObject, desc: ?*const PyStructSequence_Desc) c_int {
    if (type_obj == null or desc == null) return -1;

    const d = desc.?;
    const n_fields = count_fields(d);
    const n_visible = count_visible_fields(d);

    type_obj.?.tp_name = d.name;
    type_obj.?.tp_doc = d.doc;
    type_obj.?.tp_basicsize = @sizeOf(PyStructSequence) - @sizeOf(*cpython.PyObject) + @as(isize, @intCast(n_fields)) * @sizeOf(*cpython.PyObject);
    type_obj.?.tp_dealloc = structseq_dealloc;
    type_obj.?.tp_repr = structseq_repr;
    type_obj.?.tp_hash = structseq_hash;
    type_obj.?.tp_as_sequence = &structseq_as_sequence;
    type_obj.?.tp_richcompare = structseq_richcompare;
    type_obj.?.tp_new = structseq_new;
    type_obj.?.tp_flags = cpython.Py_TPFLAGS_DEFAULT;
    type_obj.?.ob_base.ob_size = @intCast(n_visible);

    return 0;
}

/// Legacy init (void return)
pub export fn PyStructSequence_InitType(type_obj: ?*cpython.PyTypeObject, desc: ?*const PyStructSequence_Desc) void {
    _ = PyStructSequence_InitType2(type_obj, desc);
}

/// Create a new struct sequence instance
pub export fn PyStructSequence_New(type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (type_obj == null) return null;

    const basicsize: usize = @intCast(type_obj.?.tp_basicsize);

    const mem = allocator.alignedAlloc(u8, @alignOf(PyStructSequence), basicsize) catch return null;
    const ss: *PyStructSequence = @ptrCast(@alignCast(mem.ptr));

    // Initialize header
    ss.* = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = type_obj.?,
            },
            .ob_size = type_obj.?.ob_base.ob_size, // visible field count
        },
        .ob_hash = -1,
        .ob_item = undefined,
    };

    // Initialize all items to NULL
    const n_fields = (basicsize - @sizeOf(PyStructSequence) + @sizeOf(*cpython.PyObject)) / @sizeOf(*cpython.PyObject);
    const items: [*]*cpython.PyObject = &ss.ob_item;
    for (0..n_fields) |i| {
        items[i] = undefined;
    }

    return @ptrCast(ss);
}

/// Get item from struct sequence (by index, includes hidden fields)
pub export fn PyStructSequence_GetItem(op: ?*cpython.PyObject, index: isize) ?*cpython.PyObject {
    if (op == null) return null;
    const ss: *PyStructSequence = @ptrCast(@alignCast(op.?));

    if (index < 0) return null;

    const items: [*]*cpython.PyObject = &ss.ob_item;
    return items[@intCast(index)];
}

/// Set item in struct sequence (by index)
pub export fn PyStructSequence_SetItem(op: ?*cpython.PyObject, index: isize, value: ?*cpython.PyObject) void {
    if (op == null or value == null) return;
    const ss: *PyStructSequence = @ptrCast(@alignCast(op.?));

    if (index < 0) return;

    const items: [*]*cpython.PyObject = &ss.ob_item;
    items[@intCast(index)] = value.?;
}

/// GET_ITEM macro - no error checking
pub export fn PyStructSequence_GET_ITEM(op: ?*cpython.PyObject, index: isize) ?*cpython.PyObject {
    return PyStructSequence_GetItem(op, index);
}

/// SET_ITEM macro - no error checking, steals reference
pub export fn PyStructSequence_SET_ITEM(op: ?*cpython.PyObject, index: isize, value: ?*cpython.PyObject) void {
    PyStructSequence_SetItem(op, index, value);
}

// ============================================================================
// COMMON STRUCT SEQUENCE TYPES
// ============================================================================

// These would be initialized at module load time with proper descriptors

/// Create os.stat_result type descriptor
pub fn make_stat_result_desc() PyStructSequence_Desc {
    const stat_fields = [_]PyStructSequence_Field{
        .{ .name = "st_mode", .doc = "protection bits" },
        .{ .name = "st_ino", .doc = "inode" },
        .{ .name = "st_dev", .doc = "device" },
        .{ .name = "st_nlink", .doc = "number of hard links" },
        .{ .name = "st_uid", .doc = "user ID of owner" },
        .{ .name = "st_gid", .doc = "group ID of owner" },
        .{ .name = "st_size", .doc = "total size, in bytes" },
        .{ .name = "st_atime", .doc = "time of last access" },
        .{ .name = "st_mtime", .doc = "time of last modification" },
        .{ .name = "st_ctime", .doc = "time of last change" },
        .{ .name = null, .doc = null }, // sentinel
    };
    _ = stat_fields;

    return .{
        .name = "os.stat_result",
        .doc = "Result of os.stat(), os.fstat() and os.lstat().",
        .fields = null, // Would point to stat_fields
        .n_in_sequence = 10,
        ._pad = [_]u8{0} ** 4,
    };
}

/// Create time.struct_time type descriptor
pub fn make_struct_time_desc() PyStructSequence_Desc {
    const time_fields = [_]PyStructSequence_Field{
        .{ .name = "tm_year", .doc = "year, for example, 1993" },
        .{ .name = "tm_mon", .doc = "month of year, range [1, 12]" },
        .{ .name = "tm_mday", .doc = "day of month, range [1, 31]" },
        .{ .name = "tm_hour", .doc = "hours, range [0, 23]" },
        .{ .name = "tm_min", .doc = "minutes, range [0, 59]" },
        .{ .name = "tm_sec", .doc = "seconds, range [0, 61]" },
        .{ .name = "tm_wday", .doc = "day of week, range [0, 6], Monday is 0" },
        .{ .name = "tm_yday", .doc = "day of year, range [1, 366]" },
        .{ .name = "tm_isdst", .doc = "1 if summer time is in effect, 0 if not, and -1 if unknown" },
        .{ .name = null, .doc = null }, // sentinel
    };
    _ = time_fields;

    return .{
        .name = "time.struct_time",
        .doc = "The time value as returned by gmtime(), localtime(), and strptime().",
        .fields = null, // Would point to time_fields
        .n_in_sequence = 9,
        ._pad = [_]u8{0} ** 4,
    };
}

// ============================================================================
// UNNAMED FIELD SUPPORT
// ============================================================================

/// Check if a field is unnamed
pub fn is_unnamed_field(field: *const PyStructSequence_Field) bool {
    return field.name == PyStructSequence_UnnamedField;
}

/// Get the total number of real (named) fields
pub fn count_named_fields(desc: *const PyStructSequence_Desc) usize {
    if (desc.fields == null) return 0;

    var count: usize = 0;
    const fields = desc.fields.?;
    var i: usize = 0;
    while (true) {
        if (fields[i].name == null and fields[i].doc == null) break;
        if (!is_unnamed_field(&fields[i])) {
            count += 1;
        }
        i += 1;
        if (i > PyStructSequence_MAXFIELDS) break;
    }
    return count;
}
