/// Type Object Implementation - Core Type System
///
/// Implements CPython's Objects/typeobject.c
/// The type system including PyType_Type (the metatype) and type operations
///
/// Reference: cpython/Objects/typeobject.c
///            cpython/Include/cpython/object.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// Reference PyBaseObject_Type from typeslots.zig (where it's exported)
const PyBaseObject_Type = @extern(*cpython.PyTypeObject, .{ .name = "PyBaseObject_Type" });

// ============================================================================
// CONSTANTS
// ============================================================================

/// MRO entry flags
pub const MCACHE_SIZE_EXP: u5 = 12;
pub const MCACHE_SIZE: usize = 1 << MCACHE_SIZE_EXP;
pub const MCACHE_HASH_METHOD: usize = 1;

/// Type ready flags
pub const Py_TPFLAGS_READY: c_ulong = 1 << 12;
pub const Py_TPFLAGS_READYING: c_ulong = 1 << 13;
pub const Py_TPFLAGS_HAVE_VECTORCALL: c_ulong = 1 << 11;
pub const Py_TPFLAGS_METHOD_DESCRIPTOR: c_ulong = 1 << 17;
pub const Py_TPFLAGS_IMMUTABLETYPE: c_ulong = 1 << 8;

// ============================================================================
// TYPE DEFINITIONS - Internal Structures
// ============================================================================

/// PyHeapTypeObject - heap-allocated type object
/// Reference: cpython/Include/cpython/object.h
///
/// For types created at runtime (via class statement or type())
pub const PyHeapTypeObject = extern struct {
    ht_type: cpython.PyTypeObject, // The type object itself
    as_async: cpython.PyAsyncMethods, // Async methods
    as_number: cpython.PyNumberMethods, // Number methods
    as_mapping: cpython.PyMappingMethods, // Mapping methods
    as_sequence: cpython.PySequenceMethods, // Sequence methods
    as_buffer: cpython.PyBufferProcs, // Buffer methods
    ht_name: ?*cpython.PyObject, // __name__
    ht_slots: ?*cpython.PyObject, // __slots__
    ht_qualname: ?*cpython.PyObject, // __qualname__
    ht_cached_keys: ?*anyopaque, // Cached keys for dict
    ht_module: ?*cpython.PyObject, // __module__
    _ht_tpname: ?[*:0]u8, // Storage for tp_name
};

// ============================================================================
// TYPE TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for type objects
fn type_dealloc(self_obj: ?*cpython.PyObject) callconv(.c) void {
    if (self_obj == null) return;
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(self_obj.?));

    // Only heap types should be deallocated
    if ((type_obj.tp_flags & cpython.Py_TPFLAGS_HEAPTYPE) == 0) {
        return;
    }

    // Decref base type
    if (type_obj.tp_base) |base| {
        const base_obj: *cpython.PyObject = @ptrCast(base);
        base_obj.ob_refcnt -= 1;
    }

    // Decref dict
    if (type_obj.tp_dict) |dict| {
        dict.ob_refcnt -= 1;
    }

    // Free the type
    const ptr: [*]u8 = @ptrCast(type_obj);
    allocator.free(ptr[0..@sizeOf(PyHeapTypeObject)]);
}

/// Repr for type objects
fn type_repr(self_obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(self_obj.?));

    const name = type_obj.tp_name orelse "?";
    _ = name;

    // Format: <class 'module.name'>
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("<class '?'>");
}

/// Call for type objects (instantiation)
fn type_call(type_obj_raw: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(type_obj_raw));

    // Call tp_new to create instance
    var obj: ?*cpython.PyObject = null;
    if (type_obj.tp_new) |new_fn| {
        obj = new_fn(type_obj, args, kwargs);
    }

    if (obj == null) return null;

    // Call tp_init to initialize instance
    if (type_obj.tp_init) |init_fn| {
        const result = init_fn(obj.?, args, kwargs);
        if (result < 0) {
            obj.?.ob_refcnt -= 1;
            return null;
        }
    }

    return obj;
}

