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

// Import type objects from their respective modules
const pylong = @import("pyobject_long.zig");
const pyfloat = @import("pyobject_float.zig");
const pylist = @import("pyobject_list.zig");
const pytuple = @import("pyobject_tuple.zig");
const pydict = @import("pyobject_dict.zig");
const pyunicode = @import("pyobject_unicode.zig");

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
    if (isFloat(obj)) {
        return pyfloat.PyFloat_AsDouble(obj);
    }

    if (isInt(obj)) {
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
    return pylist.PyList_New(size);
}

/// Create a new tuple with given size
pub fn createTuple(size: isize) ?*cpython.PyObject {
    return pytuple.PyTuple_New(size);
}

/// Create a new dict
pub fn createDict() ?*cpython.PyObject {
    return pydict.PyDict_New();
}

/// Create integer from i64
pub fn createInt(value: i64) ?*cpython.PyObject {
    return pylong.PyLong_FromLong(@intCast(value));
}

/// Create float from f64
pub fn createFloat(value: f64) ?*cpython.PyObject {
    return pyfloat.PyFloat_FromDouble(value);
}

/// Create string from slice
pub fn createString(data: []const u8) ?*cpython.PyObject {
    const cpython_unicode = @import("cpython_unicode.zig");
    return cpython_unicode.PyUnicode_FromStringAndSize(data.ptr, @intCast(data.len));
}

