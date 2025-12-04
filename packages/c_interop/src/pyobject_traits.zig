/// PyObject Traits - Systematic Solutions for Recurring C Interop Patterns
///
/// Similar to function_traits.zig, this provides unified helpers for:
/// | Pattern                    | Solution                                      |
/// |----------------------------|-----------------------------------------------|
/// | Reference counting         | Ref/Unref with automatic cleanup              |
/// | Type checking              | Unified type predicates                       |
/// | Object creation            | Factory functions with proper init            |
/// | Protocol dispatch          | Unified protocol method lookup                |
/// | Error handling             | Consistent error state management             |
/// | Memory management          | Scoped allocations with cleanup               |
///
/// USAGE:
/// ```zig
/// const traits = @import("pyobject_traits.zig");
///
/// // Reference counting
/// const obj = traits.incref(some_obj);
/// defer traits.decref(obj);
///
/// // Type checking
/// if (traits.isInt(obj)) { ... }
/// if (traits.isSequence(obj)) { ... }
///
/// // Safe object creation
/// const list = traits.createList(10) orelse return null;
/// defer traits.decrefIfError(list, &had_error);
///
/// // Protocol dispatch
/// const len = traits.getLength(obj) orelse return -1;
/// ```

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// REFERENCE COUNTING - Solve manual ob_refcnt manipulation
// ============================================================================

/// Increment reference count, return object for chaining
pub inline fn incref(obj: anytype) @TypeOf(obj) {
    if (@typeInfo(@TypeOf(obj)) == .optional) {
        if (obj) |o| {
            const base = getBaseObject(o);
            base.ob_refcnt += 1;
        }
        return obj;
    } else {
        const base = getBaseObject(obj);
        base.ob_refcnt += 1;
        return obj;
    }
}

/// Decrement reference count
pub inline fn decref(obj: anytype) void {
    if (@typeInfo(@TypeOf(obj)) == .optional) {
        if (obj) |o| {
            const base = getBaseObject(o);
            base.ob_refcnt -= 1;
            if (base.ob_refcnt == 0) {
                deallocObject(o);
            }
        }
    } else {
        const base = getBaseObject(obj);
        base.ob_refcnt -= 1;
        if (base.ob_refcnt == 0) {
            deallocObject(obj);
        }
    }
}

/// Decrement only if an error occurred (for cleanup patterns)
pub inline fn decrefIfError(obj: anytype, had_error: *bool) void {
    if (had_error.*) {
        decref(obj);
    }
}

/// Create a borrowed reference (no refcount change, just for documentation)
pub inline fn borrow(obj: anytype) @TypeOf(obj) {
    return obj;
}

/// Steal a reference (transfer ownership, no refcount change)
pub inline fn steal(obj: anytype) @TypeOf(obj) {
    return obj;
}

/// Get base PyObject from any PyObject subtype
inline fn getBaseObject(obj: anytype) *cpython.PyObject {
    const T = @TypeOf(obj);
    if (T == *cpython.PyObject) {
        return obj;
    } else if (@hasField(std.meta.Child(T), "ob_base")) {
        // Direct ob_base field
        const child = std.meta.Child(T);
        if (@TypeOf(@field(@as(*child, undefined), "ob_base")) == cpython.PyObject) {
            return &obj.ob_base;
        } else {
            // Nested ob_base (PyVarObject)
            return &obj.ob_base.ob_base;
        }
    } else {
        return @ptrCast(obj);
    }
}

/// Deallocate object using its type's tp_dealloc
fn deallocObject(obj: anytype) void {
    const base = getBaseObject(obj);
    const type_obj = cpython.Py_TYPE(base);
    if (type_obj.tp_dealloc) |dealloc| {
        dealloc(base);
    }
}

// ============================================================================
// TYPE CHECKING - Unified predicates
// ============================================================================

/// Check if object is an integer (int or bool subclass)
pub inline fn isInt(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_LONG_SUBCLASS) != 0;
}