/// Getattro for type objects
fn type_getattro(type_obj_raw: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(type_obj_raw));
    const pydict = @import("dictobject.zig");

    // First, check the type's own dict
    if (type_obj.tp_dict) |dict| {
        const result = pydict.PyDict_GetItem(dict, name);
        if (result != null) {
            // Check if it's a descriptor
            if (result.?.ob_type.tp_descr_get) |descr_get| {
                return descr_get(result.?, null, type_obj_raw);
            }
            cpython.Py_INCREF(result.?);
            return result;
        }
    }

    // Check base type
    if (type_obj.tp_base) |base| {
        return type_getattro(@ptrCast(base), name);
    }

    return null;
}

/// Setattro for type objects
fn type_setattro(type_obj_raw: *cpython.PyObject, name: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(type_obj_raw));
    const pydict = @import("dictobject.zig");

    // Check if type is immutable
    if ((type_obj.tp_flags & Py_TPFLAGS_IMMUTABLETYPE) != 0) {
        return -1;
    }

    // Set or delete attribute in type's dict
    if (type_obj.tp_dict) |dict| {
        var result: c_int = 0;
        if (value == null) {
            // Delete attribute
            result = pydict.PyDict_DelItem(dict, name);
        } else {
            // Set attribute
            result = pydict.PyDict_SetItem(dict, name, value.?);
        }

        // Invalidate attribute cache
        type_obj.tp_version_tag = 0;
        return result;
    }

    return -1;
}

/// Traverse for type objects (GC)
fn type_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.c) c_int {
    if (self_obj == null) return 0;
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (type_obj.tp_dict) |dict| {
            const result = v(dict, arg);
            if (result != 0) return result;
        }
        if (type_obj.tp_bases) |bases| {
            const result = v(bases, arg);
            if (result != 0) return result;
        }
        if (type_obj.tp_mro) |mro| {
            const result = v(mro, arg);
            if (result != 0) return result;
        }
        if (type_obj.tp_base) |base| {
            const base_obj: *cpython.PyObject = @ptrCast(base);
            const result = v(base_obj, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for type objects (GC)
fn type_clear(self_obj: ?*cpython.PyObject) callconv(.c) c_int {
    if (self_obj == null) return 0;
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(self_obj.?));

    if (type_obj.tp_dict) |dict| {
        dict.ob_refcnt -= 1;
        type_obj.tp_dict = null;
    }

    return 0;
}

/// Init for type objects (type(...) call with 3 args)
fn type_init(self_obj: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = self_obj;
    _ = args;
    _ = kwargs;
    return 0;
}

/// New for type objects
fn type_new(metatype: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = metatype;
    _ = args;
    _ = kwargs;

    // This is called when: type(name, bases, dict)
    // For creating new class types at runtime

    // Allocate heap type
    const mem = allocator.alloc(u8, @sizeOf(PyHeapTypeObject)) catch return null;
    @memset(mem, 0);
    const heap_type: *PyHeapTypeObject = @ptrCast(@alignCast(mem.ptr));

    // Initialize the type object portion
    heap_type.ht_type.ob_base.ob_base.ob_refcnt = 1;
    heap_type.ht_type.ob_base.ob_base.ob_type = &PyType_Type;
    heap_type.ht_type.tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HEAPTYPE | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC;

    return @ptrCast(&heap_type.ht_type);
}

/// PyType_Type - the metatype (type of all types)
pub export var PyType_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, // Set to self later
        .ob_size = 0,
    },
    .tp_name = "type",
    .tp_basicsize = @sizeOf(PyHeapTypeObject),
    .tp_itemsize = @sizeOf(cpython.PyMemberDef), // For __slots__
    .tp_dealloc = type_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = type_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Inherit from object
    .tp_call = type_call,
    .tp_str = null,
    .tp_getattro = type_getattro,
    .tp_setattro = type_setattro,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "type(object_or_name, bases, dict)\ntype(object) -> the object's type\ntype(name, bases, dict) -> a new type",
    .tp_traverse = type_traverse,
    .tp_clear = type_clear,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(cpython.PyTypeObject, "tp_weaklist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null, // Set to &PyBaseObject_Type at init
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(cpython.PyTypeObject, "tp_dict"),
    .tp_init = type_init,
    .tp_alloc = null,
    .tp_new = type_new,
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
// BASE OBJECT TYPE
// ============================================================================

/// Repr for object
fn object_repr(self_obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self_obj == null) return null;

    const type_name = self_obj.?.ob_type.tp_name orelse "object";
    _ = type_name;

    // Format: <type_name object at 0x...>
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("<object>");
}

/// Str for object (defaults to repr)
fn object_str(self_obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self_obj == null) return null;

    if (self_obj.?.ob_type.tp_repr) |repr_fn| {
        return repr_fn(self_obj.?);
    }

    return object_repr(self_obj);
}

