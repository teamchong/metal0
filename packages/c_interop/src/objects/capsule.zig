/// PyCapsule Implementation - Exact CPython Memory Layout
///
/// Wrap void * pointers to be passed between C modules
///
/// Reference: cpython/Objects/capsule.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// Destructor function type - called when capsule is deallocated
pub const PyCapsule_Destructor = ?*const fn (?*cpython.PyObject) callconv(.C) void;

/// PyCapsule - Internal structure (EXACT CPython layout)
/// Reference: cpython/Objects/capsule.c
///
/// typedef struct {
///     PyObject_HEAD
///     void *pointer;
///     const char *name;
///     void *context;
///     PyCapsule_Destructor destructor;
///     traverseproc traverse_func;
///     inquiry clear_func;
/// } PyCapsule;
pub const PyCapsule = extern struct {
    ob_base: cpython.PyObject, // PyObject_HEAD (16 bytes on 64-bit)
    pointer: ?*anyopaque, // void *pointer
    name: ?[*:0]const u8, // const char *name
    context: ?*anyopaque, // void *context
    destructor: PyCapsule_Destructor, // PyCapsule_Destructor destructor
    traverse_func: cpython.traverseproc, // traverseproc traverse_func
    clear_func: cpython.inquiry, // inquiry clear_func
};

// Verify layout matches CPython
comptime {
    // PyCapsule should be: PyObject(16) + pointer(8) + name(8) + context(8) + destructor(8) + traverse(8) + clear(8) = 64 bytes
    if (@sizeOf(PyCapsule) != 64) {
        @compileError("PyCapsule size mismatch with CPython");
    }
}

// ============================================================================
// TYPE OBJECT
// ============================================================================

/// PyCapsule_Type - the type object for capsules
pub export var PyCapsule_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, // Will be set to &PyType_Type
        .ob_size = 0,
    },
    .tp_name = "PyCapsule",
    .tp_basicsize = @sizeOf(PyCapsule),
    .tp_itemsize = 0,
    .tp_dealloc = capsule_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = capsule_repr,
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
    .tp_doc = "Capsule objects let you wrap a C \"void *\" pointer in a Python\nobject.  They're a way of passing data through the Python interpreter\nwithout creating your own custom type.\n\nCapsules are used for communication between extension modules.\nThey provide a way for an extension module to export a C interface\nto other extension modules, so that extension modules can use the\nPython import mechanism to link to one another.\n",
    .tp_traverse = capsule_traverse,
    .tp_clear = capsule_clear,
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
};

// ============================================================================
// INTERNAL HELPERS
// ============================================================================

/// Check if capsule is valid
fn is_legal_capsule(op: ?*cpython.PyObject, invalid_msg: [*:0]const u8) bool {
    if (op == null) {
        // PyErr_SetString(PyExc_ValueError, invalid_msg);
        _ = invalid_msg;
        return false;
    }

    // Check if it's a PyCapsule
    if (op.?.ob_type != &PyCapsule_Type) {
        return false;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    if (capsule.pointer == null) {
        return false;
    }

    return true;
}

/// Check if names match (NULL matches NULL)
fn name_matches(name1: ?[*:0]const u8, name2: ?[*:0]const u8) bool {
    if (name1 == null or name2 == null) {
        return name1 == name2;
    }
    return std.mem.orderZ(u8, name1.?, name2.?) == .eq;
}

/// Dealloc function
fn capsule_dealloc(op: ?*cpython.PyObject) callconv(.C) void {
    if (op == null) return;
    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));

    // Call destructor if set
    if (capsule.destructor) |dtor| {
        dtor(op);
    }

    // Free the capsule
    const ptr: [*]u8 = @ptrCast(capsule);
    allocator.free(ptr[0..@sizeOf(PyCapsule)]);
}

/// Repr function
fn capsule_repr(op: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (op == null) return null;
    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    const pyunicode = @import("unicodeobject.zig");

    // Format: <capsule object "name" at 0xADDRESS> or <capsule object NULL at 0xADDRESS>
    var buf: [256]u8 = undefined;
    var pos: usize = 0;

    const prefix = "<capsule object ";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    // Add name
    if (capsule.name) |name| {
        buf[pos] = '"';
        pos += 1;
        const name_slice = std.mem.span(name);
        const name_len = @min(name_slice.len, buf.len - pos - 50);
        @memcpy(buf[pos..][0..name_len], name_slice[0..name_len]);
        pos += name_len;
        buf[pos] = '"';
        pos += 1;
    } else {
        const null_str = "NULL";
        @memcpy(buf[pos..][0..null_str.len], null_str);
        pos += null_str.len;
    }

    // Add address
    const at_str = " at 0x";
    @memcpy(buf[pos..][0..at_str.len], at_str);
    pos += at_str.len;

    // Format address as hex
    const addr = @intFromPtr(op.?);
    const hex_chars = "0123456789abcdef";
    var hex_buf: [16]u8 = undefined;
    var hex_len: usize = 0;
    var temp_addr = addr;
    while (temp_addr > 0 or hex_len == 0) : (temp_addr /= 16) {
        hex_buf[15 - hex_len] = hex_chars[temp_addr % 16];
        hex_len += 1;
    }
    @memcpy(buf[pos..][0..hex_len], hex_buf[16 - hex_len ..]);
    pos += hex_len;

    buf[pos] = '>';
    pos += 1;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

/// Traverse function for GC
fn capsule_traverse(self: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self == null) return 0;
    const capsule: *PyCapsule = @ptrCast(@alignCast(self.?));

    if (capsule.traverse_func) |traverse| {
        return traverse(self, visit, arg);
    }
    return 0;
}

