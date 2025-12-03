/// metal0 Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const pyint = @import("pyint.zig");
const pyfloat = @import("pyfloat.zig");
const pybool = @import("pybool.zig");
const pylist = @import("pylist.zig");
pub const pystring = @import("pystring.zig");
const pytuple = @import("pytuple.zig");
const pyfile = @import("pyfile.zig");

/// BigInt for arbitrary precision integers (Python int semantics)
pub const bigint = @import("bigint");
pub const BigInt = bigint.BigInt;

/// Export string utilities for native codegen
pub const string_utils = @import("string_utils.zig");

/// Export _string module (formatter_parser, etc.)
pub const _string = @import("_string.zig");

/// Export AST executor for eval() support
pub const ast_executor = @import("ast_executor.zig");

/// Export calendar module
pub const calendar = @import("calendar.zig");

/// Export ctypes FFI module
pub const ctypes = @import("ctypes.zig");

/// Export typing module types
pub const typing = @import("typing.zig");

/// Export dynamic attribute access stubs
const dynamic_attrs = @import("dynamic_attrs.zig");

/// Export PyValue for dynamic attributes
pub const PyValue = @import("py_value.zig").PyValue;

/// Export comptime type inference helpers
const comptime_helpers = @import("comptime_helpers.zig");
pub const InferListType = comptime_helpers.InferListType;
pub const createListComptime = comptime_helpers.createListComptime;
pub const InferDictValueType = comptime_helpers.InferDictValueType;

/// Export comptime closure helpers
pub const closure_impl = @import("closure_impl.zig");
pub const Closure0 = closure_impl.Closure0;
pub const Closure1 = closure_impl.Closure1;
pub const Closure2 = closure_impl.Closure2;
pub const Closure3 = closure_impl.Closure3;
pub const ZeroClosure = closure_impl.ZeroClosure;
pub const AnyClosure0 = closure_impl.AnyClosure0;
pub const AnyClosure1 = closure_impl.AnyClosure1;
pub const AnyClosure2 = closure_impl.AnyClosure2;
pub const AnyClosure3 = closure_impl.AnyClosure3;

/// Export TypeFactory for first-class types (classes as values)
pub const type_factory = @import("type_factory.zig");
pub const TypeFactory = type_factory.TypeFactory;
pub const AnyTypeFactory = type_factory.AnyTypeFactory;

/// Export format utilities from runtime_format.zig
const runtime_format = @import("runtime_format.zig");
pub const formatAny = runtime_format.formatAny;
pub const formatUnknown = runtime_format.formatUnknown;
pub const formatFloat = runtime_format.formatFloat;
pub const formatPyObject = runtime_format.formatPyObject;
pub const PyDict_AsString = runtime_format.PyDict_AsString;
pub const printValue = runtime_format.printValue;
pub const pyFormat = runtime_format.pyFormat;
pub const pyMod = runtime_format.pyMod;

/// Export exception types from runtime/exceptions.zig
pub const exceptions = @import("runtime/exceptions.zig");
pub const PythonError = exceptions.PythonError;
pub const ExceptionTypeId = exceptions.ExceptionTypeId;
pub const TypeError = exceptions.TypeError;
pub const ValueError = exceptions.ValueError;
pub const KeyError = exceptions.KeyError;
pub const IndexError = exceptions.IndexError;
pub const ZeroDivisionError = exceptions.ZeroDivisionError;
pub const AttributeError = exceptions.AttributeError;
pub const NameError = exceptions.NameError;
pub const FileNotFoundError = exceptions.FileNotFoundError;
pub const IOError = exceptions.IOError;
pub const RuntimeError = exceptions.RuntimeError;
pub const StopIteration = exceptions.StopIteration;
pub const NotImplementedError = exceptions.NotImplementedError;
pub const AssertionError = exceptions.AssertionError;
pub const OverflowError = exceptions.OverflowError;
pub const ImportError = exceptions.ImportError;
pub const ModuleNotFoundError = exceptions.ModuleNotFoundError;
pub const OSError = exceptions.OSError;
pub const PermissionError = exceptions.PermissionError;
pub const TimeoutError = exceptions.TimeoutError;
pub const ConnectionError = exceptions.ConnectionError;
pub const RecursionError = exceptions.RecursionError;
pub const MemoryError = exceptions.MemoryError;
pub const LookupError = exceptions.LookupError;
pub const ArithmeticError = exceptions.ArithmeticError;
pub const BufferError = exceptions.BufferError;
pub const EOFError = exceptions.EOFError;
pub const GeneratorExit = exceptions.GeneratorExit;
pub const SystemExit = exceptions.SystemExit;
pub const KeyboardInterrupt = exceptions.KeyboardInterrupt;
pub const BaseException = exceptions.BaseException;
pub const Exception = exceptions.Exception;
pub const SyntaxError = exceptions.SyntaxError;
pub const UnicodeError = exceptions.UnicodeError;
pub const UnicodeDecodeError = exceptions.UnicodeDecodeError;
pub const UnicodeEncodeError = exceptions.UnicodeEncodeError;

/// Python's NotImplemented singleton - used by binary operations to signal
/// that the operation is not supported for the given types.
/// In Python: return NotImplemented tells the interpreter to try the reflected method.
/// In metal0: we use a sentinel struct that evaluates to false in boolean contexts.
pub const NotImplementedType = struct {
    _marker: u8 = 0,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = self;
        _ = fmt;
        _ = options;
        try writer.writeAll("NotImplemented");
    }
};
pub const NotImplemented: NotImplementedType = .{};

/// Comptime type check for Python type names
/// Used for comptime branching in type-checking patterns with anytype params
/// Example: if (comptime !runtime.istype(@TypeOf(x), "int")) return error.TypeError;
pub fn istype(comptime T: type, comptime type_name: []const u8) bool {
    const info = @typeInfo(T);

    if (comptime std.mem.eql(u8, type_name, "int")) {
        return info == .int or info == .comptime_int or T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "float")) {
        return info == .float or info == .comptime_float;
    } else if (comptime std.mem.eql(u8, type_name, "bool")) {
        return T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "str")) {
        if (T == []const u8 or T == []u8) return true;
        // String literals: *const [N:0]u8
        if (info == .pointer and info.pointer.size == .one) {
            const child_info = @typeInfo(info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) {
                return true;
            }
        }
        return false;
    } else {
        // Unknown type - check for struct with matching name
        if (info == .@"struct") {
            if (@hasDecl(T, "__class_name__")) {
                return std.mem.eql(u8, T.__class_name__, type_name);
            }
        }
        return false;
    }
}

/// Discard a value (consume it to prevent unused variable errors)
/// This is a no-op function that accepts any value
pub inline fn discard(_: anytype) void {}