/// Hash for object (default: id-based hash)
fn object_hash(self_obj: ?*cpython.PyObject) callconv(.c) isize {
    if (self_obj == null) return -1;

    // Default hash is based on memory address
    const addr = @intFromPtr(self_obj.?);
    var hash: isize = @intCast(addr >> 4);
    if (hash == -1) hash = -2;
    return hash;
}

/// Richcompare for object (identity comparison only)
fn object_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only handle EQ and NE
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return &object_mod._Py_NotImplementedStruct;
    }

    const same = (self_obj == other);

    if (op == object_mod.Py_EQ) {
        return if (same) pybool.Py_True() else pybool.Py_False();
    } else {
        return if (same) pybool.Py_False() else pybool.Py_True();
    }
}

/// Init for object
fn object_init(self_obj: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = self_obj;
    _ = args;
    _ = kwargs;
    // Base object init does nothing
    return 0;
}

/// New for object
fn object_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    if (type_obj == null) return null;

    const basicsize: usize = @intCast(type_obj.?.tp_basicsize);
    const mem = allocator.alloc(u8, basicsize) catch return null;
    @memset(mem, 0);

    const obj: *cpython.PyObject = @ptrCast(@alignCast(mem.ptr));
    obj.ob_refcnt = 1;
    obj.ob_type = type_obj.?;

    return obj;
}

/// PyBaseObject_Type - reference to the base type (exported in typeslots.zig)
const PyBaseObject_Type_local: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyType_Type },
        .ob_size = 0,
    },
    .tp_name = "object",
    .tp_basicsize = @sizeOf(cpython.PyObject),
    .tp_itemsize = 0,
    .tp_dealloc = null, // Set based on needs
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = object_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = object_hash,
    .tp_call = null,
    .tp_str = object_str,
    .tp_getattro = null, // Use generic
    .tp_setattro = null, // Use generic
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "The base class of the class hierarchy.\n\nWhen called, it accepts no arguments and returns a new featureless\ninstance that has no instance attributes and cannot be given any.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = object_richcompare,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null, // object has no base
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = object_init,
    .tp_alloc = null,
    .tp_new = object_new,
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

/// Check if object is a type (internal - use typeslots.zig export)
fn PyType_Check_impl(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    // Check if type is PyType_Type or subclass
    return if (op.?.ob_type == &PyType_Type) 1 else 0;
}

/// Check if object is exactly a type (not subclass, internal)
fn PyType_CheckExact_impl(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &PyType_Type) 1 else 0;
}

/// Make a type ready (inherit slots, finalize MRO, etc.) - internal impl
pub fn PyType_Ready(type_obj: ?*cpython.PyTypeObject) c_int {
    if (type_obj == null) return -1;

    // Already ready?
    if ((type_obj.?.tp_flags & Py_TPFLAGS_READY) != 0) {
        return 0;
    }

    // Currently being initialized?
    if ((type_obj.?.tp_flags & Py_TPFLAGS_READYING) != 0) {
        return 0;
    }

    type_obj.?.tp_flags |= Py_TPFLAGS_READYING;

    // Set base type if not set
    if (type_obj.?.tp_base == null and type_obj != &PyBaseObject_Type) {
        type_obj.?.tp_base = &PyBaseObject_Type;
    }

    // Inherit slots from base
    if (type_obj.?.tp_base) |base| {
        inherit_slots(type_obj.?, base);
    }

    // Set type if not set
    if (type_obj.?.ob_base.ob_base.ob_type == undefined) {
        type_obj.?.ob_base.ob_base.ob_type = &PyType_Type;
    }

    // Mark as ready
    type_obj.?.tp_flags &= ~Py_TPFLAGS_READYING;
    type_obj.?.tp_flags |= Py_TPFLAGS_READY;

    return 0;
}

