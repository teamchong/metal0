/// CPython Type Operations
///
/// This implements type system operations for creating and managing types.
/// Critical for NumPy dtype system and custom array types.

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyErr_SetString = traits.externs.PyErr_SetString;

/// PyType_Type - The metatype (type of all type objects)
pub var PyType_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, // Will point to itself
        .ob_size = 0,
    },
    .tp_name = "type",
    .tp_basicsize = @intCast(@sizeOf(cpython.PyTypeObject)),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = type_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = type_call,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_TYPE_SUBCLASS,
    .tp_doc = "type(object) -> the object's type\ntype(name, bases, dict, **kwds) -> a new type",
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

/// PyBaseObject_Type - The base type for all objects ('object')
pub var PyBaseObject_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, // Will point to &PyType_Type
        .ob_size = 0,
    },
    .tp_name = "object",
    .tp_basicsize = @intCast(@sizeOf(cpython.PyObject)),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "The base class of the class hierarchy.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
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
    .tp_init = null,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

fn object_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const unicode = @import("unicodeobject.zig");
    var buf: [256]u8 = undefined;
    const type_obj = cpython.Py_TYPE(obj);
    const name = if (type_obj.tp_name) |n| std.mem.span(n) else "object";
    const str = std.fmt.bufPrint(&buf, "<{s} object at 0x{x}>", .{ name, @intFromPtr(obj) }) catch return null;
    return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
}

fn object_hash(obj: *cpython.PyObject) callconv(.c) isize {
    // Default hash is based on object identity (pointer)
    return @bitCast(@as(usize, @intFromPtr(obj)) >> 4);
}

fn object_new(type_obj: *cpython.PyTypeObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    // Allocate new object
    const obj = allocator.create(cpython.PyObject) catch return null;
    obj.* = .{
        .ob_refcnt = 1,
        .ob_type = type_obj,
    };
    return obj;
}

fn type_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(obj));
    const unicode = @import("unicodeobject.zig");

    var buf: [256]u8 = undefined;
    const name = type_obj.tp_name orelse "unknown";
    const str = std.fmt.bufPrint(&buf, "<class '{s}'>", .{std.mem.span(name)}) catch return null;
    return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
}

fn type_call(self: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(self));

    // Call tp_new if available
    if (type_obj.tp_new) |new_fn| {
        const result = new_fn(type_obj, args, kwargs);
        if (result) |obj| {
            // Call tp_init if available and successful
            if (type_obj.tp_init) |init_fn| {
                if (init_fn(obj, args, kwargs) < 0) {
                    // Init failed, destroy object
                    if (type_obj.tp_dealloc) |dealloc| {
                        dealloc(obj);
                    }
                    return null;
                }
            }
            return obj;
        }
    }
    return null;
}

fn type_new(metatype: *cpython.PyTypeObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = kwargs;
    const pytuple = @import("../objects/tupleobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");
    const pydict = @import("../objects/dictobject.zig");

    // type(name, bases, dict) -> new type
    const nargs = pytuple.PyTuple_Size(args);
    if (nargs == 1) {
        // type(object) -> return the object's type
        const obj = pytuple.PyTuple_GetItem(args, 0) orelse return null;
        const obj_type = cpython.Py_TYPE(obj);
        Py_INCREF(@ptrCast(obj_type));
        return @ptrCast(obj_type);
    }

    if (nargs != 3) {
        return null;
    }

    // Get name, bases, dict
    const name_obj = pytuple.PyTuple_GetItem(args, 0) orelse return null;
    const bases = pytuple.PyTuple_GetItem(args, 1) orelse return null;
    const dict = pytuple.PyTuple_GetItem(args, 2) orelse return null;

    const name_str = pyunicode.PyUnicode_AsUTF8(name_obj) orelse return null;

    // Allocate new type object
    const new_type = allocator.create(cpython.PyTypeObject) catch return null;

    // Initialize with defaults from metatype
    new_type.* = metatype.*;

    // Copy name
    const name_copy = allocator.dupeZ(u8, std.mem.span(name_str)) catch {
        allocator.destroy(new_type);
        return null;
    };
    new_type.tp_name = name_copy;

    // Set up base type
    if (pytuple.PyTuple_Size(bases) > 0) {
        const base_obj = pytuple.PyTuple_GetItem(bases, 0);
        if (base_obj) |b| {
            new_type.tp_base = @ptrCast(@alignCast(b));
        }
    }

    // Copy dict
    new_type.tp_dict = pydict.PyDict_Copy(dict);

    // Set refcount
    new_type.ob_base.ob_base.ob_refcnt = 1;
    new_type.ob_base.ob_base.ob_type = metatype;

    // Mark as heap type
    new_type.tp_flags |= Py_TPFLAGS_HEAPTYPE;

    return @ptrCast(new_type);
}