/// Clear function for GC
fn capsule_clear(self: ?*cpython.PyObject) callconv(.C) c_int {
    if (self == null) return 0;
    const capsule: *PyCapsule = @ptrCast(@alignCast(self.?));

    if (capsule.clear_func) |clear| {
        return clear(self);
    }
    return 0;
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// PyCapsule_New - Create a new capsule containing the pointer
pub export fn PyCapsule_New(
    pointer: ?*anyopaque,
    name: ?[*:0]const u8,
    destructor: PyCapsule_Destructor,
) ?*cpython.PyObject {
    if (pointer == null) {
        // PyErr_SetString(PyExc_ValueError, "PyCapsule_New called with null pointer");
        return null;
    }

    // Allocate capsule
    const mem = allocator.alignedAlloc(u8, @alignOf(PyCapsule), @sizeOf(PyCapsule)) catch return null;
    const capsule: *PyCapsule = @ptrCast(@alignCast(mem.ptr));

    capsule.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyCapsule_Type,
        },
        .pointer = pointer,
        .name = name,
        .context = null,
        .destructor = destructor,
        .traverse_func = null,
        .clear_func = null,
    };

    return @ptrCast(capsule);
}

/// PyCapsule_IsValid - Check if capsule is valid with given name
pub export fn PyCapsule_IsValid(op: ?*cpython.PyObject, name: ?[*:0]const u8) c_int {
    if (op == null) return 0;
    if (op.?.ob_type != &PyCapsule_Type) return 0;

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    if (capsule.pointer == null) return 0;
    if (!name_matches(capsule.name, name)) return 0;

    return 1;
}

/// PyCapsule_GetPointer - Get the pointer from the capsule
pub export fn PyCapsule_GetPointer(op: ?*cpython.PyObject, name: ?[*:0]const u8) ?*anyopaque {
    if (!is_legal_capsule(op, "PyCapsule_GetPointer called with invalid PyCapsule object")) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    if (!name_matches(name, capsule.name)) {
        // PyErr_SetString(PyExc_ValueError, "PyCapsule_GetPointer called with incorrect name");
        return null;
    }

    return capsule.pointer;
}

/// PyCapsule_GetName - Get the name from the capsule
pub export fn PyCapsule_GetName(op: ?*cpython.PyObject) ?[*:0]const u8 {
    if (!is_legal_capsule(op, "PyCapsule_GetName called with invalid PyCapsule object")) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    return capsule.name;
}

/// PyCapsule_GetDestructor - Get the destructor from the capsule
pub export fn PyCapsule_GetDestructor(op: ?*cpython.PyObject) PyCapsule_Destructor {
    if (!is_legal_capsule(op, "PyCapsule_GetDestructor called with invalid PyCapsule object")) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    return capsule.destructor;
}

/// PyCapsule_GetContext - Get the context from the capsule
pub export fn PyCapsule_GetContext(op: ?*cpython.PyObject) ?*anyopaque {
    if (!is_legal_capsule(op, "PyCapsule_GetContext called with invalid PyCapsule object")) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    return capsule.context;
}