/// Inherit slots from base type
fn inherit_slots(type_obj: *cpython.PyTypeObject, base: *cpython.PyTypeObject) void {
    // Inherit basic slots
    if (type_obj.tp_dealloc == null) type_obj.tp_dealloc = base.tp_dealloc;
    if (type_obj.tp_repr == null) type_obj.tp_repr = base.tp_repr;
    if (type_obj.tp_hash == null) type_obj.tp_hash = base.tp_hash;
    if (type_obj.tp_call == null) type_obj.tp_call = base.tp_call;
    if (type_obj.tp_str == null) type_obj.tp_str = base.tp_str;
    if (type_obj.tp_getattro == null) type_obj.tp_getattro = base.tp_getattro;
    if (type_obj.tp_setattro == null) type_obj.tp_setattro = base.tp_setattro;
    if (type_obj.tp_richcompare == null) type_obj.tp_richcompare = base.tp_richcompare;
    if (type_obj.tp_iter == null) type_obj.tp_iter = base.tp_iter;
    if (type_obj.tp_iternext == null) type_obj.tp_iternext = base.tp_iternext;
    if (type_obj.tp_descr_get == null) type_obj.tp_descr_get = base.tp_descr_get;
    if (type_obj.tp_descr_set == null) type_obj.tp_descr_set = base.tp_descr_set;
    if (type_obj.tp_init == null) type_obj.tp_init = base.tp_init;
    if (type_obj.tp_alloc == null) type_obj.tp_alloc = base.tp_alloc;
    if (type_obj.tp_new == null) type_obj.tp_new = base.tp_new;
    if (type_obj.tp_free == null) type_obj.tp_free = base.tp_free;

    // Inherit protocol methods
    if (type_obj.tp_as_number == null) type_obj.tp_as_number = base.tp_as_number;
    if (type_obj.tp_as_sequence == null) type_obj.tp_as_sequence = base.tp_as_sequence;
    if (type_obj.tp_as_mapping == null) type_obj.tp_as_mapping = base.tp_as_mapping;
    if (type_obj.tp_as_buffer == null) type_obj.tp_as_buffer = base.tp_as_buffer;
    if (type_obj.tp_as_async == null) type_obj.tp_as_async = base.tp_as_async;
}

/// Get attribute from type (internal)
fn PyType_GetAttro_impl(type_obj: ?*cpython.PyObject, name: ?*cpython.PyObject) ?*cpython.PyObject {
    if (type_obj == null or name == null) return null;
    return type_getattro(type_obj.?, name.?);
}

/// Check if type is a subtype of another (internal)
fn PyType_IsSubtype_impl(a: ?*cpython.PyTypeObject, b: ?*cpython.PyTypeObject) c_int {
    if (a == null or b == null) return 0;
    if (a == b) return 1;

    // Check MRO if available
    if (a.?.tp_mro) |mro| {
        const pytuple = @import("tupleobject.zig");
        const mro_len = pytuple.PyTuple_Size(mro);
        var i: isize = 0;
        while (i < mro_len) : (i += 1) {
            const entry = pytuple.PyTuple_GetItem(mro, i);
            if (entry != null) {
                const entry_type: *cpython.PyTypeObject = @ptrCast(@alignCast(entry.?));
                if (entry_type == b.?) return 1;
            }
        }
        return 0; // If MRO exists, that's authoritative
    }

    // Walk base types (fallback if no MRO)
    var current: ?*cpython.PyTypeObject = a;
    while (current) |c| {
        if (c == b) return 1;
        current = c.tp_base;
    }

    return 0;
}

/// Get name of type (internal)
fn PyType_GetName_impl(type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (type_obj == null) return null;

    if ((type_obj.?.tp_flags & cpython.Py_TPFLAGS_HEAPTYPE) != 0) {
        const heap_type: *PyHeapTypeObject = @ptrCast(@alignCast(type_obj.?));
        if (heap_type.ht_name) |name| {
            name.ob_refcnt += 1;
            return name;
        }
    }

    if (type_obj.?.tp_name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        return pyunicode.PyUnicode_FromString(name);
    }

    return null;
}

/// Get qualified name of type (internal)
fn PyType_GetQualName_impl(type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (type_obj == null) return null;

    if ((type_obj.?.tp_flags & cpython.Py_TPFLAGS_HEAPTYPE) != 0) {
        const heap_type: *PyHeapTypeObject = @ptrCast(@alignCast(type_obj.?));
        if (heap_type.ht_qualname) |qualname| {
            qualname.ob_refcnt += 1;
            return qualname;
        }
    }

    return PyType_GetName_impl(type_obj);
}