/// Check if object is a type (instance of PyType_Type or subclass)
export fn PyType_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    const flags = type_obj.tp_flags;
    // Check TYPE_SUBCLASS flag
    return if ((flags & cpython.Py_TPFLAGS_TYPE_SUBCLASS) != 0) 1 else 0;
}

/// Check if object is exactly PyType_Type
export fn PyType_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyType_Type) 1 else 0;
}

/// Finalize type object - initializes inherited slots and type metadata
/// This is critical for C extensions that create custom types
export fn PyType_Ready(type_obj: *cpython.PyTypeObject) callconv(.c) c_int {
    // Already ready?
    if ((type_obj.tp_flags & Py_TPFLAGS_READY) != 0) {
        return 0;
    }

    // Prevent infinite recursion during type setup
    if ((type_obj.tp_flags & Py_TPFLAGS_READYING) != 0) {
        return 0;
    }
    type_obj.tp_flags |= Py_TPFLAGS_READYING;

    // 1. Set default base type if not set (except for 'object' itself)
    if (type_obj.tp_base == null and type_obj != &PyBaseObject_Type) {
        type_obj.tp_base = &PyBaseObject_Type;
        Py_INCREF(@ptrCast(&PyBaseObject_Type));
    }

    // 2. Ensure base type is ready first
    if (type_obj.tp_base) |base| {
        if ((base.tp_flags & Py_TPFLAGS_READY) == 0) {
            if (PyType_Ready(base) < 0) {
                type_obj.tp_flags &= ~Py_TPFLAGS_READYING;
                return -1;
            }
        }
    }

    // 3. Inherit slots from base type
    if (type_obj.tp_base) |base| {
        inherit_special_slots(type_obj, base);
    }

    // 4. Initialize tp_dict if null
    if (type_obj.tp_dict == null) {
        const pydict = @import("../objects/dictobject.zig");
        type_obj.tp_dict = pydict.PyDict_New();
        if (type_obj.tp_dict == null) {
            type_obj.tp_flags &= ~Py_TPFLAGS_READYING;
            return -1;
        }
    }

    // 5. Build tp_bases tuple (single inheritance for now)
    if (type_obj.tp_bases == null) {
        const pytuple = @import("../objects/tupleobject.zig");
        if (type_obj.tp_base) |base| {
            const bases = pytuple.PyTuple_New(1);
            if (bases) |b| {
                Py_INCREF(@ptrCast(base));
                _ = pytuple.PyTuple_SetItem(b, 0, @ptrCast(base));
                type_obj.tp_bases = b;
            }
        } else {
            // object has empty bases
            type_obj.tp_bases = pytuple.PyTuple_New(0);
        }
    }

    // 6. Build MRO (Method Resolution Order) - simple linear MRO for single inheritance
    if (type_obj.tp_mro == null) {
        type_obj.tp_mro = compute_mro(type_obj);
    }

    // 7. Set default tp_alloc if not set
    if (type_obj.tp_alloc == null) {
        type_obj.tp_alloc = PyType_GenericAlloc;
    }

    // 8. Set default tp_new if not set and base has one
    if (type_obj.tp_new == null) {
        if (type_obj.tp_base) |base| {
            type_obj.tp_new = base.tp_new;
        }
    }

    // 9. Set default tp_free if not set
    if (type_obj.tp_free == null) {
        type_obj.tp_free = default_tp_free;
    }

    // 10. Set ob_type to metatype if not set
    if (@intFromPtr(type_obj.ob_base.ob_base.ob_type) == 0 or
        type_obj.ob_base.ob_base.ob_type == undefined)
    {
        type_obj.ob_base.ob_base.ob_type = &PyType_Type;
    }

    // Mark as ready
    type_obj.tp_flags &= ~Py_TPFLAGS_READYING;
    type_obj.tp_flags |= Py_TPFLAGS_READY;

    return 0;
}