/// PyCapsule_SetPointer - Set the pointer in the capsule
pub export fn PyCapsule_SetPointer(op: ?*cpython.PyObject, pointer: ?*anyopaque) c_int {
    if (!is_legal_capsule(op, "PyCapsule_SetPointer called with invalid PyCapsule object")) {
        return -1;
    }

    if (pointer == null) {
        // PyErr_SetString(PyExc_ValueError, "PyCapsule_SetPointer called with null pointer");
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    capsule.pointer = pointer;
    return 0;
}

/// PyCapsule_SetName - Set the name in the capsule
pub export fn PyCapsule_SetName(op: ?*cpython.PyObject, name: ?[*:0]const u8) c_int {
    if (!is_legal_capsule(op, "PyCapsule_SetName called with invalid PyCapsule object")) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    capsule.name = name;
    return 0;
}

/// PyCapsule_SetDestructor - Set the destructor in the capsule
pub export fn PyCapsule_SetDestructor(op: ?*cpython.PyObject, destructor: PyCapsule_Destructor) c_int {
    if (!is_legal_capsule(op, "PyCapsule_SetDestructor called with invalid PyCapsule object")) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    capsule.destructor = destructor;
    return 0;
}

/// PyCapsule_SetContext - Set the context in the capsule
pub export fn PyCapsule_SetContext(op: ?*cpython.PyObject, context: ?*anyopaque) c_int {
    if (!is_legal_capsule(op, "PyCapsule_SetContext called with invalid PyCapsule object")) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    capsule.context = context;
    return 0;
}

/// _PyCapsule_SetTraverse - Set traverse and clear functions for GC
pub export fn _PyCapsule_SetTraverse(
    op: ?*cpython.PyObject,
    traverse_func: cpython.traverseproc,
    clear_func: cpython.inquiry,
) c_int {
    if (!is_legal_capsule(op, "_PyCapsule_SetTraverse called with invalid PyCapsule object")) {
        return -1;
    }

    if (traverse_func == null or clear_func == null) {
        // PyErr_SetString(PyExc_ValueError, "_PyCapsule_SetTraverse() called with NULL callback");
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op.?));
    capsule.traverse_func = traverse_func;
    capsule.clear_func = clear_func;

    // Track object with GC if not already tracked
    const obmalloc = @import("obmalloc.zig");
    if (obmalloc.PyObject_GC_IsTracked(op) == 0) {
        obmalloc.PyObject_GC_Track(op);
    }
    return 0;
}

/// PyCapsule_Import - Import a capsule from a module by attribute name
/// The name should be "module.submodule.attribute"
pub export fn PyCapsule_Import(name: ?[*:0]const u8, no_block: c_int) ?*anyopaque {
    _ = no_block;

    if (name == null) return null;

    const name_str = std.mem.span(name.?);
    if (name_str.len == 0) return null;

    // Parse module.attr.capsule path
    // Find first dot to get module name
    var module_end: usize = 0;
    while (module_end < name_str.len and name_str[module_end] != '.') : (module_end += 1) {}

    if (module_end == name_str.len) {
        // No dot found - invalid name
        return null;
    }

    // Import module and traverse attributes to find capsule
    const pyimport = @import("../include/import.zig");
    const pyunicode = @import("unicodeobject.zig");
    const object_mod = @import("object.zig");

    // Get module name (up to first dot)
    var module_name_buf: [256]u8 = undefined;
    const module_len = @min(module_end, module_name_buf.len - 1);
    @memcpy(module_name_buf[0..module_len], name_str[0..module_len]);
    module_name_buf[module_len] = 0;

    // Import the module
    const module = pyimport.PyImport_ImportModule(&module_name_buf);
    if (module == null) return null;
    defer module.?.ob_refcnt -= 1;

    // Traverse remaining attributes
    var obj: ?*cpython.PyObject = module;
    var attr_start: usize = module_end + 1;

    while (attr_start < name_str.len) {
        // Find next dot or end
        var attr_end = attr_start;
        while (attr_end < name_str.len and name_str[attr_end] != '.') : (attr_end += 1) {}

        // Get attribute name
        var attr_name_buf: [256]u8 = undefined;
        const attr_len = @min(attr_end - attr_start, attr_name_buf.len - 1);
        @memcpy(attr_name_buf[0..attr_len], name_str[attr_start..][0..attr_len]);
        attr_name_buf[attr_len] = 0;

        // Get attribute
        const attr_name_obj = pyunicode.PyUnicode_FromString(&attr_name_buf);
        if (attr_name_obj == null) return null;
        defer attr_name_obj.?.ob_refcnt -= 1;

        const next_obj = object_mod.PyObject_GetAttr(obj.?, attr_name_obj.?);
        if (next_obj == null) return null;

        // Release previous intermediate object (but not the original module)
        if (obj != module) {
            obj.?.ob_refcnt -= 1;
        }
        obj = next_obj;

        attr_start = attr_end + 1;
    }

    // obj should now be the capsule
    if (obj == null or obj.?.ob_type != &PyCapsule_Type) {
        if (obj != null and obj != module) {
            obj.?.ob_refcnt -= 1;
        }
        return null;
    }

    // Return the pointer from the capsule
    const capsule: *PyCapsule = @ptrCast(@alignCast(obj.?));
    const result = capsule.pointer;

    // Release the capsule (we got the pointer)
    if (obj != module) {
        obj.?.ob_refcnt -= 1;
    }

    return result;
}

/// PyCapsule_CheckExact - Check if object is exactly a PyCapsule
pub inline fn PyCapsule_CheckExact(op: ?*cpython.PyObject) bool {
    if (op == null) return false;
    return op.?.ob_type == &PyCapsule_Type;
}