/// Generic bool conversion for Python truthiness semantics
/// Returns false for: 0, 0.0, false, empty strings, empty slices
/// Returns true for everything else
pub fn toBool(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle integers
    if (info == .int or info == .comptime_int) {
        return value != 0;
    }

    // Handle floats
    if (info == .float or info == .comptime_float) {
        return value != 0.0;
    }

    // Handle bool
    if (T == bool) {
        return value;
    }

    // Handle slices (including strings)
    if (info == .pointer and info.pointer.size == .slice) {
        return value.len > 0;
    }

    // Handle single-item pointers to arrays (string literals)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return child_info.array.len > 0;
        }
        // Handle pointers to structs with __bool__ method (Python objects)
        if (child_info == .@"struct") {
            const ChildT = info.pointer.child;
            if (@hasDecl(ChildT, "__bool__")) {
                // Check if __bool__ takes a mutable pointer (self-mutating method)
                const bool_fn_info = @typeInfo(@TypeOf(ChildT.__bool__));
                const first_param_type = bool_fn_info.@"fn".params[0].type.?;
                const first_param_info = @typeInfo(first_param_type);

                const result = blk: {
                    if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                        // __bool__ takes *@This() (mutable) - value is already a pointer
                        if (info.pointer.is_const) {
                            // Cast away const if needed
                            break :blk @constCast(value).__bool__();
                        } else {
                            break :blk value.__bool__();
                        }
                    } else {
                        // __bool__ takes *const @This() or value - call directly
                        break :blk value.__bool__();
                    }
                };
                const ResultT = @TypeOf(result);
                if (@typeInfo(ResultT) == .bool) {
                    return result;
                }
                // Handle error union wrapping bool
                if (@typeInfo(ResultT) == .error_union) {
                    const unwrapped = result catch return false;
                    const UnwrappedT = @TypeOf(unwrapped);
                    if (@typeInfo(UnwrappedT) == .bool) {
                        return unwrapped;
                    }
                    @panic("TypeError: __bool__ should return bool, not error union with non-bool");
                }
                @panic("TypeError: __bool__ should return bool");
            }
            // Check for __len__ as fallback (containers with 0 length are falsy)
            if (@hasDecl(ChildT, "__len__")) {
                const len = value.__len__() catch return false;
                return len > 0;
            }
        }
    }

    // Handle PyString
    if (T == PyString) {
        return value.len() > 0;
    }

    // Handle PyInt
    if (T == PyInt) {
        return value.value != 0;
    }

    // Handle PyBool
    if (T == PyBool) {
        return value.value;
    }

    // Handle optional
    if (info == .optional) {
        return value != null;
    }

    // Handle structs with __bool__ method (Python protocol)
    if (info == .@"struct") {
        if (@hasDecl(T, "__bool__")) {
            // Check if __bool__ takes a mutable pointer (self-mutating method)
            const bool_fn_info = @typeInfo(@TypeOf(T.__bool__));
            const first_param_type = bool_fn_info.@"fn".params[0].type.?;
            const first_param_info = @typeInfo(first_param_type);

            const result = blk: {
                if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                    // __bool__ takes *@This() (mutable) - need to cast away const
                    // This matches Python's pass-by-reference semantics where
                    // objects can be mutated through any reference
                    var mutable = @constCast(&value);
                    break :blk mutable.__bool__();
                } else {
                    // __bool__ takes *const @This() or value - call directly
                    break :blk value.__bool__();
                }
            };
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .bool) {
                return result;
            }
            // Handle error union wrapping bool
            if (@typeInfo(ResultT) == .error_union) {
                const unwrapped = result catch return false;
                const UnwrappedT = @TypeOf(unwrapped);
                if (@typeInfo(UnwrappedT) == .bool) {
                    return unwrapped;
                }
                // __bool__ returned error union with non-bool payload
                @panic("TypeError: __bool__ should return bool, not error union with non-bool");
            }
            // Python 3: __bool__ MUST return bool (True or False)
            // Returning anything else (including int 0/1) is a TypeError
            @panic("TypeError: __bool__ should return bool");
        }
        // Check for __len__ as fallback (containers with 0 length are falsy)
        if (@hasDecl(T, "__len__")) {
            const len = value.__len__() catch return false;
            return len > 0;
        }
    }

    // Default: truthy for everything else (non-empty types)
    return true;
}

/// Validate that __bool__ returns bool (Python 3 requirement)
/// Returns error.TypeError if value is not bool
pub fn validateBoolReturn(value: anytype) PythonError!bool {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .bool) {
        return value;
    }
    // Python 3: __bool__ MUST return bool (True or False)
    return PythonError.TypeError;
}

/// Generic int conversion for __len__, __hash__, etc.
/// Handles both native int types and PyValue
/// Returns error for non-convertible types (e.g., string for __len__)
pub fn pyToInt(value: anytype) PythonError!i64 {
    const T = @TypeOf(value);
    if (T == PyValue) {
        // Extract int from PyValue, return error on non-convertible types
        return value.toInt() orelse return PythonError.TypeError;
    } else if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize or T == comptime_int) {
        return @intCast(value);
    } else if (T == bool) {
        return if (value) 1 else 0;
    } else if (@typeInfo(T) == .optional) {
        if (value) |v| return try pyToInt(v);
        return 0;
    } else {
        // Return error for unsupported types at runtime
        return PythonError.TypeError;
    }
}

/// Generic int conversion for Python int() semantics
/// Handles: integers (pass through), strings (parse), bools, floats
// =============================================================================
// CPython-Compatible PyObject Layout
// =============================================================================
// These structures use `extern struct` for C ABI compatibility.
// Field order and sizes MUST match CPython exactly for C extension compatibility.
// Reference: https://github.com/python/cpython/blob/main/Include/object.h
// =============================================================================

/// Py_ssize_t equivalent - signed size type matching C's ssize_t
pub const Py_ssize_t = isize;

/// PyObject - Base object header (CPython compatible)
/// Layout: ob_refcnt (8 bytes) + ob_type (8 bytes) = 16 bytes
pub const PyObject = extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: *PyTypeObject,

    /// Value type for initializing lists/tuples from literals (backwards compat)
    pub const Value = struct {
        int: i64,
    };
};

/// PyVarObject - Variable-size object header (CPython compatible)
/// Used for list, tuple, string, etc.
pub const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: Py_ssize_t,
};

/// Type object flags (subset of CPython's Py_TPFLAGS_*)
pub const Py_TPFLAGS = struct {
    pub const HEAPTYPE: u64 = 1 << 9;
    pub const BASETYPE: u64 = 1 << 10;
    pub const HAVE_GC: u64 = 1 << 14;
    pub const DEFAULT: u64 = 0;
};