/// Inherit special slots from base type
fn inherit_special_slots(type_obj: *cpython.PyTypeObject, base: *cpython.PyTypeObject) void {
    // Inherit tp_basicsize if not set
    if (type_obj.tp_basicsize == 0) {
        type_obj.tp_basicsize = base.tp_basicsize;
    }

    // Inherit tp_itemsize if not set
    if (type_obj.tp_itemsize == 0) {
        type_obj.tp_itemsize = base.tp_itemsize;
    }

    // Inherit dealloc
    if (type_obj.tp_dealloc == null) {
        type_obj.tp_dealloc = base.tp_dealloc;
    }

    // Inherit repr
    if (type_obj.tp_repr == null) {
        type_obj.tp_repr = base.tp_repr;
    }

    // Inherit hash
    if (type_obj.tp_hash == null) {
        type_obj.tp_hash = base.tp_hash;
    }

    // Inherit str
    if (type_obj.tp_str == null) {
        type_obj.tp_str = base.tp_str;
    }

    // Inherit getattro/setattro
    if (type_obj.tp_getattro == null) {
        type_obj.tp_getattro = base.tp_getattro;
    }
    if (type_obj.tp_setattro == null) {
        type_obj.tp_setattro = base.tp_setattro;
    }

    // Inherit rich compare
    if (type_obj.tp_richcompare == null) {
        type_obj.tp_richcompare = base.tp_richcompare;
    }

    // Inherit iter/iternext
    if (type_obj.tp_iter == null) {
        type_obj.tp_iter = base.tp_iter;
    }
    if (type_obj.tp_iternext == null) {
        type_obj.tp_iternext = base.tp_iternext;
    }

    // Inherit descriptor get/set
    if (type_obj.tp_descr_get == null) {
        type_obj.tp_descr_get = base.tp_descr_get;
    }
    if (type_obj.tp_descr_set == null) {
        type_obj.tp_descr_set = base.tp_descr_set;
    }

    // Inherit init
    if (type_obj.tp_init == null) {
        type_obj.tp_init = base.tp_init;
    }

    // Inherit protocol suites if not set
    if (type_obj.tp_as_number == null) {
        type_obj.tp_as_number = base.tp_as_number;
    }
    if (type_obj.tp_as_sequence == null) {
        type_obj.tp_as_sequence = base.tp_as_sequence;
    }
    if (type_obj.tp_as_mapping == null) {
        type_obj.tp_as_mapping = base.tp_as_mapping;
    }
    if (type_obj.tp_as_async == null) {
        type_obj.tp_as_async = base.tp_as_async;
    }
    if (type_obj.tp_as_buffer == null) {
        type_obj.tp_as_buffer = base.tp_as_buffer;
    }

    // Inherit GC support
    if (type_obj.tp_traverse == null) {
        type_obj.tp_traverse = base.tp_traverse;
    }
    if (type_obj.tp_clear == null) {
        type_obj.tp_clear = base.tp_clear;
    }

    // Inherit finalize
    if (type_obj.tp_finalize == null) {
        type_obj.tp_finalize = base.tp_finalize;
    }

    // Inherit subclass flags from base
    type_obj.tp_flags |= (base.tp_flags & (cpython.Py_TPFLAGS_LONG_SUBCLASS |
        cpython.Py_TPFLAGS_LIST_SUBCLASS |
        cpython.Py_TPFLAGS_TUPLE_SUBCLASS |
        cpython.Py_TPFLAGS_BYTES_SUBCLASS |
        cpython.Py_TPFLAGS_UNICODE_SUBCLASS |
        cpython.Py_TPFLAGS_DICT_SUBCLASS |
        cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS |
        cpython.Py_TPFLAGS_TYPE_SUBCLASS));
}