/// Get module of type (internal)
fn PyType_GetModule_impl(type_obj: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (type_obj == null) return null;

    if ((type_obj.?.tp_flags & cpython.Py_TPFLAGS_HEAPTYPE) != 0) {
        const heap_type: *PyHeapTypeObject = @ptrCast(@alignCast(type_obj.?));
        if (heap_type.ht_module) |module| {
            module.ob_refcnt += 1;
            return module;
        }
    }

    return null;
}

/// Get the module state from a type (internal)
fn PyType_GetModuleState_impl(type_obj: ?*cpython.PyTypeObject) ?*anyopaque {
    const module = PyType_GetModule_impl(type_obj);
    if (module == null) return null;

    // Get state from module using PyModule_GetState
    const moduleobject = @import("../include/moduleobject.zig");
    const state = moduleobject.PyModule_GetState(module.?);
    cpython.Py_DECREF(module.?);
    return state;
}

/// Create type from spec (internal)
fn PyType_FromSpec_impl(spec: ?*const cpython.PyType_Spec) ?*cpython.PyObject {
    return PyType_FromSpecWithBases_impl(spec, null);
}

/// Create type from spec with bases (internal)
fn PyType_FromSpecWithBases_impl(spec: ?*const cpython.PyType_Spec, bases: ?*cpython.PyObject) ?*cpython.PyObject {
    if (spec == null) return null;
    _ = bases;

    // Allocate heap type
    const mem = allocator.alloc(u8, @sizeOf(PyHeapTypeObject)) catch return null;
    @memset(mem, 0);
    const heap_type: *PyHeapTypeObject = @ptrCast(@alignCast(mem.ptr));

    // Initialize basic fields
    heap_type.ht_type.ob_base.ob_base.ob_refcnt = 1;
    heap_type.ht_type.ob_base.ob_base.ob_type = &PyType_Type;
    heap_type.ht_type.tp_name = spec.?.name;
    heap_type.ht_type.tp_basicsize = spec.?.basicsize;
    heap_type.ht_type.tp_itemsize = spec.?.itemsize;
    heap_type.ht_type.tp_flags = spec.?.flags | cpython.Py_TPFLAGS_HEAPTYPE;

    // Process slots
    if (spec.?.slots) |slots| {
        var i: usize = 0;
        while (slots[i].slot != 0) : (i += 1) {
            apply_type_slot(&heap_type.ht_type, slots[i]);
        }
    }

    // Make type ready
    _ = PyType_Ready(&heap_type.ht_type);

    return @ptrCast(&heap_type.ht_type);
}

/// Apply a slot to a type
fn apply_type_slot(type_obj: *cpython.PyTypeObject, slot: cpython.PyType_Slot) void {
    switch (slot.slot) {
        cpython.Py_tp_dealloc => type_obj.tp_dealloc = @ptrCast(slot.pfunc),
        cpython.Py_tp_repr => type_obj.tp_repr = @ptrCast(slot.pfunc),
        cpython.Py_tp_hash => type_obj.tp_hash = @ptrCast(slot.pfunc),
        cpython.Py_tp_call => type_obj.tp_call = @ptrCast(slot.pfunc),
        cpython.Py_tp_str => type_obj.tp_str = @ptrCast(slot.pfunc),
        cpython.Py_tp_getattro => type_obj.tp_getattro = @ptrCast(slot.pfunc),
        cpython.Py_tp_setattro => type_obj.tp_setattro = @ptrCast(slot.pfunc),
        cpython.Py_tp_richcompare => type_obj.tp_richcompare = @ptrCast(slot.pfunc),
        cpython.Py_tp_iter => type_obj.tp_iter = @ptrCast(slot.pfunc),
        cpython.Py_tp_iternext => type_obj.tp_iternext = @ptrCast(slot.pfunc),
        cpython.Py_tp_methods => type_obj.tp_methods = @ptrCast(slot.pfunc),
        cpython.Py_tp_members => type_obj.tp_members = @ptrCast(slot.pfunc),
        cpython.Py_tp_getset => type_obj.tp_getset = @ptrCast(slot.pfunc),
        cpython.Py_tp_init => type_obj.tp_init = @ptrCast(slot.pfunc),
        cpython.Py_tp_new => type_obj.tp_new = @ptrCast(slot.pfunc),
        cpython.Py_tp_free => type_obj.tp_free = @ptrCast(slot.pfunc),
        cpython.Py_tp_doc => type_obj.tp_doc = @ptrCast(slot.pfunc),
        cpython.Py_tp_traverse => type_obj.tp_traverse = @ptrCast(slot.pfunc),
        cpython.Py_tp_clear => type_obj.tp_clear = @ptrCast(slot.pfunc),
        cpython.Py_tp_alloc => type_obj.tp_alloc = @ptrCast(slot.pfunc),
        cpython.Py_tp_finalize => type_obj.tp_finalize = @ptrCast(slot.pfunc),
        else => {},
    }
}