/// Check if object is a float
pub inline fn isFloat(obj: *cpython.PyObject) bool {
    const pyf = @import("pyobject_float.zig");
    return cpython.Py_TYPE(obj) == &pyf.PyFloat_Type;
}

/// Check if object is a string (unicode)
pub inline fn isString(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_UNICODE_SUBCLASS) != 0;
}

/// Check if object is bytes
pub inline fn isBytes(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_BYTES_SUBCLASS) != 0;
}

/// Check if object is a tuple
pub inline fn isTuple(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_TUPLE_SUBCLASS) != 0;
}

/// Check if object is a list
pub inline fn isList(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_LIST_SUBCLASS) != 0;
}

/// Check if object is a dict
pub inline fn isDict(obj: *cpython.PyObject) bool {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return (flags & cpython.Py_TPFLAGS_DICT_SUBCLASS) != 0;
}

/// Check if object supports sequence protocol
pub inline fn isSequence(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);
    return type_obj.tp_as_sequence != null;
}

/// Check if object supports mapping protocol
pub inline fn isMapping(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);
    return type_obj.tp_as_mapping != null;
}

/// Check if object is callable
pub inline fn isCallable(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);
    return type_obj.tp_call != null;
}

/// Check if object is iterable
pub inline fn isIterable(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);
    return type_obj.tp_iter != null or isSequence(obj);
}

/// Check if object is an iterator
pub inline fn isIterator(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);
    return type_obj.tp_iternext != null;
}

/// Check if object is None
pub inline fn isNone(obj: *cpython.PyObject) bool {
    const pynone = @import("pyobject_none.zig");
    return obj == &pynone._Py_NoneStruct;
}

/// Check if object is True
pub inline fn isTrue(obj: *cpython.PyObject) bool {
    const pybool = @import("pyobject_bool.zig");
    return obj == @as(*cpython.PyObject, @ptrCast(&pybool._Py_TrueStruct.ob_base));
}

/// Check if object is False
pub inline fn isFalse(obj: *cpython.PyObject) bool {
    const pybool = @import("pyobject_bool.zig");
    return obj == @as(*cpython.PyObject, @ptrCast(&pybool._Py_FalseStruct.ob_base));
}

// ============================================================================
// PROTOCOL DISPATCH - Unified method lookup
// ============================================================================

/// Get length of any object (sequence, mapping, or __len__)
pub fn getLength(obj: *cpython.PyObject) ?isize {
    const type_obj = cpython.Py_TYPE(obj);

    // Try sequence protocol first
    if (type_obj.tp_as_sequence) |seq| {
        if (seq.sq_length) |len_fn| {
            return len_fn(obj);
        }
    }

    // Try mapping protocol
    if (type_obj.tp_as_mapping) |map| {
        if (map.mp_length) |len_fn| {
            return len_fn(obj);
        }
    }

    return null;
}

/// Get item by integer index
pub fn getItem(obj: *cpython.PyObject, index: isize) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_sequence) |seq| {
        if (seq.sq_item) |item_fn| {
            return item_fn(obj, index);
        }
    }

    // Fallback to mapping with int key
    if (type_obj.tp_as_mapping) |map| {
        if (map.mp_subscript) |sub_fn| {
            const pylong = @import("pyobject_long.zig");
            const key = pylong.PyLong_FromSsize_t(index) orelse return null;
            defer decref(key);
            return sub_fn(obj, key);
        }
    }

    return null;
}

/// Get item by key object
pub fn getItemByKey(obj: *cpython.PyObject, key: *cpython.PyObject) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_mapping) |map| {
        if (map.mp_subscript) |sub_fn| {
            return sub_fn(obj, key);
        }
    }

    return null;
}

/// Set item by integer index
pub fn setItem(obj: *cpython.PyObject, index: isize, value: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_sequence) |seq| {
        if (seq.sq_ass_item) |ass_fn| {
            return ass_fn(obj, index, value) == 0;
        }
    }

    return false;
}

/// Set item by key object
pub fn setItemByKey(obj: *cpython.PyObject, key: *cpython.PyObject, value: ?*cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_mapping) |map| {
        if (map.mp_ass_subscript) |ass_fn| {
            return ass_fn(obj, key, value) == 0;
        }
    }

    return false;
}