/// Compute MRO (Method Resolution Order) for single inheritance
fn compute_mro(type_obj: *cpython.PyTypeObject) ?*cpython.PyObject {
    const pytuple = @import("../objects/tupleobject.zig");

    // Count types in hierarchy
    var count: isize = 0;
    var current: ?*cpython.PyTypeObject = type_obj;
    while (current) |t| {
        count += 1;
        current = t.tp_base;
    }

    // Create MRO tuple
    const mro = pytuple.PyTuple_New(count) orelse return null;

    // Fill MRO (type, base, base.base, ..., object)
    var idx: isize = 0;
    current = type_obj;
    while (current) |t| {
        Py_INCREF(@ptrCast(t));
        _ = pytuple.PyTuple_SetItem(mro, idx, @ptrCast(t));
        idx += 1;
        current = t.tp_base;
    }

    return mro;
}

/// Default tp_free implementation
fn default_tp_free(obj: ?*anyopaque) callconv(.c) void {
    if (obj) |o| {
        allocator.destroy(@as(*cpython.PyObject, @ptrCast(@alignCast(o))));
    }
}

/// Generic type allocation
export fn PyType_GenericAlloc(type_obj: *cpython.PyTypeObject, nitems: isize) callconv(.c) ?*cpython.PyObject {
    const basic_size: usize = @intCast(type_obj.tp_basicsize);
    const item_size: usize = @intCast(type_obj.tp_itemsize);
    const num_items: usize = @intCast(nitems);
    
    const total_size = basic_size + (item_size * num_items);
    
    const memory = allocator.alignedAlloc(u8, @alignOf(cpython.PyObject), total_size) catch return null;
    
    const obj = @as(*cpython.PyObject, @ptrCast(@alignCast(memory.ptr)));
    obj.ob_refcnt = 1;
    obj.ob_type = type_obj;
    
    return obj;
}

/// Generic new
export fn PyType_GenericNew(type_obj: *cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;

    return PyType_GenericAlloc(type_obj, 0);
}

/// Get a builtin type by name
/// Returns the type object for common Python builtin types
pub fn PyType_GetBuiltinType(name: [*:0]const u8) ?*cpython.PyTypeObject {
    const name_slice = std.mem.span(name);

    // Check against known builtin type names
    if (std.mem.eql(u8, name_slice, "type")) {
        return &PyType_Type;
    } else if (std.mem.eql(u8, name_slice, "object")) {
        return &PyBaseObject_Type;
    } else if (std.mem.eql(u8, name_slice, "int")) {
        return @import("../objects/longobject.zig").getPyLongType();
    } else if (std.mem.eql(u8, name_slice, "str")) {
        return @import("../objects/unicodeobject.zig").getPyUnicodeType();
    } else if (std.mem.eql(u8, name_slice, "float")) {
        return @import("../objects/floatobject.zig").getPyFloatType();
    } else if (std.mem.eql(u8, name_slice, "list")) {
        return @import("../objects/listobject.zig").getPyListType();
    } else if (std.mem.eql(u8, name_slice, "dict")) {
        return @import("../objects/dictobject.zig").getPyDictType();
    } else if (std.mem.eql(u8, name_slice, "tuple")) {
        return @import("../objects/tupleobject.zig").getPyTupleType();
    } else if (std.mem.eql(u8, name_slice, "bool")) {
        return @import("../objects/boolobject.zig").getPyBoolType();
    } else if (std.mem.eql(u8, name_slice, "bytes")) {
        return @import("../objects/bytesobject.zig").getPyBytesType();
    } else if (std.mem.eql(u8, name_slice, "set")) {
        return @import("../objects/setobject.zig").getPySetType();
    } else if (std.mem.eql(u8, name_slice, "frozenset")) {
        return @import("../objects/setobject.zig").getPyFrozenSetType();
    } else if (std.mem.eql(u8, name_slice, "NoneType")) {
        return @import("../objects/noneobject.zig").getPyNoneType();
    }

    return null;
}