/// PyTypeObject - Type descriptor (simplified CPython compatible)
/// Full CPython PyTypeObject has ~50 fields; we implement the critical ones
pub const PyTypeObject = extern struct {
    ob_base: PyVarObject,
    tp_name: [*:0]const u8,
    tp_basicsize: Py_ssize_t,
    tp_itemsize: Py_ssize_t,
    // Destructor
    tp_dealloc: ?*const fn (*PyObject) callconv(.c) void,
    // Placeholder for vectorcall_offset
    tp_vectorcall_offset: Py_ssize_t,
    // Reserved slots (for getattr, setattr, etc.)
    tp_getattr: ?*anyopaque,
    tp_setattr: ?*anyopaque,
    tp_as_async: ?*anyopaque,
    tp_repr: ?*const fn (*PyObject) callconv(.c) *PyObject,
    // Number/sequence/mapping protocols
    tp_as_number: ?*anyopaque,
    tp_as_sequence: ?*anyopaque,
    tp_as_mapping: ?*anyopaque,
    tp_hash: ?*const fn (*PyObject) callconv(.c) Py_ssize_t,
    tp_call: ?*anyopaque,
    tp_str: ?*const fn (*PyObject) callconv(.c) *PyObject,
    tp_getattro: ?*anyopaque,
    tp_setattro: ?*anyopaque,
    tp_as_buffer: ?*anyopaque,
    tp_flags: u64,
    tp_doc: ?[*:0]const u8,
    // Traversal and clear for GC
    tp_traverse: ?*anyopaque,
    tp_clear: ?*anyopaque,
    tp_richcompare: ?*anyopaque,
    tp_weaklistoffset: Py_ssize_t,
    tp_iter: ?*anyopaque,
    tp_iternext: ?*anyopaque,
    tp_methods: ?*anyopaque,
    tp_members: ?*anyopaque,
    tp_getset: ?*anyopaque,
    tp_base: ?*PyTypeObject,
    tp_dict: ?*PyObject,
    tp_descr_get: ?*anyopaque,
    tp_descr_set: ?*anyopaque,
    tp_dictoffset: Py_ssize_t,
    tp_init: ?*anyopaque,
    tp_alloc: ?*anyopaque,
    tp_new: ?*anyopaque,
    tp_free: ?*anyopaque,
    tp_is_gc: ?*anyopaque,
    tp_bases: ?*PyObject,
    tp_mro: ?*PyObject,
    tp_cache: ?*PyObject,
    tp_subclasses: ?*anyopaque,
    tp_weaklist: ?*PyObject,
    tp_del: ?*anyopaque,
    tp_version_tag: u32,
    tp_finalize: ?*anyopaque,
    tp_vectorcall: ?*anyopaque,
};

// =============================================================================
// Concrete Python Type Objects (CPython ABI compatible)
// =============================================================================

/// PyLongObject - Python integer (CPython compatible)
/// CPython uses variable-length digit array; we use fixed i64 for simplicity
/// Note: For full bigint support, may need variable-length digits later
pub const PyLongObject = extern struct {
    ob_base: PyVarObject,
    // In CPython this is a variable-length digit array
    // We simplify to a single i64 for now (covers most use cases)
    ob_digit: i64,
};

/// PyFloatObject - Python float (CPython compatible)
pub const PyFloatObject = extern struct {
    ob_base: PyObject,
    ob_fval: f64,
};

/// PyComplexObject - Python complex number (CPython compatible)
pub const PyComplexObject = extern struct {
    ob_base: PyObject,
    cval_real: f64,
    cval_imag: f64,
};

/// PyBoolObject - Python bool (same layout as PyLongObject in CPython)
pub const PyBoolObject = extern struct {
    ob_base: PyVarObject,
    ob_digit: i64, // 0 for False, 1 for True
};

/// PyBigIntObject - Python int for arbitrary precision (when > i64 range)
/// Used by bytecode VM for eval() with large integers
pub const PyBigIntObject = struct {
    ob_base: PyVarObject,
    value: BigInt, // Heap-allocated arbitrary precision integer
};

/// PyListObject - Python list (CPython compatible)
pub const PyListObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Array of PyObject pointers
    allocated: Py_ssize_t, // Allocated capacity
};

/// PyTupleObject - Python tuple (CPython compatible)
pub const PyTupleObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Inline array of PyObject pointers
};

/// PyDictObject - Python dict (simplified, not full CPython layout)
/// CPython's dict is complex with compact dict + indices; we use simpler layout
pub const PyDictObject = extern struct {
    ob_base: PyObject,
    ma_used: Py_ssize_t, // Number of items
    // Internal hash map storage (not CPython compatible, but functional)
    ma_keys: ?*anyopaque, // Pointer to our hashmap
    ma_values: ?*anyopaque, // Reserved for split-table dict
};

/// PyBytesObject - Python bytes (CPython compatible)
pub const PyBytesObject = extern struct {
    ob_base: PyVarObject,
    ob_shash: Py_ssize_t, // Cached hash (-1 if not computed)
    ob_sval: [1]u8, // Variable-length byte array (at least 1 byte)
};

/// PyUnicodeObject - Python string (simplified)
/// Full CPython Unicode is very complex (compact/legacy/etc.)
/// We use a simplified UTF-8 representation
pub const PyUnicodeObject = extern struct {
    ob_base: PyObject,
    length: Py_ssize_t, // Number of code points
    hash: Py_ssize_t, // Cached hash (-1 if not computed)
    // State flags (interned, kind, compact, ascii, ready)
    state: u32,
    _padding: u32, // Alignment padding
    // UTF-8 data pointer (simplified from CPython's complex union)
    data: [*]const u8,
};

/// PyNoneStruct - The None singleton
pub const PyNoneStruct = extern struct {
    ob_base: PyObject,
};

/// PyFileObject - File handle (metal0 specific, not CPython compatible)
pub const PyFileObject = extern struct {
    ob_base: PyObject,
    // File-specific fields (not matching CPython's io module)
    fd: i32,
    mode: u32,
    name: ?[*:0]const u8,
};

// =============================================================================
// Global Type Objects (singletons)
// =============================================================================

/// Forward declaration for type object initialization
fn nullDealloc(_: *PyObject) callconv(.c) void {}

/// Base type object template
fn makeTypeObject(comptime name: [*:0]const u8, comptime basicsize: Py_ssize_t, comptime itemsize: Py_ssize_t) PyTypeObject {
    return PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1, // Immortal
                .ob_type = undefined, // Will be set to &PyType_Type
            },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = basicsize,
        .tp_itemsize = itemsize,
        .tp_dealloc = nullDealloc,
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
        .tp_flags = Py_TPFLAGS.DEFAULT,
        .tp_doc = null,
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
    };
}

// Type object singletons
pub var PyLong_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyLongObject), 0);
pub var PyFloat_Type: PyTypeObject = makeTypeObject("float", @sizeOf(PyFloatObject), 0);
pub var PyComplex_Type: PyTypeObject = makeTypeObject("complex", @sizeOf(PyComplexObject), 0);
pub var PyBool_Type: PyTypeObject = makeTypeObject("bool", @sizeOf(PyBoolObject), 0);
pub var PyList_Type: PyTypeObject = makeTypeObject("list", @sizeOf(PyListObject), @sizeOf(*PyObject));
pub var PyTuple_Type: PyTypeObject = makeTypeObject("tuple", @sizeOf(PyTupleObject), @sizeOf(*PyObject));
pub var PyDict_Type: PyTypeObject = makeTypeObject("dict", @sizeOf(PyDictObject), 0);
pub var PyUnicode_Type: PyTypeObject = makeTypeObject("str", @sizeOf(PyUnicodeObject), 0);
pub var PyBytes_Type: PyTypeObject = makeTypeObject("bytes", @sizeOf(PyBytesObject), 1);
pub var PyNone_Type: PyTypeObject = makeTypeObject("NoneType", @sizeOf(PyNoneStruct), 0);
pub var PyType_Type: PyTypeObject = makeTypeObject("type", @sizeOf(PyTypeObject), 0);
pub var PyFile_Type: PyTypeObject = makeTypeObject("file", @sizeOf(PyFileObject), 0);
pub var PyBigInt_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyBigIntObject), 0);

// None singleton
pub var _Py_NoneStruct: PyNoneStruct = .{
    .ob_base = .{
        .ob_refcnt = 1, // Immortal
        .ob_type = &PyNone_Type,
    },
};
pub const Py_None: *PyObject = @ptrCast(&_Py_NoneStruct);

// =============================================================================
// CPython-compatible Reference Counting Macros
// =============================================================================