/// Get iterator for object
pub fn getIter(obj: *cpython.PyObject) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_iter) |iter_fn| {
        return iter_fn(obj);
    }

    // Fallback: create sequence iterator
    if (isSequence(obj)) {
        const pyiter = @import("pyobject_iter.zig");
        return pyiter.PySeqIter_New(obj);
    }

    return null;
}

/// Get next item from iterator
pub fn iterNext(iter: *cpython.PyObject) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(iter);

    if (type_obj.tp_iternext) |next_fn| {
        return next_fn(iter);
    }

    return null;
}

/// Get truth value of object
pub fn toBool(obj: *cpython.PyObject) bool {
    const type_obj = cpython.Py_TYPE(obj);

    // Use nb_bool if available
    if (type_obj.tp_as_number) |num| {
        if (num.nb_bool) |bool_fn| {
            return bool_fn(obj) != 0;
        }
    }

    // Use length (non-empty = true)
    if (getLength(obj)) |len| {
        return len > 0;
    }

    // Default: true
    return true;
}

/// Convert to integer
pub fn toInt(obj: *cpython.PyObject) ?i64 {
    const pylong = @import("pyobject_long.zig");

    if (isInt(obj)) {
        return pylong.PyLong_AsLong(obj);
    }

    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_as_number) |num| {
        if (num.nb_int) |int_fn| {
            const result = int_fn(obj) orelse return null;
            defer decref(result);
            return pylong.PyLong_AsLong(result);
        }
    }

    return null;
}

/// Convert to float
pub fn toFloat(obj: *cpython.PyObject) ?f64 {
    const pyfloat = @import("pyobject_float.zig");

    if (isFloat(obj)) {
        return pyfloat.PyFloat_AsDouble(obj);
    }

    if (isInt(obj)) {
        const pylong = @import("pyobject_long.zig");
        return pylong.PyLong_AsDouble(obj);
    }

    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_as_number) |num| {
        if (num.nb_float) |float_fn| {
            const result = float_fn(obj) orelse return null;
            defer decref(result);
            return pyfloat.PyFloat_AsDouble(result);
        }
    }

    return null;
}

// ============================================================================
// OBJECT CREATION - Factory functions
// ============================================================================

/// Create a new list with given size
pub fn createList(size: isize) ?*cpython.PyObject {
    const pylist = @import("pyobject_list.zig");
    return pylist.PyList_New(size);
}

/// Create a new tuple with given size
pub fn createTuple(size: isize) ?*cpython.PyObject {
    const pytuple = @import("pyobject_tuple.zig");
    return pytuple.PyTuple_New(size);
}

/// Create a new dict
pub fn createDict() ?*cpython.PyObject {
    const pydict = @import("pyobject_dict.zig");
    return pydict.PyDict_New();
}

/// Create integer from i64
pub fn createInt(value: i64) ?*cpython.PyObject {
    const pylong = @import("pyobject_long.zig");
    return pylong.PyLong_FromLong(@intCast(value));
}

/// Create float from f64
pub fn createFloat(value: f64) ?*cpython.PyObject {
    const pyfloat = @import("pyobject_float.zig");
    return pyfloat.PyFloat_FromDouble(value);
}

/// Create string from slice
pub fn createString(data: []const u8) ?*cpython.PyObject {
    const pyunicode = @import("cpython_unicode.zig");
    return pyunicode.PyUnicode_FromStringAndSize(data.ptr, @intCast(data.len));
}

/// Create string from C string
pub fn createStringFromCStr(cstr: [*:0]const u8) ?*cpython.PyObject {
    const pyunicode = @import("cpython_unicode.zig");
    return pyunicode.PyUnicode_FromString(cstr);
}

/// Create bytes from slice
pub fn createBytes(data: []const u8) ?*cpython.PyObject {
    const pybytes = @import("pyobject_bytes.zig");
    return pybytes.PyBytes_FromStringAndSize(data.ptr, @intCast(data.len));
}