/// Create string from C string
pub fn createStringFromCStr(cstr: [*:0]const u8) ?*cpython.PyObject {
    const cpython_unicode = @import("cpython_unicode.zig");
    return cpython_unicode.PyUnicode_FromString(cstr);
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
// PURE ZIG IMPLEMENTATIONS (no extern - all implemented in Zig)
// ============================================================================
// These functions use the same memory layout as CPython but are pure Zig.
// Import via: const externs = traits.externs;

pub const externs = struct {
    // Reference counting
    pub fn Py_INCREF(op: *cpython.PyObject) void {
        op.ob_refcnt += 1;
    }

    pub fn Py_DECREF(op: *cpython.PyObject) void {
        op.ob_refcnt -= 1;
        // Note: actual deallocation would happen at refcnt == 0
        // For now we rely on Zig allocator for memory management
    }

    // Error handling (simplified - uses thread-local or global error state)
    var current_error: ?*cpython.PyObject = null;
    var current_error_msg: ?[*:0]const u8 = null;

    pub fn PyErr_SetString(exc_type: *cpython.PyObject, msg: [*:0]const u8) void {
        current_error = exc_type;
        current_error_msg = msg;
    }

    pub fn PyErr_Occurred() ?*cpython.PyObject {
        return current_error;
    }

    pub fn PyErr_Clear() void {
        current_error = null;
        current_error_msg = null;
    }

    // Integer operations - create PyLongObject
    pub fn PyLong_FromLong(val: c_long) ?*cpython.PyObject {
        return PyLong_FromLongLong(@intCast(val));
    }

    pub fn PyLong_FromLongLong(val: c_longlong) ?*cpython.PyObject {
        const obj = allocator.create(cpython.PyLongObject) catch return null;
        obj.* = cpython.PyLongObject{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = &pylong.PyLong_Type,
                },
                .ob_size = 1,
            },
            .ob_digit = .{@intCast(val)},
        };
        return @ptrCast(obj);
    }

    pub fn PyLong_AsLong(op: *cpython.PyObject) c_long {
        const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(op));
        return @intCast(long_obj.ob_digit[0]);
    }

    pub fn PyLong_AsLongLong(op: *cpython.PyObject) c_longlong {
        const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(op));
        return @intCast(long_obj.ob_digit[0]);
    }

    // Float operations - create PyFloatObject
    pub fn PyFloat_FromDouble(val: f64) ?*cpython.PyObject {
        const obj = allocator.create(cpython.PyFloatObject) catch return null;
        obj.* = cpython.PyFloatObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &pyfloat.PyFloat_Type,
            },
            .ob_fval = val,
        };
        return @ptrCast(obj);
    }

    pub fn PyFloat_AsDouble(op: *cpython.PyObject) f64 {
        const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(op));
        return float_obj.ob_fval;
    }

    // Singleton objects
    var _Py_NoneStruct: cpython.PyObject = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // Will be set on first use
    };
    var _Py_TrueStruct: cpython.PyLongObject = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 1 },
        .ob_digit = .{1},
    };
    var _Py_FalseStruct: cpython.PyLongObject = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
        .ob_digit = .{0},
    };

    pub fn Py_None() *cpython.PyObject {
        return &_Py_NoneStruct;
    }

    pub fn Py_True() *cpython.PyObject {
        return @ptrCast(&_Py_TrueStruct);
    }

    pub fn Py_False() *cpython.PyObject {
        return @ptrCast(&_Py_FalseStruct);
    }

    // Tuple operations
    pub fn PyTuple_New(size: isize) ?*cpython.PyObject {
        const usize_val: usize = @intCast(size);
        const items = allocator.alloc(*cpython.PyObject, usize_val) catch return null;
        const obj = allocator.create(cpython.PyTupleObject) catch {
            allocator.free(items);
            return null;
        };
        obj.* = cpython.PyTupleObject{
            .ob_base = .{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = &pytuple.PyTuple_Type },
                .ob_size = size,
            },
            .ob_item = items.ptr,
        };
        return @ptrCast(obj);
    }

    pub fn PyTuple_GetItem(op: *cpython.PyObject, idx: isize) ?*cpython.PyObject {
        const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(op));
        if (idx < 0 or idx >= tuple.ob_base.ob_size) return null;
        return tuple.ob_item[@intCast(idx)];
    }

    pub fn PyTuple_SetItem(op: *cpython.PyObject, idx: isize, value: *cpython.PyObject) c_int {
        const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(op));
        if (idx < 0 or idx >= tuple.ob_base.ob_size) return -1;
        tuple.ob_item[@intCast(idx)] = value;
        return 0;
    }

    pub fn PyTuple_Size(op: *cpython.PyObject) isize {
        const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(op));
        return tuple.ob_base.ob_size;
    }

    // List operations
    pub fn PyList_New(size: isize) ?*cpython.PyObject {
        const usize_val: usize = @intCast(size);
        const items = allocator.alloc(*cpython.PyObject, usize_val) catch return null;
        const obj = allocator.create(cpython.PyListObject) catch {
            allocator.free(items);
            return null;
        };
        obj.* = cpython.PyListObject{
            .ob_base = .{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = &pylist.PyList_Type },
                .ob_size = size,
            },
            .ob_item = items.ptr,
            .allocated = size,
        };
        return @ptrCast(obj);
    }

    pub fn PyList_GetItem(op: *cpython.PyObject, idx: isize) ?*cpython.PyObject {
        const list: *cpython.PyListObject = @ptrCast(@alignCast(op));
        if (idx < 0 or idx >= list.ob_base.ob_size) return null;
        return list.ob_item[@intCast(idx)];
    }

    pub fn PyList_SetItem(op: *cpython.PyObject, idx: isize, value: *cpython.PyObject) c_int {
        const list: *cpython.PyListObject = @ptrCast(@alignCast(op));
        if (idx < 0 or idx >= list.ob_base.ob_size) return -1;
        list.ob_item[@intCast(idx)] = value;
        return 0;
    }

    pub fn PyList_Append(op: *cpython.PyObject, value: *cpython.PyObject) c_int {
        const list: *cpython.PyListObject = @ptrCast(@alignCast(op));
        const new_size = list.ob_base.ob_size + 1;
        if (new_size > list.allocated) {
            // Need to grow - double capacity
            const new_cap = @max(list.allocated * 2, 8);
            const old_slice = list.ob_item[0..@intCast(list.ob_base.ob_size)];
            const new_items = allocator.alloc(*cpython.PyObject, @intCast(new_cap)) catch return -1;
            @memcpy(new_items[0..old_slice.len], old_slice);
            if (list.allocated > 0) {
                allocator.free(list.ob_item[0..@intCast(list.allocated)]);
            }
            list.ob_item = new_items.ptr;
            list.allocated = @intCast(new_cap);
        }
        list.ob_item[@intCast(list.ob_base.ob_size)] = value;
        list.ob_base.ob_size = new_size;
        return 0;
    }

    // Unicode operations - use existing pyunicode module
    pub fn PyUnicode_FromString(str: [*:0]const u8) ?*cpython.PyObject {
        return pyunicode.createFromCString(str);
    }

    pub fn PyUnicode_FromStringAndSize(str: [*]const u8, len: isize) ?*cpython.PyObject {
        return pyunicode.createFromSlice(str[0..@intCast(len)]);
    }

    pub fn PyUnicode_AsUTF8(op: *cpython.PyObject) ?[*:0]const u8 {
        return pyunicode.asUTF8(op);
    }

    // Dict operations - use existing pydict module
    pub fn PyDict_New() ?*cpython.PyObject {
        return pydict.create(allocator);
    }

    // Dict operations - delegate to pyobject_dict.zig
    pub fn PyDict_Copy(obj: *cpython.PyObject) ?*cpython.PyObject {
        return pydict.PyDict_Copy(obj);
    }

    pub fn PyDict_SetItem(dict: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) c_int {
        return pydict.PyDict_SetItem(dict, key, value);
    }

    pub fn PyDict_SetItemString(dict: *cpython.PyObject, key: [*:0]const u8, value: *cpython.PyObject) c_int {
        return pydict.PyDict_SetItemString(dict, key, value);
    }

    pub fn PyDict_GetItem(dict: *cpython.PyObject, key: *cpython.PyObject) ?*cpython.PyObject {
        return pydict.PyDict_GetItem(dict, key);
    }

    pub fn PyDict_GetItemString(dict: *cpython.PyObject, key: [*:0]const u8) ?*cpython.PyObject {
        return pydict.PyDict_GetItemString(dict, key);
    }

    pub fn PyDict_DelItem(dict: *cpython.PyObject, key: *cpython.PyObject) c_int {
        return pydict.PyDict_DelItem(dict, key);
    }

    // Object attribute operations - use type's tp_getattro/tp_setattro slots
    pub fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) ?*cpython.PyObject {
        const type_obj = cpython.Py_TYPE(obj);

        // Try tp_getattro first (takes PyObject* name)
        if (type_obj.tp_getattro) |getattro| {
            const name_obj = PyUnicode_FromString(name) orelse return null;
            defer Py_DECREF(name_obj);
            return getattro(obj, name_obj);
        }

        // Fall back to tp_getattr (takes C string)
        if (type_obj.tp_getattr) |getattr| {
            // tp_getattr expects non-const, but we won't modify it
            return getattr(obj, @constCast(name));
        }

        return null;
    }

    pub fn PyObject_SetAttrString(obj: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) c_int {
        const type_obj = cpython.Py_TYPE(obj);

        // Try tp_setattro first
        if (type_obj.tp_setattro) |setattro| {
            const name_obj = PyUnicode_FromString(name) orelse return -1;
            defer Py_DECREF(name_obj);
            return setattro(obj, name_obj, value);
        }

        // Fall back to tp_setattr
        if (type_obj.tp_setattr) |setattr| {
            return setattr(obj, @constCast(name), value);
        }

        return -1;
    }

    pub fn PyObject_CallObject(callable: *cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
        const type_obj = cpython.Py_TYPE(callable);

        // Use tp_call slot
        if (type_obj.tp_call) |call_fn| {
            // args can be null (no args) - pass empty tuple
            const args_tuple = args orelse PyTuple_New(0) orelse return null;
            defer if (args == null) Py_DECREF(args_tuple);
            return call_fn(callable, args_tuple, null);
        }

        return null;
    }

    pub fn PyObject_Call(callable: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) ?*cpython.PyObject {
        const type_obj = cpython.Py_TYPE(callable);

        // Use tp_call slot
        if (type_obj.tp_call) |call_fn| {
            return call_fn(callable, args, kwargs);
        }

        return null;
    }

    // Memory operations
    pub fn PyMem_Malloc(size: usize) ?*anyopaque {
        const mem = allocator.alloc(u8, size) catch return null;
        return mem.ptr;
    }

    pub fn PyMem_Free(ptr: ?*anyopaque) void {
        _ = ptr; // Can't free without size info in Zig allocator
    }

    pub fn PyObject_Malloc(size: usize) ?*anyopaque {
        return PyMem_Malloc(size);
    }

    pub fn PyObject_Free(ptr: ?*anyopaque) void {
        PyMem_Free(ptr);
    }

    // Module operations - delegate to cpython_module.zig
    pub fn PyModule_Create2(def: *cpython.PyModuleDef, api_version: c_int) ?*cpython.PyObject {
        const module_mod = @import("cpython_module.zig");
        return module_mod.PyModule_Create2(def, api_version);
    }

    // Function operations - delegate to pyobject_method.zig
    pub fn PyCFunction_NewEx(meth: *const cpython.PyMethodDef, self: ?*cpython.PyObject, module: ?*cpython.PyObject) ?*cpython.PyObject {
        const pymethod = @import("pyobject_method.zig");
        return pymethod.PyCFunction_NewEx(meth, self, module);
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "type checking" {
    const int_obj = pylong.PyLong_FromLong(42).?;
    defer decref(int_obj);

    try std.testing.expect(isInt(int_obj));
    try std.testing.expect(!isFloat(int_obj));
    try std.testing.expect(!isString(int_obj));
}

test "reference counting" {
    const obj = pylong.PyLong_FromLong(100).?;
    const initial_refcnt = obj.ob_refcnt;

    _ = incref(obj);
    try std.testing.expectEqual(initial_refcnt + 1, obj.ob_refcnt);

    decref(obj);
    try std.testing.expectEqual(initial_refcnt, obj.ob_refcnt);

    decref(obj); // Final decref
}

test "protocol dispatch" {
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