/// Check if type is subtype
export fn PyType_IsSubtype(a: *cpython.PyTypeObject, b: *cpython.PyTypeObject) callconv(.c) c_int {
    if (a == b) return 1;
    
    // Check base chain
    var current = a.tp_base;
    while (current) |base| {
        if (base == b) return 1;
        current = base.tp_base;
    }
    
    return 0;
}

/// Get type name
export fn PyType_GetName(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");
    if (type_obj.tp_name) |name| {
        return pyunicode.PyUnicode_FromString(name);
    }
    return null;
}

/// Get type qualified name
export fn PyType_GetQualName(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    // For now, same as GetName
    return PyType_GetName(type_obj);
}

/// Get type module
/// For heap types (PEP 3121), returns the module that defined this type
export fn PyType_GetModule(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    const pydict = @import("../objects/dictobject.zig");

    // Check if type has a __dict__
    if (type_obj.tp_dict) |dict| {
        // Look for __module__ attribute
        const pyunicode = @import("unicodeobject.zig");
        const module_name = pyunicode.PyUnicode_FromString("__module__");
        if (module_name) |key| {
            defer traits.decref(key);
            if (pydict.PyDict_GetItem(dict, key)) |module_str| {
                // module_str is the module name string (e.g., "numpy.core")
                // We need to look up in sys.modules to get the actual module object
                const sys = @import("../python/sysmodule.zig");
                const modules = sys.PySys_GetObject("modules");
                if (modules) |mods| {
                    // Get the actual module from sys.modules
                    const name_str = pyunicode.PyUnicode_AsUTF8(module_str);
                    if (name_str) |ns| {
                        return pydict.PyDict_GetItemString(mods, ns);
                    }
                }
            }
        }
    }

    // For non-heap types, check if ht_module is set (heap type structure)
    if ((type_obj.tp_flags & Py_TPFLAGS_HEAPTYPE) != 0) {
        // Cast to heap type and access ht_module
        // HeapTypeObject has ht_module field after PyTypeObject
        const HeapTypePtr = [*]u8;
        const base_ptr: HeapTypePtr = @ptrCast(type_obj);
        const module_offset = @sizeOf(cpython.PyTypeObject);
        const module_ptr: **cpython.PyObject = @ptrCast(@alignCast(base_ptr + module_offset));
        return module_ptr.*;
    }

    return null;
}

/// Get type module state
/// Returns the per-module state for heap types (PEP 3121)
export fn PyType_GetModuleState(type_obj: *cpython.PyTypeObject) callconv(.c) ?*anyopaque {
    // First get the module
    const module = PyType_GetModule(type_obj);
    if (module) |mod| {
        // Get module def from the module
        const module_mod = @import("moduleobject.zig");
        const def = module_mod.PyModule_GetDef(mod);
        if (def) |d| {
            // Get state from module
            const state = module_mod.PyModule_GetState(mod);
            if (state != null and d.m_size > 0) {
                return state;
            }
        }
    }
    return null;
}