/// Get None singleton
pub fn none() *cpython.PyObject {
    const pynone = @import("pyobject_none.zig");
    return &pynone._Py_NoneStruct;
}

/// Get True singleton
pub fn true_() *cpython.PyObject {
    const pybool = @import("pyobject_bool.zig");
    return @ptrCast(&pybool._Py_TrueStruct.ob_base);
}

/// Get False singleton
pub fn false_() *cpython.PyObject {
    const pybool = @import("pyobject_bool.zig");
    return @ptrCast(&pybool._Py_FalseStruct.ob_base);
}

/// Create bool from condition
pub fn createBool(condition: bool) *cpython.PyObject {
    return if (condition) true_() else false_();
}

// ============================================================================
// ERROR HANDLING
// ============================================================================

/// Check if an error has occurred
pub fn errorOccurred() bool {
    const exc = @import("pyobject_exceptions.zig");
    return exc.PyErr_Occurred() != null;
}

/// Clear current error
pub fn clearError() void {
    const exc = @import("pyobject_exceptions.zig");
    exc.PyErr_Clear();
}

/// Set error with string message
pub fn setError(comptime exc_type: []const u8, message: [*:0]const u8) void {
    const exc = @import("pyobject_exceptions.zig");
    const type_obj = getExceptionType(exc_type);
    exc.PyErr_SetString(type_obj, message);
}

fn getExceptionType(comptime name: []const u8) *cpython.PyTypeObject {
    const exc = @import("exception_types.zig");
    return switch (name[0]) {
        'T' => &exc.PyExc_TypeError,
        'V' => &exc.PyExc_ValueError,
        'K' => &exc.PyExc_KeyError,
        'I' => &exc.PyExc_IndexError,
        'A' => &exc.PyExc_AttributeError,
        'R' => &exc.PyExc_RuntimeError,
        else => &exc.PyExc_RuntimeError,
    };
}

// ============================================================================
// SCOPED HELPERS
// ============================================================================

/// RAII-style reference holder for automatic decref
pub fn Ref(comptime T: type) type {
    return struct {
        ptr: T,

        const Self = @This();

        pub fn init(obj: T) Self {
            return .{ .ptr = incref(obj) };
        }

        pub fn borrow(obj: T) Self {
            return .{ .ptr = obj };
        }

        pub fn deinit(self: Self) void {
            decref(self.ptr);
        }

        pub fn get(self: Self) T {
            return self.ptr;
        }

        pub fn release(self: *Self) T {
            const ptr = self.ptr;
            self.ptr = undefined;
            return ptr;
        }
    };
}

// ============================================================================
// TYPE REGISTRY - Canonical type definitions
// ============================================================================
// This provides a single import point for all PyObject subtypes.
// Instead of importing from multiple files, use:
//   const types = traits.types;
//   const mod: *types.Module = @ptrCast(@alignCast(obj));