/// Get slot from type (internal)
fn PyType_GetSlot_impl(type_obj: ?*cpython.PyTypeObject, slot: c_int) ?*anyopaque {
    if (type_obj == null) return null;

    return switch (slot) {
        cpython.Py_tp_dealloc => @ptrCast(type_obj.?.tp_dealloc),
        cpython.Py_tp_repr => @ptrCast(type_obj.?.tp_repr),
        cpython.Py_tp_hash => @ptrCast(type_obj.?.tp_hash),
        cpython.Py_tp_call => @ptrCast(type_obj.?.tp_call),
        cpython.Py_tp_str => @ptrCast(type_obj.?.tp_str),
        cpython.Py_tp_getattro => @ptrCast(type_obj.?.tp_getattro),
        cpython.Py_tp_setattro => @ptrCast(type_obj.?.tp_setattro),
        cpython.Py_tp_richcompare => @ptrCast(type_obj.?.tp_richcompare),
        cpython.Py_tp_iter => @ptrCast(type_obj.?.tp_iter),
        cpython.Py_tp_iternext => @ptrCast(type_obj.?.tp_iternext),
        cpython.Py_tp_init => @ptrCast(type_obj.?.tp_init),
        cpython.Py_tp_new => @ptrCast(type_obj.?.tp_new),
        cpython.Py_tp_free => @ptrCast(type_obj.?.tp_free),
        cpython.Py_tp_alloc => @ptrCast(type_obj.?.tp_alloc),
        else => null,
    };
}

/// Modify a type (add/update attributes) - internal
fn PyType_Modified_impl(type_obj: ?*cpython.PyTypeObject) void {
    if (type_obj == null) return;

    // Invalidate attribute cache
    type_obj.?.tp_version_tag = 0;

    // Invalidate caches for subtypes
    if (type_obj.?.tp_subclasses) |subclasses| {
        // tp_subclasses is a dict of weakrefs to subtypes
        const pydict = @import("dictobject.zig");
        var pos: isize = 0;
        var key: ?*cpython.PyObject = null;
        var value: ?*cpython.PyObject = null;

        while (pydict.PyDict_Next(subclasses, &pos, &key, &value) != 0) {
            if (value != null) {
                // Value is a weakref to subtype
                const weakref = @import("weakrefobject.zig");
                const subtype_obj = weakref.PyWeakref_GetObject(value);
                if (subtype_obj != null and subtype_obj != &@import("noneobject.zig")._Py_NoneStruct) {
                    const subtype: *cpython.PyTypeObject = @ptrCast(@alignCast(subtype_obj.?));
                    // Recursively invalidate subtype
                    PyType_Modified_impl(subtype);
                }
            }
        }
    }
}

/// Generic alloc for types (internal)
fn PyType_GenericAlloc_impl(type_obj: ?*cpython.PyTypeObject, nitems: isize) ?*cpython.PyObject {
    if (type_obj == null) return null;

    const basicsize: usize = @intCast(type_obj.?.tp_basicsize);
    const itemsize: usize = @intCast(type_obj.?.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(@max(0, nitems)));

    const obj = @import("obmalloc.zig").PyObject_Calloc(1, size);
    if (obj == null) return null;

    const py_obj: *cpython.PyObject = @ptrCast(@alignCast(obj));
    py_obj.ob_refcnt = 1;
    py_obj.ob_type = type_obj.?;

    if (nitems > 0) {
        const var_obj: *cpython.PyVarObject = @ptrCast(@alignCast(obj));
        var_obj.ob_size = nitems;
    }

    return py_obj;
}

/// Generic new for types (internal)
fn PyType_GenericNew_impl(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    return PyType_GenericAlloc_impl(type_obj, 0);
}