pub inline fn Py_INCREF(op: *PyObject) void {
    op.ob_refcnt += 1;
}

pub inline fn Py_DECREF(op: *PyObject) void {
    op.ob_refcnt -= 1;
    if (op.ob_refcnt == 0) {
        if (op.ob_type.tp_dealloc) |dealloc| {
            dealloc(op);
        }
    }
}

pub inline fn Py_XINCREF(op: ?*PyObject) void {
    if (op) |o| Py_INCREF(o);
}

pub inline fn Py_XDECREF(op: ?*PyObject) void {
    if (op) |o| Py_DECREF(o);
}

/// Type checking macros
pub inline fn Py_TYPE(op: *PyObject) *PyTypeObject {
    return op.ob_type;
}

pub inline fn Py_IS_TYPE(op: *PyObject, typ: *PyTypeObject) bool {
    return Py_TYPE(op) == typ;
}

pub inline fn PyLong_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyLong_Type);
}

pub inline fn PyFloat_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyFloat_Type);
}

pub inline fn PyComplex_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyComplex_Type);
}

pub inline fn PyBool_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBool_Type);
}

pub inline fn PyList_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyList_Type);
}

pub inline fn PyTuple_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyTuple_Type);
}

pub inline fn PyDict_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyDict_Type);
}

pub inline fn PyUnicode_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyUnicode_Type);
}

pub inline fn PyBytes_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBytes_Type);
}

pub inline fn PyBigInt_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBigInt_Type);
}

/// Get ob_size from PyVarObject
pub inline fn Py_SIZE(op: *PyObject) Py_ssize_t {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    return var_obj.ob_size;
}

/// Set ob_size on PyVarObject
pub inline fn Py_SET_SIZE(op: *PyObject, size: Py_ssize_t) void {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    var_obj.ob_size = size;
}

/// Extract value from PyObject for comparisons
/// Returns f64 for numeric types (allows uniform comparison)
pub fn pyObjectToValue(obj: *PyObject) f64 {
    if (PyFloat_Check(obj)) {
        const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
        return float_obj.ob_fval;
    }
    if (PyLong_Check(obj)) {
        const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
        return @floatFromInt(long_obj.ob_digit);
    }
    if (PyBool_Check(obj)) {
        const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
        return @floatFromInt(bool_obj.ob_digit);
    }
    // Default to 0 for non-numeric types
    return 0.0;
}

/// Convert PyObject to string representation (like Python's str())
pub fn pyObjToStr(allocator: std.mem.Allocator, obj: *PyObject) ![]const u8 {
    if (PyLong_Check(obj)) {
        const val = PyInt.getValue(obj);
        return std.fmt.allocPrint(allocator, "{d}", .{val});
    }
    if (PyFloat_Check(obj)) {
        const val = PyFloat.getValue(obj);
        return std.fmt.allocPrint(allocator, "{d}", .{val});
    }
    if (PyBool_Check(obj)) {
        const val = PyBool.getValue(obj);
        return if (val) "True" else "False";
    }
    if (PyUnicode_Check(obj)) {
        return PyString.getValue(obj);
    }
    // Fallback for other types
    return std.fmt.allocPrint(allocator, "<PyObject@{*}>", .{obj});
}

// =============================================================================
// Backwards Compatibility - Legacy TypeId enum
// =============================================================================
// This provides a bridge for existing code that uses the old type_id system

pub const TypeId = enum {
    int,
    float,
    bool,
    string,
    list,
    tuple,
    dict,
    none,
    file,
    regex,
    bytes,
    bigint,

    /// Convert PyObject to legacy TypeId
    pub fn fromPyObject(obj: *PyObject) TypeId {
        if (Py_IS_TYPE(obj, &PyLong_Type)) return .int;
        if (Py_IS_TYPE(obj, &PyFloat_Type)) return .float;
        if (Py_IS_TYPE(obj, &PyBool_Type)) return .bool;
        if (Py_IS_TYPE(obj, &PyUnicode_Type)) return .string;
        if (Py_IS_TYPE(obj, &PyList_Type)) return .list;
        if (Py_IS_TYPE(obj, &PyTuple_Type)) return .tuple;
        if (Py_IS_TYPE(obj, &PyDict_Type)) return .dict;
        if (Py_IS_TYPE(obj, &PyNone_Type)) return .none;
        if (Py_IS_TYPE(obj, &PyBytes_Type)) return .bytes;
        if (Py_IS_TYPE(obj, &PyBigInt_Type)) return .bigint;
        return .none; // Default fallback
    }
};

/// Legacy type_id accessor for backwards compatibility
pub fn getTypeId(obj: *PyObject) TypeId {
    return TypeId.fromPyObject(obj);
}

// =============================================================================
// Legacy Reference Counting (bridges to new CPython-compatible functions)
// =============================================================================

/// Legacy incref - bridges to Py_INCREF
pub fn incref(obj: *PyObject) void {
    Py_INCREF(obj);
}

/// Legacy decref with allocator - uses new type-based deallocation
pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    if (obj.ob_refcnt <= 0) {
        std.debug.print("WARNING: Attempting to decref object with ref_count already 0\n", .{});
        return;
    }
    obj.ob_refcnt -= 1;
    if (obj.ob_refcnt == 0) {
        // Use type-based deallocation
        const type_id = getTypeId(obj);
        switch (type_id) {
            .int => {
                // PyLongObject is self-contained, just free it
                const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
                allocator.destroy(long_obj);
            },
            .float => {
                const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
                allocator.destroy(float_obj);
            },
            .bool => {
                const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
                allocator.destroy(bool_obj);
            },
            .list => {
                const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
                const size: usize = @intCast(list_obj.ob_base.ob_size);
                // Decref all items
                for (0..size) |i| {
                    decref(list_obj.ob_item[i], allocator);
                }
                // Free the item array
                if (list_obj.allocated > 0) {
                    const alloc_size: usize = @intCast(list_obj.allocated);
                    allocator.free(list_obj.ob_item[0..alloc_size]);
                }
                allocator.destroy(list_obj);
            },
            .tuple => {
                const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
                const size: usize = @intCast(tuple_obj.ob_base.ob_size);
                // Decref all items
                for (0..size) |i| {
                    decref(tuple_obj.ob_item[i], allocator);
                }
                // Free the tuple (items are inline in CPython, but we allocate separately)
                allocator.free(tuple_obj.ob_item[0..size]);
                allocator.destroy(tuple_obj);
            },
            .string => {
                const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
                // Free the string data if owned
                const len: usize = @intCast(str_obj.length);
                if (len > 0) {
                    allocator.free(str_obj.data[0..len]);
                }
                allocator.destroy(str_obj);
            },
            .dict => {
                const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
                // Free internal hashmap if present
                if (dict_obj.ma_keys) |keys_ptr| {
                    const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
                    var it = map.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        decref(entry.value_ptr.*, allocator);
                    }
                    map.deinit();
                    allocator.destroy(map);
                }
                allocator.destroy(dict_obj);
            },
            .none => {
                // Never free the None singleton
            },
            else => {
                // Generic deallocation for unknown types
                // Just free the base PyObject
            },
        }
    }
}