pub const types = struct {
    // Core object types
    pub const Object = cpython.PyObject;
    pub const VarObject = cpython.PyVarObject;
    pub const Type = cpython.PyTypeObject;

    // Numeric types
    pub const Long = @import("pyobject_long.zig").PyLongObject;
    pub const Float = @import("pyobject_float.zig").PyFloatObject;
    pub const Bool = @import("pyobject_bool.zig").PyBoolObject;
    pub const Complex = @import("pyobject_complex.zig").PyComplexObject;

    // Sequence types
    pub const List = @import("pyobject_list.zig").PyListObject;
    pub const Tuple = @import("pyobject_tuple.zig").PyTupleObject;

    // Mapping types
    pub const Dict = @import("pyobject_dict.zig").PyDictObject;
    pub const Set = @import("pyobject_set.zig").PySetObject;
    pub const FrozenSet = @import("pyobject_set.zig").PyFrozenSetObject;

    // String/bytes types (use cpython_unicode for full API)
    pub const Bytes = @import("pyobject_bytes.zig").PyBytesObject;

    // Callable types
    pub const Method = @import("pyobject_method.zig").PyMethodObject;
    // Note: Function and CFunction types defined in cpython_module.zig (PyMethodDef)

    // Closure types
    pub const Cell = @import("pyobject_cell.zig").PyCellObject;
    pub const Generator = @import("pyobject_gen.zig").PyGenObject;
    pub const Coroutine = @import("pyobject_gen.zig").PyCoroObject;
    pub const AsyncGenerator = @import("pyobject_gen.zig").PyAsyncGenObject;
    pub const Frame = @import("pyobject_frame.zig").PyFrameObject;

    // Module types - cpython_module has the module creation API
    pub const Module = @import("cpython_module.zig").PyModuleObject;
    pub const ModuleDef = @import("cpython_module.zig").PyModuleDef;
    pub const MethodDef = @import("cpython_module.zig").PyMethodDef;

    // Iterator types
    pub const SeqIter = @import("pyobject_iter.zig").PySeqIterObject;
    pub const CallIter = @import("pyobject_iter.zig").PyCallIterObject;

    // Range/slice types
    pub const Range = @import("pyobject_range.zig").PyRangeObject;
    pub const Slice = @import("pyobject_slice.zig").PySliceObject;

    // Buffer types
    pub const MemoryView = @import("cpython_memoryview.zig").PyMemoryViewObject;
};

/// Get the canonical type object for a PyObject subtype
pub fn typeObject(comptime T: type) *cpython.PyTypeObject {
    return switch (T) {
        types.Long => &@import("pyobject_long.zig").PyLong_Type,
        types.Float => &@import("pyobject_float.zig").PyFloat_Type,
        types.Bool => &@import("pyobject_bool.zig").PyBool_Type,
        types.List => &@import("pyobject_list.zig").PyList_Type,
        types.Tuple => &@import("pyobject_tuple.zig").PyTuple_Type,
        types.Dict => &@import("pyobject_dict.zig").PyDict_Type,
        types.Set => &@import("pyobject_set.zig").PySet_Type,
        types.FrozenSet => &@import("pyobject_set.zig").PyFrozenSet_Type,
        types.Bytes => &@import("pyobject_bytes.zig").PyBytes_Type,
        types.Cell => &@import("pyobject_cell.zig").PyCell_Type,
        types.Generator => &@import("pyobject_gen.zig").PyGen_Type,
        types.Coroutine => &@import("pyobject_gen.zig").PyCoro_Type,
        types.AsyncGenerator => &@import("pyobject_gen.zig").PyAsyncGen_Type,
        types.Frame => &@import("pyobject_frame.zig").PyFrame_Type,
        types.Module => &@import("cpython_module.zig").PyModule_Type,
        types.Range => &@import("pyobject_range.zig").PyRange_Type,
        types.Slice => &@import("pyobject_slice.zig").PySlice_Type,
        else => @compileError("Unknown type for typeObject"),
    };
}

/// Cast a PyObject to a specific subtype (with type check)
pub fn cast(comptime T: type, obj: *cpython.PyObject) ?*T {
    const type_obj = typeObject(T);
    if (cpython.Py_TYPE(obj) == type_obj) {
        return @ptrCast(@alignCast(obj));
    }
    return null;
}

/// Cast a PyObject to a specific subtype (unsafe, no check)
pub fn castUnchecked(comptime T: type, obj: *cpython.PyObject) *T {
    return @ptrCast(@alignCast(obj));
}

/// Check if object is of a specific type
pub fn isType(comptime T: type, obj: *cpython.PyObject) bool {
    return cpython.Py_TYPE(obj) == typeObject(T);
}

// ============================================================================
// CENTRALIZED EXTERN DECLARATIONS
// ============================================================================
// Instead of declaring extern fn in every file, import from here:
//   const externs = traits.externs;
//   _ = externs.PyDict_New();

