/// Optimization helpers for C interop layer
///
/// Provides optimized allocator selection and hash functions
/// based on proven patterns from tokenizer package

const std = @import("std");
const builtin = @import("builtin");

// Use std hash instead of external wyhash to avoid import issues
const wyhash = struct {
    pub const WyhashStateless = struct {
        pub fn hash(_: u64, data: []const u8) u64 {
            return std.hash.Wyhash.hash(0, data);
        }
    };
};

/// Get optimal allocator for C interop
/// - C extensions expect C allocator behavior
/// - Must use std.heap.c_allocator for CPython compatibility
/// - This is correct and cannot be changed (C extensions rely on it)
pub fn getCInteropAllocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

/// Fast string hash context using wyhash (from Bun, 1.05x faster)
/// Use for PyDict string key hashing
pub const WyhashStringContext = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        return wyhash.WyhashStateless.hash(0, key);
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

/// Type alias for string-keyed HashMap with wyhash
/// Use for PyDict internal implementation
pub fn StringHashMap(comptime V: type) type {
    return std.HashMap([]const u8, V, WyhashStringContext, std.hash_map.default_max_load_percentage);
}

/// Fast hash for PyObject pointers (used in PyDict)
/// Uses identity hash (pointer value) which is correct for Python
pub fn hashPyObject(obj: *const anyopaque) u64 {
    const ptr_val = @intFromPtr(obj);
    return wyhash.WyhashStateless.hash(0, std.mem.asBytes(&ptr_val));
}

/// Fast hash for string data (used when hashing string contents)
pub fn hashString(data: []const u8) u64 {
    return wyhash.WyhashStateless.hash(0, data);
}

// ============================================================================
// POINTER CAST HELPERS
// ============================================================================

/// Safe pointer cast with alignment - reduces @ptrCast(@alignCast(...)) noise
/// Usage: const obj = ptrCast(*PyListObject, raw_ptr);
pub inline fn ptrCast(comptime T: type, ptr: anytype) T {
    return @ptrCast(@alignCast(ptr));
}

/// Cast PyObject to specific type
/// Usage: const list = pyObjCast(*PyListObject, obj);
pub inline fn pyObjCast(comptime T: type, obj: anytype) T {
    return @ptrCast(@alignCast(obj));
}

/// Get data stored after a variable-sized object
/// Usage: const data = getPostObjectData(*UnicodeData, unicode, @sizeOf(PyUnicodeObject));
pub inline fn getPostObjectData(comptime T: type, obj: anytype, base_size: usize) T {
    const addr = @intFromPtr(obj) + base_size;
    return @ptrFromInt(addr);
}

// ============================================================================
// TYPE OBJECT BUILDER
// ============================================================================

const cpython = @import("cpython_object.zig");

/// Configuration for building a PyTypeObject
pub const TypeObjectConfig = struct {
    name: [*:0]const u8,
    basicsize: usize,
    itemsize: usize = 0,
    flags: u64 = cpython.Py_TPFLAGS_DEFAULT,
    doc: ?[*:0]const u8 = null,
    dealloc: ?*const fn (*cpython.PyObject) callconv(.c) void = null,
    repr: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject = null,
    hash: ?*const fn (*cpython.PyObject) callconv(.c) isize = null,
    str: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject = null,
    as_number: ?*cpython.PyNumberMethods = null,
    as_sequence: ?*cpython.PySequenceMethods = null,
    as_mapping: ?*cpython.PyMappingMethods = null,
    richcompare: ?*const fn (*cpython.PyObject, *cpython.PyObject, c_int) callconv(.c) ?*cpython.PyObject = null,
    iter: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject = null,
    iternext: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject = null,
};

/// Build a PyTypeObject with sensible defaults - reduces 80+ lines to ~10
pub fn makeTypeObject(config: TypeObjectConfig) cpython.PyTypeObject {
    return .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
            .ob_size = 0,
        },
        .tp_name = config.name,
        .tp_basicsize = @intCast(config.basicsize),
        .tp_itemsize = @intCast(config.itemsize),
        .tp_dealloc = config.dealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = config.repr,
        .tp_as_number = config.as_number,
        .tp_as_sequence = config.as_sequence,
        .tp_as_mapping = config.as_mapping,
        .tp_hash = config.hash,
        .tp_call = null,
        .tp_str = config.str orelse config.repr,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = config.flags,
        .tp_doc = config.doc,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = config.richcompare,
        .tp_weaklistoffset = 0,
        .tp_iter = config.iter,
        .tp_iternext = config.iternext,
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
}

// ============================================================================
// TESTS
// ============================================================================

test "optimization helpers" {
    const alloc = getCInteropAllocator();
    const mem = try alloc.alloc(u8, 100);
    defer alloc.free(mem);
    
    // Test string hash
    const hash1 = hashString("hello");
    const hash2 = hashString("hello");
    const hash3 = hashString("world");
    
    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}