/// Check if a PyObject is truthy (Python truthiness semantics)
/// Returns false for: None, False, 0, empty string, empty list/dict
/// Returns true for everything else
pub fn pyTruthy(obj: *PyObject) bool {
    const type_id = getTypeId(obj);
    switch (type_id) {
        .none => return false,
        .bool => {
            const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
            return bool_obj.ob_digit != 0;
        },
        .int => {
            const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
            return long_obj.ob_digit != 0;
        },
        .float => {
            const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
            return float_obj.ob_fval != 0.0;
        },
        .string => {
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
            return str_obj.length > 0;
        },
        .list => {
            const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
            return list_obj.ob_base.ob_size > 0;
        },
        .dict => {
            const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
            return dict_obj.ma_used > 0;
        },
        .tuple => {
            const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
            return tuple_obj.ob_base.ob_size > 0;
        },
        else => return true, // All other types (file, regex, etc.) are truthy
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    printPyObjectImpl(obj, false);
}

/// Internal: print PyObject with quote_strings flag for container elements
fn printPyObjectImpl(obj: *PyObject, quote_strings: bool) void {
    const type_id = getTypeId(obj);
    switch (type_id) {
        .int => {
            const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
            std.debug.print("{}", .{long_obj.ob_digit});
        },
        .float => {
            const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
            std.debug.print("{d}", .{float_obj.ob_fval});
        },
        .bool => {
            const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
            std.debug.print("{s}", .{if (bool_obj.ob_digit != 0) "True" else "False"});
        },
        .string => {
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
            const len: usize = @intCast(str_obj.length);
            if (quote_strings) {
                std.debug.print("'{s}'", .{str_obj.data[0..len]});
            } else {
                std.debug.print("{s}", .{str_obj.data[0..len]});
            }
        },
        .none => {
            std.debug.print("None", .{});
        },
        .list => {
            printList(obj);
        },
        .tuple => {
            PyTuple.print(obj);
        },
        .dict => {
            printDict(obj);
        },
        else => {
            // For other types (file, regex), print the pointer
            std.debug.print("{*}", .{obj});
        },
    }
}

/// Helper function to print a dict in Python format: {'key': value, ...}
fn printDict(obj: *PyObject) void {
    std.debug.assert(PyDict_Check(obj));
    const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

    std.debug.print("{{", .{});
    if (dict_obj.ma_keys) |keys_ptr| {
        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
        var iter = map.iterator();
        var idx: usize = 0;
        while (iter.next()) |entry| {
            if (idx > 0) {
                std.debug.print(", ", .{});
            }
            // Print key with quotes (string keys)
            std.debug.print("'{s}': ", .{entry.key_ptr.*});
            // Recursively print value (with quoted strings)
            printPyObjectImpl(entry.value_ptr.*, true);
            idx += 1;
        }
    }
    std.debug.print("}}", .{});
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(PyList_Check(obj));
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    const size: usize = @intCast(list_obj.ob_base.ob_size);

    std.debug.print("[", .{});
    for (0..size) |i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        const item = list_obj.ob_item[i];
        // Print each element based on its type
        const item_type = getTypeId(item);
        switch (item_type) {
            .int => {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(item));
                std.debug.print("{}", .{long_obj.ob_digit});
            },
            .string => {
                const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(item));
                const len: usize = @intCast(str_obj.length);
                std.debug.print("'{s}'", .{str_obj.data[0..len]});
            },
            .tuple => {
                PyTuple.print(item);
            },
            else => {
                std.debug.print("{*}", .{item});
            },
        }
    }
    std.debug.print("]", .{});
}

/// Python integer type - re-exported from pyint.zig
pub const PyInt = pyint.PyInt;

/// Python float type - re-exported from pyfloat.zig
pub const PyFloat = pyfloat.PyFloat;

/// Python bool type - re-exported from pybool.zig
pub const PyBool = pybool.PyBool;

/// Bool singletons - re-exported from pybool.zig
pub const Py_True = pybool.Py_True;
pub const Py_False = pybool.Py_False;

/// Feature macros struct - CPython build configuration with comptime-known values
/// Supports subscript access: feature_macros["HAVE_FORK"] returns bool
pub const FeatureMacros = struct {
    /// Comptime subscript access - used when key is known at compile time
    pub fn index(_: FeatureMacros, comptime key: []const u8) bool {
        if (comptime std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (comptime std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (comptime std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (comptime std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (comptime std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (comptime std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Runtime key lookup - returns bool for known keys
    pub fn get(_: FeatureMacros, key: []const u8) bool {
        if (std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Static key list for iteration
    pub const key_list: [6][]const u8 = .{
        "HAVE_FORK",
        "MS_WINDOWS",
        "PY_HAVE_THREAD_NATIVE_ID",
        "Py_REF_DEBUG",
        "Py_TRACE_REFS",
        "USE_STACKCHECK",
    };

    /// Iterator for keys() - returns comptime slice of keys
    pub fn keys() []const []const u8 {
        return &key_list;
    }
};

/// Python file type - re-exported from pyfile.zig
pub const PyFile = pyfile.PyFile;

/// Helper functions for operations that can raise exceptions
/// True division (Python's / operator) - always returns float
/// Integer division (floor division //) with zero check
/// Modulo with zero check
/// Split string on whitespace (Python str.split() with no args)
/// Returns ArrayList of string slices, removes empty strings
pub fn stringSplitWhitespace(text: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};

    // Split on any whitespace, skip empty parts (like Python's split())
    var iter = std.mem.tokenizeAny(u8, text, " \t\n\r\x0c\x0b");
    while (iter.next()) |part| {
        try result.append(allocator, part);
    }

    return result;
}

/// Convert any value to i64 (Python int() constructor)
/// Handles strings, floats, ints, and types with __int__ method
/// Repeat string n times (Python str * n)
pub fn strRepeat(allocator: std.mem.Allocator, s: []const u8, n: usize) []const u8 {
    if (n == 0) return "";
    if (n == 1) return s;

    const result = allocator.alloc(u8, s.len * n) catch return "";
    for (0..n) |i| {
        @memcpy(result[i * s.len ..][0..s.len], s);
    }
    return result;
}

/// Check if a byte is Unicode whitespace
/// Handles ASCII whitespace plus Unicode whitespace characters like \xa0 (NBSP)
pub fn isUnicodeWhitespace(c: u8) bool {
    // ASCII whitespace
    if (std.ascii.isWhitespace(c)) return true;
    // Non-breaking space (Unicode 0xA0)
    if (c == 0xA0) return true;
    // Other common Unicode whitespace in Latin-1 range
    return false;
}

/// Check if a Unicode codepoint is whitespace
pub fn isUnicodeCodepointWhitespace(cp: u21) bool {
    // ASCII whitespace (0x09-0x0D, 0x20)
    if (cp <= 0x20) {
        return cp == 0x20 or (cp >= 0x09 and cp <= 0x0D);
    }
    // Unicode whitespace characters
    return switch (cp) {
        0x00A0, // Non-breaking space
        0x1680, // Ogham space
        0x2000...0x200A, // Various typographic spaces
        0x2028, // Line separator
        0x2029, // Paragraph separator
        0x202F, // Narrow no-break space
        0x205F, // Medium mathematical space
        0x3000, // Ideographic space
        => true,
        else => false,
    };
}

/// Check if a UTF-8 string contains only whitespace characters
pub fn isStringAllWhitespace(text: []const u8) bool {
    if (text.len == 0) return false;
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return false;
        if (i + cp_len > text.len) return false;
        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return false;
        if (!isUnicodeCodepointWhitespace(cp)) return false;
        i += cp_len;
    }
    return true;
}

/// Convert primitive i64 to PyString
// Import and re-export built-in functions
pub const builtins = @import("runtime/builtins.zig");
pub const range = builtins.range;
pub const enumerate = builtins.enumerate;
pub const zip2 = builtins.zip2;
pub const zip3 = builtins.zip3;
pub const all = builtins.all;
pub const any = builtins.any;
pub const abs = builtins.abs;
pub const minList = builtins.minList;
pub const minVarArgs = builtins.minVarArgs;
pub const maxList = builtins.maxList;
pub const maxVarArgs = builtins.maxVarArgs;
pub const sum = builtins.sum;
pub const sorted = builtins.sorted;
pub const reversed = builtins.reversed;
pub const filterTruthy = builtins.filterTruthy;
pub const callable = builtins.callable;
pub const builtinLen = builtins.len;
pub const builtinId = builtins.id;
pub const builtinHash = builtins.hash;
pub const bigIntDivmod = builtins.bigIntDivmod;
pub const bigIntCompare = builtins.bigIntCompare;
pub const operatorEq = builtins.operatorEq;
pub const operatorNe = builtins.operatorNe;
pub const operatorLt = builtins.operatorLt;
pub const operatorLe = builtins.operatorLe;
pub const operatorGt = builtins.operatorGt;
pub const operatorGe = builtins.operatorGe;
pub const classInstanceEq = builtins.classInstanceEq;
pub const classInstanceNe = builtins.classInstanceNe;

// Import and re-export float operations
pub const float_ops = @import("runtime/float_ops.zig");
pub const divideFloat = float_ops.divideFloat;
pub const floatFromHex = float_ops.floatFromHex;
pub const floatGetFormat = float_ops.floatGetFormat;
pub const floatIsInteger = float_ops.floatIsInteger;

// Import and re-export integer operations
pub const int_ops = @import("runtime/int_ops.zig");
pub const toInt = int_ops.toInt;
pub const int__new__ = int_ops.int__new__;
pub const divideInt = int_ops.divideInt;
pub const moduloInt = int_ops.moduloInt;
pub const pyIntFromAny = int_ops.pyIntFromAny;
pub const intToString = int_ops.intToString;
pub const parseIntUnicode = int_ops.parseIntUnicode;
pub const parseIntToBigInt = int_ops.parseIntToBigInt;
pub const intBuiltinCall = int_ops.intBuiltinCall;
pub const intFromBytes = int_ops.intFromBytes;
pub const intToBytes = int_ops.intToBytes;
pub const floatAsIntegerRatio = float_ops.floatAsIntegerRatio;
pub const floatHex = float_ops.floatHex;
pub const floatToHex = float_ops.floatToHex;
pub const floatFloor = float_ops.floatFloor;
pub const floatCeil = float_ops.floatCeil;
pub const floatTrunc = float_ops.floatTrunc;
pub const floatRound = float_ops.floatRound;
pub const floatBuiltinCall = float_ops.floatBuiltinCall;
pub const boolBuiltinCall = float_ops.boolBuiltinCall;
pub const parseFloatWithUnicode = float_ops.parseFloatWithUnicode;

/// Type builtin wrappers - simple functions that return a truthy []const u8
/// Used when types are stored as first-class values in lists
/// These return a non-empty string so bool(type) returns True
pub fn boolBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bool";
}

pub fn intBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "int";
}

pub fn floatBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "float";
}

pub fn strBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "str";
}

pub fn bytesBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bytes";
}

pub fn listBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "list";
}

pub fn dictBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "dict";
}