pub const externs = struct {
    // Reference counting (prefer using traits.incref/decref instead)
    pub extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
    pub extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

    // Error handling
    pub extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;
    pub extern fn PyErr_Occurred() callconv(.c) ?*cpython.PyObject;
    pub extern fn PyErr_Clear() callconv(.c) void;

    // Dict operations
    pub extern fn PyDict_New() callconv(.c) ?*cpython.PyObject;
    pub extern fn PyDict_Copy(*cpython.PyObject) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyDict_SetItem(*cpython.PyObject, *cpython.PyObject, *cpython.PyObject) callconv(.c) c_int;
    pub extern fn PyDict_SetItemString(*cpython.PyObject, [*:0]const u8, *cpython.PyObject) callconv(.c) c_int;
    pub extern fn PyDict_GetItem(*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyDict_GetItemString(*cpython.PyObject, [*:0]const u8) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyDict_DelItem(*cpython.PyObject, *cpython.PyObject) callconv(.c) c_int;

    // Unicode operations
    pub extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyUnicode_FromStringAndSize([*]const u8, isize) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyUnicode_AsUTF8(*cpython.PyObject) callconv(.c) ?[*:0]const u8;

    // Integer operations
    pub extern fn PyLong_FromLong(c_long) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyLong_AsLong(*cpython.PyObject) callconv(.c) c_long;

    // Tuple operations
    pub extern fn PyTuple_New(isize) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyTuple_GetItem(*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyTuple_SetItem(*cpython.PyObject, isize, *cpython.PyObject) callconv(.c) c_int;
    pub extern fn PyTuple_Size(*cpython.PyObject) callconv(.c) isize;

    // List operations
    pub extern fn PyList_New(isize) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyList_GetItem(*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject;
    pub extern fn PyList_SetItem(*cpython.PyObject, isize, *cpython.PyObject) callconv(.c) c_int;
    pub extern fn PyList_Append(*cpython.PyObject, *cpython.PyObject) callconv(.c) c_int;

    // Memory operations
    pub extern fn PyMem_Malloc(usize) callconv(.c) ?*anyopaque;
    pub extern fn PyMem_Free(?*anyopaque) callconv(.c) void;
    pub extern fn PyObject_Malloc(usize) callconv(.c) ?*anyopaque;
    pub extern fn PyObject_Free(?*anyopaque) callconv(.c) void;

    // Module operations
    pub extern fn PyModule_Create2(*anyopaque, c_int) callconv(.c) ?*cpython.PyObject;

    // Function operations
    pub extern fn PyCFunction_NewEx(*const anyopaque, ?*cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject;
};

// ============================================================================
// TESTS
// ============================================================================

test "type checking" {
    const pylong = @import("pyobject_long.zig");

    const int_obj = pylong.PyLong_FromLong(42).?;
    defer decref(int_obj);

    try std.testing.expect(isInt(int_obj));
    try std.testing.expect(!isFloat(int_obj));
    try std.testing.expect(!isString(int_obj));
}

test "reference counting" {
    const pylong = @import("pyobject_long.zig");

    const obj = pylong.PyLong_FromLong(100).?;
    const initial_refcnt = obj.ob_refcnt;

    _ = incref(obj);
    try std.testing.expectEqual(initial_refcnt + 1, obj.ob_refcnt);

    decref(obj);
    try std.testing.expectEqual(initial_refcnt, obj.ob_refcnt);

    decref(obj); // Final decref
}

test "protocol dispatch" {
    const pytuple = @import("pyobject_tuple.zig");
    const pylong = @import("pyobject_long.zig");

    const tuple = pytuple.PyTuple_New(3).?;
    defer decref(tuple);

    // Set items
    _ = pytuple.PyTuple_SetItem(tuple, 0, incref(pylong.PyLong_FromLong(1).?));
    _ = pytuple.PyTuple_SetItem(tuple, 1, incref(pylong.PyLong_FromLong(2).?));
    _ = pytuple.PyTuple_SetItem(tuple, 2, incref(pylong.PyLong_FromLong(3).?));

    // Test length
    const len = getLength(tuple);
    try std.testing.expectEqual(@as(?isize, 3), len);

    // Test type check
    try std.testing.expect(isTuple(tuple));
    try std.testing.expect(isSequence(tuple));
}
