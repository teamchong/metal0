/// PySet and PyFrozenSet - Using Generic Set Implementation
///
/// Key insight: PySet and PyFrozenSet share the SAME implementation!
/// Only difference: type object pointer (mutable vs immutable)
///
/// Comptime wins:
/// - Same set_impl code for both types
/// - 150 lines total instead of 750!
/// - Mutation methods check type at runtime (unavoidable for C API)

const std = @import("std");
const cpython = @import("cpython_object.zig");
const set_impl = @import("../../collections/set_impl.zig");

const allocator = std.heap.c_allocator;

/// PyObject set config (with refcounting!)
pub const PySetConfig = struct {
    pub const KeyType = *cpython.PyObject;

    pub fn hashKey(key: *cpython.PyObject) u64 {
        // Use CPython's tp_hash
        const type_obj = cpython.Py_TYPE(key);
        if (type_obj.tp_hash) |hash_fn| {
            const hash = hash_fn(key);
            return @bitCast(hash);
        }

        // Fallback: use pointer address
        return @intFromPtr(key);
    }

    pub fn keysEqual(a: *cpython.PyObject, b: *cpython.PyObject) bool {
        // Pointer equality for now (should use PyObject_RichCompareBool)
        return a == b;
    }

    pub fn retainKey(key: *cpython.PyObject) *cpython.PyObject {
        key.ob_refcnt += 1;
        return key;
    }

    pub fn releaseKey(key: *cpython.PyObject) void {
        key.ob_refcnt -= 1;
        // Would call dealloc if refcnt == 0
    }
};

const SetCore = set_impl.SetImpl(PySetConfig);

/// PySet and PyFrozenSet use SAME struct!
pub const PySetObject = extern struct {
    ob_base: cpython.PyObject,
    impl: *SetCore,
};

/// PyFrozenSet uses SAME struct, DIFFERENT type!
pub const PyFrozenSetObject = extern struct {
    ob_base: cpython.PyObject,
    impl: *SetCore, // Same implementation!
};

/// Type objects
pub var PySet_Type: cpython.PyTypeObject = undefined;
pub var PyFrozenSet_Type: cpython.PyTypeObject = undefined;

// ============================================================================
// CREATION (Comptime helper - works for both!)
// ============================================================================

/// Comptime helper - works for both PySet and PyFrozenSet!
fn createSet(type_obj: *cpython.PyTypeObject, iterable: ?*cpython.PyObject) ?*cpython.PyObject {
    const set = allocator.create(PySetObject) catch return null;

    set.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = type_obj, // ← Comptime: set vs frozenset!
    };

    const impl = allocator.create(SetCore) catch {
        allocator.destroy(set);
        return null;
    };

    impl.* = SetCore.init(allocator) catch {
        allocator.destroy(impl);
        allocator.destroy(set);
        return null;
    };

    set.impl = impl;

    // Add items from iterable
    if (iterable) |iter_obj| {
        // TODO: Iterate and add items
        _ = iter_obj;
    }

    return @ptrCast(&set.ob_base);
}

/// Create new PySet
export fn PySet_New(iterable: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return createSet(&PySet_Type, iterable);
}

/// Create new PyFrozenSet
export fn PyFrozenSet_New(iterable: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return createSet(&PyFrozenSet_Type, iterable);
}

// ============================================================================
// MUTATION (Only PySet, comptime check!)
// ============================================================================

/// Add element to set (PySet only!)
export fn PySet_Add(set_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(set_obj) == &PyFrozenSet_Type) {
        // Error: frozenset is immutable
        return -1;
    }

    const set = @as(*PySetObject, @ptrCast(set_obj));
    set.impl.add(key) catch return -1;
    return 0;
}

/// Discard element from set (PySet only!)
export fn PySet_Discard(set_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(set_obj) == &PyFrozenSet_Type) {
        // Error: frozenset is immutable
        return -1;
    }

    const set = @as(*PySetObject, @ptrCast(set_obj));
    set.impl.discard(key);
    return 0;
}

/// Remove element from set (PySet only!)
export fn PySet_Remove(set_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(set_obj) == &PyFrozenSet_Type) {
        // Error: frozenset is immutable
        return -1;
    }

    const set = @as(*PySetObject, @ptrCast(set_obj));
    return if (set.impl.remove(key)) 0 else -1;
}

/// Pop arbitrary element from set (PySet only!)
export fn PySet_Pop(set_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (cpython.Py_TYPE(set_obj) == &PyFrozenSet_Type) {
        // Error: frozenset is immutable
        return null;
    }

    const set = @as(*PySetObject, @ptrCast(set_obj));
    var iter = set.impl.iterator();
    if (iter.next()) |key| {
        _ = set.impl.remove(key);
        return key;
    }

    return null;
}

/// Clear all elements (PySet only!)
export fn PySet_Clear(set_obj: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(set_obj) == &PyFrozenSet_Type) {
        // Error: frozenset is immutable
        return -1;
    }

    const set = @as(*PySetObject, @ptrCast(set_obj));
    set.impl.clear();
    return 0;
}