pub fn setBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "set";
}

pub fn tupleBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "tuple";
}

pub fn frozensetBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "frozenset";
}

pub fn typeBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "type";
}

pub fn objectBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "object";
}

pub fn complexBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "complex";
}
pub const toFloat = float_ops.toFloat;

/// Format mode for formatInt
pub const FormatMode = enum {
    hex_lower,
    hex_upper,
    octal,
    decimal,
};

/// Convert any numeric value (including bool) to a hex/octal formatted string
/// This is needed because Zig's {x} format doesn't support bool directly
/// Returns a stack-allocated formatted string (valid for the current scope)
pub fn formatInt(value: anytype, mode: FormatMode) []const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Convert to unsigned int for formatting
    const int_val: u64 = if (info == .bool)
        @as(u64, if (value) 1 else 0)
    else if (info == .int or info == .comptime_int)
        @as(u64, @intCast(if (value < 0) @as(i64, value) +% @as(i64, @bitCast(@as(u64, std.math.maxInt(u64)))) +% 1 else @as(i64, value)))
    else if (info == .float or info == .comptime_float)
        @as(u64, @intFromFloat(@abs(value)))
    else
        0;

    // Use thread-local buffer for result
    const S = struct {
        threadlocal var buf: [32]u8 = undefined;
    };

    const len = switch (mode) {
        .hex_lower => std.fmt.bufPrint(&S.buf, "{x}", .{int_val}) catch return "0",
        .hex_upper => std.fmt.bufPrint(&S.buf, "{X}", .{int_val}) catch return "0",
        .octal => std.fmt.bufPrint(&S.buf, "{o}", .{int_val}) catch return "0",
        .decimal => std.fmt.bufPrint(&S.buf, "{d}", .{int_val}) catch return "0",
    };
    return len;
}

/// Compare two sets for equality
/// Sets are equal if they have the same elements (order doesn't matter)
pub fn setEqual(a: anytype, b: anytype) bool {
    // If they're the same pointer, they're equal (identity)
    if (@intFromPtr(&a) == @intFromPtr(&b)) return true;

    // Check if they have the same count
    if (a.count() != b.count()) return false;

    // Check if all elements in a are in b
    var iter = a.iterator();
    while (iter.next()) |entry| {
        if (b.get(entry.key_ptr.*) == null) return false;
    }

    return true;
}