/// Modified type (invalidate caches)
/// Called when a type's __dict__ or MRO changes
export fn PyType_Modified(type_obj: *cpython.PyTypeObject) callconv(.c) void {
    // Increment version tag to invalidate attribute caches
    type_obj.tp_version_tag +%= 1;

    // Also invalidate subclasses (recursively)
    // For now, just increment our own version tag
    // A full implementation would walk tp_subclasses
}

/// Has feature flag
export fn PyType_HasFeature(type_obj: *cpython.PyTypeObject, feature: c_ulong) callconv(.c) c_int {
    return if ((type_obj.tp_flags & feature) != 0) 1 else 0;
}

/// Get flags
export fn PyType_GetFlags(type_obj: *cpython.PyTypeObject) callconv(.c) c_ulong {
    return type_obj.tp_flags;
}

/// Get slot value from type
export fn PyType_GetSlot(type_obj: *cpython.PyTypeObject, slot: c_int) callconv(.c) ?*anyopaque {
    // Slot IDs from CPython's typeslots.inc
    return switch (slot) {
        1 => @ptrCast(type_obj.tp_dealloc),
        2 => @ptrCast(type_obj.tp_getattr),
        3 => @ptrCast(type_obj.tp_setattr),
        4 => @ptrCast(type_obj.tp_repr),
        5 => @ptrCast(type_obj.tp_hash),
        6 => @ptrCast(type_obj.tp_call),
        7 => @ptrCast(type_obj.tp_str),
        8 => @ptrCast(type_obj.tp_getattro),
        9 => @ptrCast(type_obj.tp_setattro),
        10 => @ptrCast(type_obj.tp_as_buffer),
        12 => @ptrCast(type_obj.tp_traverse),
        13 => @ptrCast(type_obj.tp_clear),
        14 => @ptrCast(type_obj.tp_richcompare),
        15 => @ptrCast(type_obj.tp_iter),
        16 => @ptrCast(type_obj.tp_iternext),
        17 => @ptrCast(type_obj.tp_methods),
        18 => @ptrCast(type_obj.tp_members),
        19 => @ptrCast(type_obj.tp_getset),
        20 => @ptrCast(type_obj.tp_base),
        22 => @ptrCast(type_obj.tp_descr_get),
        23 => @ptrCast(type_obj.tp_descr_set),
        25 => @ptrCast(type_obj.tp_init),
        26 => @ptrCast(type_obj.tp_alloc),
        27 => @ptrCast(type_obj.tp_new),
        28 => @ptrCast(type_obj.tp_free),
        30 => @ptrCast(type_obj.tp_finalize),
        else => null,
    };
}

/// Check fast subclass flag
export fn PyType_FastSubclass(type_obj: *cpython.PyTypeObject, flag: c_ulong) callconv(.c) c_int {
    return if ((type_obj.tp_flags & flag) != 0) 1 else 0;
}

/// Get base type
export fn PyType_GetBase(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyTypeObject {
    return type_obj.tp_base;
}

/// Get type dict
export fn PyType_GetDict(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    return type_obj.tp_dict;
}

/// Get type bases tuple
export fn PyType_GetBases(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    return type_obj.tp_bases;
}

/// Get type MRO (Method Resolution Order)
export fn PyType_GetMRO(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    return type_obj.tp_mro;
}

// Type feature flags (from CPython)
pub const Py_TPFLAGS_HEAPTYPE: c_ulong = (1 << 9);
pub const Py_TPFLAGS_BASETYPE: c_ulong = (1 << 10);
pub const Py_TPFLAGS_READY: c_ulong = (1 << 12);
pub const Py_TPFLAGS_READYING: c_ulong = (1 << 13);
pub const Py_TPFLAGS_HAVE_GC: c_ulong = (1 << 14);
pub const Py_TPFLAGS_DEFAULT: c_ulong = Py_TPFLAGS_HAVE_GC;

// Tests
test "PyType function exports" {
    _ = PyType_Ready;
    _ = PyType_GenericNew;
    _ = PyType_IsSubtype;
}