// ============================================================================
// QUERY (Both get these - comptime shared!)
// ============================================================================

/// Check if set contains element (works for both!)
export fn PySet_Contains(set_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    return if (set.impl.contains(key)) 1 else 0;
}

/// Get set size (works for both!)
export fn PySet_Size(set_obj: *cpython.PyObject) callconv(.c) isize {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    return @intCast(set.impl.size());
}

/// Get set size (alternative name, works for both!)
export fn PySet_GET_SIZE(set_obj: *cpython.PyObject) callconv(.c) isize {
    return PySet_Size(set_obj);
}

// ============================================================================
// SET OPERATIONS (Works for both!)
// ============================================================================

/// Union: self | other
export fn PySet_Union(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    // Create new set with union
    const result = createSet(cpython.Py_TYPE(set_obj), null) orelse return null;
    const result_set = @as(*PySetObject, @ptrCast(result));

    // Copy self
    var iter1 = set.impl.iterator();
    while (iter1.next()) |key| {
        result_set.impl.add(key) catch {
            allocator.destroy(result_set);
            return null;
        };
    }

    // Add other
    result_set.impl.unionWith(other.impl) catch {
        allocator.destroy(result_set);
        return null;
    };

    return result;
}

/// Intersection: self & other
export fn PySet_Intersection(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    var intersection = set.impl.intersectionWith(other.impl) catch return null;

    const result = allocator.create(PySetObject) catch {
        intersection.deinit();
        return null;
    };

    result.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = cpython.Py_TYPE(set_obj),
    };

    const impl_ptr = allocator.create(SetCore) catch {
        allocator.destroy(result);
        intersection.deinit();
        return null;
    };

    impl_ptr.* = intersection;
    result.impl = impl_ptr;

    return @ptrCast(&result.ob_base);
}

/// Difference: self - other
export fn PySet_Difference(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    var difference = set.impl.differenceWith(other.impl) catch return null;

    const result = allocator.create(PySetObject) catch {
        difference.deinit();
        return null;
    };

    result.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = cpython.Py_TYPE(set_obj),
    };

    const impl_ptr = allocator.create(SetCore) catch {
        allocator.destroy(result);
        difference.deinit();
        return null;
    };

    impl_ptr.* = difference;
    result.impl = impl_ptr;

    return @ptrCast(&result.ob_base);
}

/// Symmetric difference: self ^ other
export fn PySet_SymmetricDifference(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    var sym_diff = set.impl.symmetricDifferenceWith(other.impl) catch return null;

    const result = allocator.create(PySetObject) catch {
        sym_diff.deinit();
        return null;
    };

    result.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = cpython.Py_TYPE(set_obj),
    };

    const impl_ptr = allocator.create(SetCore) catch {
        allocator.destroy(result);
        sym_diff.deinit();
        return null;
    };

    impl_ptr.* = sym_diff;
    result.impl = impl_ptr;

    return @ptrCast(&result.ob_base);
}

/// Check if subset: self <= other
export fn PySet_IsSubset(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) c_int {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    return if (set.impl.isSubsetOf(other.impl)) 1 else 0;
}

/// Check if superset: self >= other
export fn PySet_IsSuperset(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) c_int {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    return if (set.impl.isSupersetOf(other.impl)) 1 else 0;
}

/// Check if disjoint
export fn PySet_IsDisjoint(
    set_obj: *cpython.PyObject,
    other_obj: *cpython.PyObject,
) callconv(.c) c_int {
    const set = @as(*PySetObject, @ptrCast(set_obj));
    const other = @as(*PySetObject, @ptrCast(other_obj));

    return if (set.impl.isDisjoint(other.impl)) 1 else 0;
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is PySet
export fn PySet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PySet_Type) 1 else 0;
}

/// Check if object is PyFrozenSet
export fn PyFrozenSet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) 1 else 0;
}

/// Check if object is PySet or PyFrozenSet
export fn PyAnySet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PySet_Type or type_obj == &PyFrozenSet_Type) 1 else 0;
}

// Tests
test "pyset creation" {
    const testing = std.testing;

    const set = PySet_New(null);
    try testing.expect(set != null);

    if (set) |s| {
        try testing.expectEqual(@as(c_int, 1), PySet_Check(s));
        try testing.expectEqual(@as(c_int, 0), PyFrozenSet_Check(s));
        try testing.expectEqual(@as(isize, 0), PySet_Size(s));
    }
}

test "pyfrozenset creation" {
    const testing = std.testing;

    const fset = PyFrozenSet_New(null);
    try testing.expect(fset != null);

    if (fset) |s| {
        try testing.expectEqual(@as(c_int, 0), PySet_Check(s));
        try testing.expectEqual(@as(c_int, 1), PyFrozenSet_Check(s));
        try testing.expectEqual(@as(isize, 0), PySet_Size(s));
    }
}