/// Generic 'in' operator for any type - works with ArrayLists, slices, etc.
pub fn containsGeneric(container: anytype, item: anytype) bool {
    const T = @TypeOf(container);
    const info = @typeInfo(T);

    // ArrayList: check .items
    if (info == .@"struct" and @hasField(T, "items")) {
        for (container.items) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Array: iterate and compare (e.g., [_]i64{1, 2, 3})
    if (info == .array) {
        for (container) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Slice: iterate and compare
    if (info == .pointer and info.pointer.size == .slice) {
        for (container) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Empty list []
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.len == 0) {
            return false;
        }
    }

    return false;
}

/// Generic 'in' operator - checks membership based on container type
pub fn contains(needle: *PyObject, haystack: *PyObject) bool {
    const haystack_type = getTypeId(haystack);
    switch (haystack_type) {
        .string => {
            // String contains substring
            return PyString.contains(haystack, needle);
        },
        .list => {
            // List contains element
            return PyList.contains(haystack, needle);
        },
        .dict => {
            // Dict contains key (needle must be a string)
            const needle_type = getTypeId(needle);
            if (needle_type != .string) {
                return false;
            }
            const key = PyString.getValue(needle);
            return PyDict.contains(haystack, key);
        },
        else => {
            // Unsupported type - return false
            return false;
        },
    }
}

/// Python list type - re-exported from pylist.zig
pub const PyList = pylist.PyList;

/// Python tuple type - re-exported from pytuple.zig
pub const PyTuple = pytuple.PyTuple;

/// Python string type - re-exported from pystring.zig
pub const PyString = pystring.PyString;

// Import PyDict from separate file
const dict_module = @import("dict.zig");
pub const PyDict = dict_module.PyDict;

// HTTP, async, JSON, regex, sys, and dynamic execution modules
pub const http = @import("http.zig");
pub const async_runtime = @import("async.zig");
pub const asyncio = @import("asyncio.zig");
pub const parallel = @import("parallel.zig");
pub const io = @import("io.zig");
pub const json = @import("json.zig");
pub const re = @import("re.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const sys = @import("sys.zig");
pub const time = @import("time.zig");
pub const math = @import("math.zig");
pub const unittest = @import("unittest.zig");
pub const pathlib = @import("pathlib.zig");
pub const datetime = @import("datetime.zig");
pub const eval_module = @import("eval.zig");
pub const exec_module = @import("exec.zig");
pub const gzip = @import("gzip");
pub const zlib = @import("zlib.zig");
pub const hashlib = @import("hashlib.zig");
pub const pickle = @import("pickle.zig");
pub const test_support = @import("test_support.zig");
pub const base64 = @import("base64.zig");
pub const pylong = @import("pylong.zig");
pub const TestBuffer = @import("testbuffer.zig");

// Green thread runtime (real M:N scheduler) - use module imports to avoid conflicts with h2
pub const GreenThread = @import("green_thread").GreenThread;
pub const Scheduler = @import("scheduler").Scheduler;
pub var scheduler: Scheduler = undefined;
pub var scheduler_initialized = false;

// Netpoller for async I/O and timers
pub const netpoller = @import("netpoller");

// Export convenience functions
pub const httpGet = http.getAsPyString;
pub const httpGetResponse = http.getAsResponse;
pub const sleep = async_runtime.sleep;
pub const now = async_runtime.now;
pub const jsonLoads = json.loads;
pub const jsonDumps = json.dumps;
pub const reCompile = re.compile;
pub const reSearch = re.search;
pub const reMatch = re.match;

// Dynamic execution exports
pub const eval = eval_module.eval;
pub const exec = exec_module.exec;
pub const compile_builtin = @import("compile.zig").compile_builtin;
pub const dynamic_import = @import("dynamic_import.zig").dynamic_import;

// Bytecode execution (for comptime eval)
pub const bytecode = @import("bytecode.zig");
pub const BytecodeProgram = bytecode.BytecodeProgram;
pub const BytecodeVM = bytecode.VM;

// Dynamic attribute access exports
pub const getattr_builtin = dynamic_attrs.getattr_builtin;
pub const setattr_builtin = dynamic_attrs.setattr_builtin;
pub const hasattr_builtin = dynamic_attrs.hasattr_builtin;
pub const vars_builtin = dynamic_attrs.vars_builtin;
pub const globals_builtin = dynamic_attrs.globals_builtin;
pub const locals_builtin = dynamic_attrs.locals_builtin;
pub const dir_builtin = dynamic_attrs.dir_builtin;

// Type checking functions
/// Check if a value is callable (has a __call__ method or is a function)
pub fn isCallable(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    return switch (info) {
        .@"fn" => true,
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => true,
            .@"struct" => @hasDecl(ptr.child, "__call__"),
            else => false,
        },
        .@"struct" => @hasDecl(T, "__call__"),
        else => false,
    };
}

/// Check if cls is a subclass of base (placeholder for runtime type checking)
pub fn isSubclass(cls: anytype, base: anytype) bool {
    _ = cls;
    _ = base;
    // At compile time, type relationships are static
    // Return false as a safe default for runtime checks
    return false;
}

/// Check if cls is a subclass of any of the types in the tuple (for type unions like int | str)
pub fn isSubclassMulti(cls: anytype, bases: anytype) bool {
    _ = cls;
    _ = bases;
    // At compile time, type relationships are static
    // Return false as a safe default for runtime checks
    return false;
}

/// Complex number type
pub const PyComplex = struct {
    real: f64,
    imag: f64,

    pub fn create(real: f64, imag: f64) PyComplex {
        return .{ .real = real, .imag = imag };
    }

    pub fn fromValue(value: anytype) PyComplex {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .int, .comptime_int => .{ .real = @floatFromInt(value), .imag = 0.0 },
            .float, .comptime_float => .{ .real = value, .imag = 0.0 },
            .bool => .{ .real = if (value) 1.0 else 0.0, .imag = 0.0 },
            else => .{ .real = 0.0, .imag = 0.0 },
        };
    }

    pub fn add(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }

    pub fn sub(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real - other.real, .imag = self.imag - other.imag };
    }

    pub fn mul(self: PyComplex, other: PyComplex) PyComplex {
        return .{
            .real = self.real * other.real - self.imag * other.imag,
            .imag = self.real * other.imag + self.imag * other.real,
        };
    }

    pub fn div(self: PyComplex, other: PyComplex) PyComplex {
        // (a + bi) / (c + di) = (ac + bd) / (c^2 + d^2) + ((bc - ad) / (c^2 + d^2))i
        const denom = other.real * other.real + other.imag * other.imag;
        return .{
            .real = (self.real * other.real + self.imag * other.imag) / denom,
            .imag = (self.imag * other.real - self.real * other.imag) / denom,
        };
    }

    /// Negation operator for PyComplex (-c)
    pub fn neg(self: PyComplex) PyComplex {
        return .{ .real = -self.real, .imag = -self.imag };
    }

    pub fn eql(self: PyComplex, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                const f: f64 = @floatFromInt(other);
                return self.real == f and self.imag == 0.0;
            },
            .float, .comptime_float => {
                return self.real == other and self.imag == 0.0;
            },
            .bool => {
                // complex(False) == False is True (both are "zero")
                const f: f64 = if (other) 1.0 else 0.0;
                return self.real == f and self.imag == 0.0;
            },
            .@"struct" => {
                if (T == PyComplex) {
                    return self.real == other.real and self.imag == other.imag;
                }
            },
            else => {},
        }
        return false;
    }
};

/// Decimal type for fixed-point decimal arithmetic (Python's decimal module)
/// This is a simplified implementation using f64 for now
pub const Decimal = struct {
    value: f64,

    pub fn create(value: f64) Decimal {
        return .{ .value = value };
    }

    pub fn fromString(s: []const u8) Decimal {
        return .{ .value = std.fmt.parseFloat(f64, s) catch 0 };
    }

    pub fn add(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value + other.value };
    }

    pub fn sub(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value - other.value };
    }

    pub fn mul(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value * other.value };
    }

    pub fn div(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value / other.value };
    }

    pub fn neg(self: Decimal) Decimal {
        return .{ .value = -self.value };
    }

    pub fn eql(self: Decimal, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return self.value == @as(f64, @floatFromInt(other)),
            .float, .comptime_float => return self.value == other,
            .@"struct" => {
                if (T == Decimal) {
                    return self.value == other.value;
                }
            },
            else => {},
        }
        return false;
    }
};

// Tests
test "PyInt creation and retrieval" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);
    defer decref(obj, allocator);

    try std.testing.expectEqual(@as(i64, 42), PyInt.getValue(obj));
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
}

test "PyList append and retrieval" {
    const allocator = std.testing.allocator;
    const list = try PyList.create(allocator);
    defer decref(list, allocator);

    const item1 = try PyInt.create(allocator, 10);
    const item2 = try PyInt.create(allocator, 20);

    try PyList.append(list, item1);
    try PyList.append(list, item2);

    // Transfer ownership to list (decref our references)
    decref(item1, allocator);
    decref(item2, allocator);

    try std.testing.expectEqual(@as(usize, 2), PyList.len(list));
    try std.testing.expectEqual(@as(i64, 10), PyInt.getValue(try PyList.getItem(list, 0)));
    try std.testing.expectEqual(@as(i64, 20), PyInt.getValue(try PyList.getItem(list, 1)));
}

test "PyString creation" {
    const allocator = std.testing.allocator;
    const obj = try PyString.create(allocator, "hello");
    defer decref(obj, allocator);

    const value = PyString.getValue(obj);
    try std.testing.expectEqualStrings("hello", value);
}

test "PyDict set and get" {
    const allocator = std.testing.allocator;
    const dict = try PyDict.create(allocator);
    defer decref(dict, allocator);

    const value = try PyInt.create(allocator, 100);
    try PyDict.set(dict, "key", value);

    // Transfer ownership to dict
    decref(value, allocator);

    const retrieved = PyDict.get(dict, "key");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(i64, 100), PyInt.getValue(retrieved.?));
}

/// Python hash() builtin - returns integer hash of object
/// For integers: returns the integer itself (Python behavior)
/// For strings: uses wyhash for fast hashing
/// For bools: 1 for True, 0 for False
pub fn pyHash(value: anytype) i64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Integer types: hash is the value itself (Python behavior)
    if (type_info == .int or type_info == .comptime_int) {
        return @intCast(value);
    }

    // Bool: 1 for true, 0 for false
    if (type_info == .bool) {
        return if (value) 1 else 0;
    }

    // Pointer types - check if it's a string slice
    if (type_info == .pointer) {
        const child = type_info.pointer.child;
        // Check for []const u8 (string slice)
        if (child == u8) {
            return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
        }
        // Check for slice of u8
        if (@typeInfo(child) == .array) {
            const array_child = @typeInfo(child).array.child;
            if (array_child == u8) {
                return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
            }
        }
    }

    // Float: hash the bit representation
    if (type_info == .float or type_info == .comptime_float) {
        const bits: u64 = @bitCast(@as(f64, value));
        return @bitCast(bits);
    }

    // Default: return 0 for unhashable types
    return 0;
}

/// Python len() builtin for PyObject* types
/// Dispatches to the appropriate type's len function based on type_id
pub fn pyLen(obj: *PyObject) usize {
    const type_id = getTypeId(obj);
    return switch (type_id) {
        .list => PyList.len(obj),
        .dict => PyDict.len(obj),
        .tuple => PyTuple.len(obj),
        .string => PyString.len(obj),
        else => 0, // None, int, float, bool don't have length
    };
}

/// Compare PyObject with integer (for eval() result comparisons)
pub fn pyObjEqInt(obj: *PyObject, value: i64) bool {
    const type_id = getTypeId(obj);
    if (type_id == .int) {
        return PyInt.getValue(obj) == value;
    }
    return false;
}

/// Extract int value from PyObject (for eval() results)
pub fn pyObjToInt(obj: *PyObject) i64 {
    const type_id = getTypeId(obj);
    if (type_id == .int) {
        return PyInt.getValue(obj);
    }
    return 0;
}

/// Extract BigInt value from PyObject (for eval() results with large integers)
pub fn pyObjToBigInt(obj: *PyObject, allocator: std.mem.Allocator) BigInt {
    const type_id = getTypeId(obj);
    if (type_id == .bigint) {
        // PyBigIntObject - clone the BigInt value
        const bigint_obj: *PyBigIntObject = @ptrCast(@alignCast(obj));
        return bigint_obj.value.clone(allocator) catch BigInt.fromInt(allocator, 0) catch unreachable;
    }
    if (type_id == .int) {
        const val = PyInt.getValue(obj);
        return BigInt.fromInt(allocator, val) catch BigInt.fromInt(allocator, 0) catch unreachable;
    }
    return BigInt.fromInt(allocator, 0) catch unreachable;
}

/// Bounds-checked array list access for exception handling
/// Returns element at index or IndexError if out of bounds
pub fn arrayListGet(comptime T: type, list: std.ArrayList(T), index: i64) PythonError!T {
    const len: i64 = @intCast(list.items.len);

    // Handle negative indices (Python-style)
    const actual_index = if (index < 0) len + index else index;

    // Bounds check
    if (actual_index < 0 or actual_index >= len) {
        return PythonError.IndexError;
    }

    return list.items[@intCast(actual_index)];
}

/// Create a unique base object instance (for sentinel values)
/// Each call returns a new unique object that can be compared by identity
pub fn createObject() *PyObject {
    // Use a static struct for identity comparison with proper alignment
    // Each call creates a unique instance at comptime
    const Sentinel = struct { _marker: u64 align(@alignOf(PyObject)) = 0 };
    const sentinel = Sentinel{};
    return @ptrCast(@alignCast(@constCast(&sentinel)));
}

/// Parse int from string with Unicode whitespace stripping (like Python's int())
/// Strips Unicode whitespace (EM SPACE, EN SPACE, etc.) before parsing
/// Returns error.ValueError for invalid strings (like Python's int())
/// Supports base 0 for auto-detection from prefix (0x, 0o, 0b, 0X, 0O, 0B)
/// Parse int from string directly to BigInt with Unicode whitespace stripping
/// Use this when you know the result will be stored in a BigInt
/// Check if codepoint is Unicode whitespace (Python's definition)
/// Get numeric value of a Unicode digit character (0-9)
/// Returns null if not a digit
/// Parse integer from string with Unicode digit support
/// Concatenate two arrays/slices - returns a new array with elements from both
/// This is Python list concatenation: [1,2] + [3,4] = [1,2,3,4]
pub inline fn concat(a: anytype, b: anytype) @TypeOf(a ++ b) {
    return a ++ b;
}

/// Repeat an array n times - returns a new array with elements repeated
/// This is Python list multiplication: [1,2] * 3 = [1,2,1,2,1,2]
pub inline fn listRepeat(arr: anytype, n: anytype) @TypeOf(arr ** @as(usize, @intCast(n))) {
    return arr ** @as(usize, @intCast(n));
}

/// Marshal loads - decode simplified marshal format back to value
/// Uses compile-time encoding: "T" = True, "F" = False
pub fn marshalLoads(data: []const u8) bool {
    if (data.len == 0) return false;
    // "T" for True, "F" for False
    return data[0] == 'T';
}

/// Pickle loads - decode pickle format back to value
/// Handles pickle protocol 0 format for booleans: "I01\n." = True, "I00\n." = False
pub fn pickleLoads(data: []const u8) bool {
    if (data.len < 4) return false;
    // Protocol 0: "I01\n." = True, "I00\n." = False
    if (data[0] == 'I' and data[1] == '0') {
        return data[2] == '1';
    }
    // Protocol 2+: \x88 = True, \x89 = False
    if (data.len >= 4 and data[0] == 0x80 and data[1] == 0x02) {
        return data[2] == 0x88;
    }
    return false;
}

test "reference counting" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);

    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    incref(obj);
    try std.testing.expectEqual(@as(usize, 2), obj.ref_count);

    decref(obj, allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    decref(obj, allocator);
    // Object should be destroyed here
}
