/// metal0 Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const builtin = @import("builtin");
const allocator_helper = @import("utils.allocator_helper");

/// Browser WASM (freestanding) has no threading or OS support
pub const is_freestanding = builtin.os.tag == .freestanding;

/// Cross-platform print function
/// - Native/WASI: uses std.debug.print (stderr)
/// - Freestanding (browser): no-op (JS should use exported functions)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (comptime !is_freestanding) {
        std.debug.print(fmt, args);
    }
}

/// Print a newline
pub fn println() void {
    print("\n", .{});
}

const hashmap_helper = @import("utils.hashmap_helper");
const pyint = @import("Objects/intobject.zig");
const pyfloat = @import("Objects/floatobject.zig");
const pybool = @import("Objects/boolobject.zig");
const pylist = @import("Objects/listobject.zig");
pub const pystring = @import("Objects/unicodeobject.zig");
const pytuple = @import("Objects/tupleobject.zig");
const pyfile = @import("Objects/fileobject.zig");

/// BigInt for arbitrary precision integers (Python int semantics)
pub const bigint = @import("bigint");
pub const BigInt = bigint.BigInt;

/// UnifiedInt - Unified integer type that auto-promotes i64 to BigInt on overflow
/// Use for: function params/returns, user input, arithmetic that may overflow
/// See CLAUDE.md "Integer Type Strategy" for usage guide
pub const unified_int_mod = @import("Objects/pyint.zig");
pub const UnifiedInt = unified_int_mod.UnifiedInt;

/// Export string utilities for native codegen
pub const string_utils = @import("runtime/string_utils.zig");

/// Export slice operations for native codegen (fixes comptime explosion in stepped slices)
pub const slice_ops = @import("runtime/slice_ops.zig");

/// Export set operations for native codegen (fixes comptime explosion in set methods)
pub const set_ops = @import("runtime/set_ops.zig");

/// Export io_uring file reader for batch async I/O (Linux only, fallback on other platforms)
pub const io_uring_reader = @import("runtime/io_uring_reader.zig");

/// Export tuple operations for native codegen (fixes comptime explosion in dynamic tuple indexing)
pub const tuple_ops = @import("runtime/tuple_ops.zig");

/// Export copy operations for native codegen (fixes comptime explosion in copy/deepcopy)
pub const copy_ops = @import("runtime/copy_ops.zig");

/// Export itertools operations for native codegen (fixes comptime explosion in itertools functions)
pub const itertools_ops = @import("runtime/itertools_ops.zig");

// =============================================================================
// Modular submodules (split from runtime.zig for organization)
// These are available as separate imports for new code:
// Usage: @import("runtime").bool_ops.toBool or @import("runtime/bool_ops.zig").toBool
// The original functions remain in runtime.zig for backwards compatibility.
// =============================================================================

/// Boolean operations module
pub const bool_ops = @import("runtime/bool_ops.zig");

/// Equality operations module
pub const equality_mod = @import("runtime/equality.zig");

/// Hash operations module
pub const hash_ops = @import("runtime/hash_ops.zig");

/// Type operations module
pub const type_ops = @import("runtime/type_ops.zig");

/// PyObject types module
pub const pyobject_mod = @import("runtime/pyobject.zig");

/// Complex and Decimal types module
pub const complex_decimal_mod = @import("runtime/complex_decimal.zig");

/// List conversion helpers module
pub const list_conversion_mod = @import("runtime/list_conversion.zig");

/// Glob pattern matching module
pub const glob_ops_mod = @import("runtime/glob_ops.zig");

/// Tuple runtime operations (tupleConcat, tupleMultiply, tupleRepeat, sliceRepeatDynamic)
pub const tuple_runtime = @import("runtime/tuple_runtime.zig");

/// Type builtin stubs (boolBuiltin, intBuiltin, etc.)
pub const type_builtins = @import("runtime/type_builtins.zig");

/// Whitespace detection (isUnicodeWhitespace, isUnicodeCodepointWhitespace, isStringAllWhitespace)
pub const whitespace = @import("runtime/whitespace.zig");

/// Container operations (setEqual, arrayLessThan)
pub const container_ops = @import("runtime/container_ops.zig");

/// Format operations (formatInt, FormatMode)
pub const format_ops = @import("runtime/format_ops.zig");

/// Logic operations (pyOr, pyAnd)
pub const logic_ops = @import("runtime/logic_ops.zig");

/// Floor division operations
pub const floor_div = @import("runtime/floor_div.zig");

/// Pickle and marshal serialization
pub const pickle_marshal = @import("runtime/pickle_marshal.zig");

/// String runtime operations
pub const string_runtime = @import("runtime/string_runtime.zig");

/// Type name and string conversion utilities
pub const type_name = @import("runtime/type_name.zig");

/// List concatenation and repetition
pub const concat_repeat = @import("runtime/concat_repeat.zig");

/// Integer conversion utilities
pub const int_convert = @import("runtime/int_convert.zig");

/// Complex number type
pub const pycomplex = @import("runtime/pycomplex.zig");

/// Decimal type
pub const decimal_mod = @import("runtime/decimal.zig");

/// Feature macros
pub const feature_macros_mod = @import("runtime/feature_macros.zig");

/// DynamicClosure - Type-erased closure for Python scope semantics
/// Used when a function is defined in multiple if/else branches and used outside
/// Holds a pointer to any closure struct and its call function
pub const DynamicClosure = struct {
    /// Opaque pointer to the actual closure struct
    ptr: *anyopaque,
    /// Type-erased call function that takes (ptr, arg1, arg2) and returns result
    call_fn: *const fn (*anyopaque, anytype, anytype) anyerror!i64,

    const Self = @This();

    /// Create a DynamicClosure from any closure that has a .call() method
    pub fn init(closure: anytype) Self {
        const Closure = @TypeOf(closure);
        return .{
            .ptr = @ptrCast(@constCast(&closure)),
            .call_fn = struct {
                fn callWrapper(ptr: *anyopaque, arg1: anytype, arg2: anytype) anyerror!i64 {
                    const c: *const Closure = @ptrCast(@alignCast(ptr));
                    return c.call(arg1, arg2);
                }
            }.callWrapper,
        };
    }

    /// Call the wrapped closure
    pub fn call(self: Self, arg1: anytype, arg2: anytype) anyerror!i64 {
        return self.call_fn(self.ptr, arg1, arg2);
    }
};

// Re-export logic operations from logic_ops.zig
pub const pyOr = logic_ops.pyOr;
pub const pyAnd = logic_ops.pyAnd;

/// Export _string module (formatter_parser, etc.)
pub const _string = @import("Modules/_string.zig");

/// Export C accelerator modules
pub const _functools = @import("Modules/_functools.zig");
pub const _operator = @import("Modules/_operator.zig");
pub const _collections = @import("Modules/_collections/_collections.zig");
pub const _bisect = @import("Modules/_bisect.zig");
pub const _heapq = @import("Modules/_heapq.zig");
pub const _struct = @import("Modules/_struct.zig");
pub const _random = @import("Modules/_random.zig");
pub const _pickle = @import("Modules/_pickle.zig");

/// Export AST executor for eval() support
pub const ast_executor = @import("Python/ast_executor.zig");

/// Export iterators (TupleIterator, ListIterator, ReversedIterator)
pub const iterators = @import("Python/iterobject.zig");
pub const TupleIterator = iterators.TupleIterator;
pub const ListIterator = iterators.ListIterator;
pub const ReversedIterator = iterators.ReversedIterator;
pub const SequenceIterator = iterators.SequenceIterator;

/// Export calendar module
pub const calendar = @import("Lib/calendar.zig");

/// Export os module
pub const os = @import("Lib/os.zig");

/// Export itertools module
pub const itertools = @import("Lib/itertools.zig");

/// Export ctypes FFI module
pub const ctypes = @import("Modules/_ctypes.zig");

/// Export typing module types
pub const typing = @import("Lib/typing.zig");

/// Export dynamic attribute access stubs
const dynamic_attrs = @import("runtime/dynamic_attrs.zig");

/// Export PyValue for dynamic attributes
const object_zig = @import("Objects/object.zig");
pub const PyValue = object_zig.PyValue;
/// Convert any value to PyValue (O(n) instantiations instead of O(n²))
pub const toPyValue = object_zig.toPyValue;

/// Export NativeList - unified list type for native codegen (avoids anytype monomorphization)
/// See listobject.zig for full documentation
pub const NativeList = pylist.NativeList;

/// Export comptime type inference helpers
const comptime_helpers = @import("runtime/comptime_helpers.zig");
pub const InferListType = comptime_helpers.InferListType;
pub const createListComptime = comptime_helpers.createListComptime;
pub const InferDictValueType = comptime_helpers.InferDictValueType;

/// Export comptime closure helpers
pub const closure_impl = @import("runtime/closure_impl.zig");
pub const Closure0 = closure_impl.Closure0;
pub const Closure1 = closure_impl.Closure1;
pub const Closure2 = closure_impl.Closure2;
pub const Closure3 = closure_impl.Closure3;
pub const ZeroClosure = closure_impl.ZeroClosure;
pub const AnyClosure0 = closure_impl.AnyClosure0;
pub const AnyClosure1 = closure_impl.AnyClosure1;
pub const AnyClosure2 = closure_impl.AnyClosure2;
pub const AnyClosure3 = closure_impl.AnyClosure3;
pub const AnyClosure4 = closure_impl.AnyClosure4;
pub const AnyClosure5 = closure_impl.AnyClosure5;
pub const AnyClosure6 = closure_impl.AnyClosure6;
pub const AnyClosure7 = closure_impl.AnyClosure7;

/// Debug info reader for Python line number translation
pub const debug_reader = @import("runtime/debug_reader.zig");

/// Export TypeFactory for first-class types (classes as values)
pub const type_factory = @import("runtime/type_factory.zig");
pub const TypeFactory = type_factory.TypeFactory;
pub const AnyTypeFactory = type_factory.AnyTypeFactory;

/// Export format utilities from runtime_format.zig
const runtime_format = @import("Python/formatter.zig");
pub const formatAny = runtime_format.formatAny;
pub const formatUnknown = runtime_format.formatUnknown;
pub const formatFloat = runtime_format.formatFloat;
pub const formatPyObject = runtime_format.formatPyObject;
pub const PyDict_AsString = runtime_format.PyDict_AsString;
pub const printValue = runtime_format.printValue;
pub const pyFormat = runtime_format.pyFormat;
pub const pyMod = runtime_format.pyMod;
pub const pyFloatMod = runtime_format.pyFloatMod;
pub const pyFloatFloorDiv = runtime_format.pyFloatFloorDiv;
pub const pyStringFormat = runtime_format.pyStringFormat;

// Re-export floor division from floor_div.zig
pub const pyFloorDiv = floor_div.pyFloorDiv;

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

// Exception message handling
pub const setExceptionMessage = exceptions.setExceptionMessage;
pub const setExceptionType = exceptions.setExceptionType;
pub const setException = exceptions.setException;
pub const getExceptionMessage = exceptions.getExceptionMessage;
pub const getExceptionType = exceptions.getExceptionType;
pub const getExceptionStr = exceptions.getExceptionStr;
pub const clearException = exceptions.clearException;

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

// Type checking - re-exported from type_ops.zig
pub const istype = type_ops.istype;

/// Discard a value (consume it to prevent unused variable errors)
/// This is a no-op function that accepts any value
pub inline fn discard(_: anytype) void {}

// Equality operations - re-exported from equality.zig
pub const pyContains = equality_mod.pyContains;
pub const pyCount = equality_mod.pyCount;
pub const pySliceEql = equality_mod.pySliceEql;
pub const pyTupleEql = equality_mod.pyTupleEql;
pub const pyAnyEql = equality_mod.pyAnyEql;
const pyAnyEqlSameType = equality_mod.pyAnyEqlSameType;
pub const iterSlice = equality_mod.iterSlice;

// Bool operations - re-exported from bool_ops.zig
pub const toBool = bool_ops.toBool;
pub const toBoolWithError = bool_ops.toBoolWithError;
pub const toBoolValue = bool_ops.toBoolValue;
pub const validateBoolReturn = bool_ops.validateBoolReturn;
pub const validateFloatReturn = bool_ops.validateFloatReturn;

// Re-export pyToInt from int_convert.zig
pub const pyToInt = int_convert.pyToInt;

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
    // Offset to vectorcall function pointer (PEP 590)
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

/// PySet minimum size (matches CPython)
pub const PySet_MINSIZE: usize = 8;

/// Set entry - key + cached hash
pub const setentry = extern struct {
    key: ?*PyObject,
    hash: Py_ssize_t, // Cached hash of key
};

/// PySetObject - Python set/frozenset (CPython compatible layout)
pub const PySetObject = extern struct {
    ob_base: PyObject, // 16 bytes
    fill: Py_ssize_t, // Number of active + dummy entries
    used: Py_ssize_t, // Number of active entries
    mask: Py_ssize_t, // Table size - 1 (always power of 2 - 1)
    table: ?[*]setentry, // Points to smalltable or malloc'd memory
    hash: Py_ssize_t, // Only used by frozenset, -1 for set
    finger: Py_ssize_t, // Search finger for pop()
    smalltable: [PySet_MINSIZE]setentry, // Inline storage for small sets
    weakreflist: ?*PyObject, // List of weak references
};

/// Deque block size (matches CPython)
pub const DEQUE_BLOCKLEN: usize = 64;

/// DequeBlock - linked list node for deque
pub const DequeBlock = extern struct {
    data: [DEQUE_BLOCKLEN]?*PyObject,
    prev: ?*DequeBlock,
    next: ?*DequeBlock,
};

/// PyDequeObject - Double-ended queue
pub const PyDequeObject = extern struct {
    ob_base: PyObject,
    leftblock: ?*DequeBlock,
    rightblock: ?*DequeBlock,
    leftindex: usize, // Index in leftblock
    rightindex: usize, // Index in rightblock
    len: Py_ssize_t, // Number of items
    maxlen: Py_ssize_t, // Maximum length (-1 for unbounded)
    weakreflist: ?*PyObject,
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
pub var PySet_Type: PyTypeObject = makeTypeObject("set", @sizeOf(PySetObject), 0);
pub var PyFrozenSet_Type: PyTypeObject = makeTypeObject("frozenset", @sizeOf(PySetObject), 0);
pub var PyDeque_Type: PyTypeObject = makeTypeObject("collections.deque", @sizeOf(PyDequeObject), 0);

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

pub inline fn PySet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PySet_Type);
}

pub inline fn PyFrozenSet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyFrozenSet_Type);
}

pub inline fn PyAnySet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PySet_Type) or Py_IS_TYPE(op, &PyFrozenSet_Type);
}

pub inline fn PyDeque_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyDeque_Type);
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

/// Convert PyObject pointer to a list (for list() builtin on PyObject)
/// Returns PyValue.list containing the elements
/// Note: This function returns a slice backed by static storage for small lists
/// or the original list's internal storage. Caller should not modify.
pub fn pyObjectToList(obj: *PyObject) PyValue {
    // Check if it's a list
    if (PyList_Check(obj)) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size = list_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &[_]PyValue{} };

        // Convert list elements to PyValue slice
        // Use thread-local static buffer for small lists to avoid allocation
        const Static = struct {
            threadlocal var buffer: [64]PyValue = undefined;
        };

        const count: usize = @intCast(size);
        if (list_obj.ob_item == null) return .{ .list = &[_]PyValue{} };

        const items = list_obj.ob_item.?;

        // Small list - use thread-local buffer (no allocation needed)
        if (count <= 64) {
            for (0..count) |i| {
                Static.buffer[i] = pyObjectToPyValue(items[i]);
            }
            return .{ .list = Static.buffer[0..count] };
        }

        // Large list - allocate on heap using c_allocator
        // The caller must free this when done if needed
        const heap_buffer = std.heap.c_allocator.alloc(PyValue, count) catch {
            // Fallback: return first 64 elements on allocation failure
            for (0..64) |i| {
                Static.buffer[i] = pyObjectToPyValue(items[i]);
            }
            return .{ .list = Static.buffer[0..64] };
        };
        for (0..count) |i| {
            heap_buffer[i] = pyObjectToPyValue(items[i]);
        }
        return .{ .list = heap_buffer };
    }
    // Check if it's a tuple
    if (PyTuple_Check(obj)) {
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size = tuple_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &[_]PyValue{} };

        const Static = struct {
            threadlocal var buffer: [64]PyValue = undefined;
        };

        const count: usize = @intCast(size);
        if (count <= 64) {
            for (0..count) |i| {
                Static.buffer[i] = pyObjectToPyValue(tuple_obj.ob_item[i]);
            }
            return .{ .list = Static.buffer[0..count] };
        }

        return .{ .list = &[_]PyValue{} };
    }
    // Default: return empty list
    return .{ .list = &[_]PyValue{} };
}

/// Convert a single PyObject to PyValue
fn pyObjectToPyValue(obj: ?*PyObject) PyValue {
    const o = obj orelse return .{ .none = {} };

    if (PyLong_Check(o)) {
        // Get value from PyLongObject
        const long_obj: *PyLongObject = @ptrCast(@alignCast(o));
        return .{ .int = @intCast(long_obj.ob_digit) };
    }
    if (PyFloat_Check(o)) {
        const float_obj: *PyFloatObject = @ptrCast(@alignCast(o));
        return .{ .float = float_obj.ob_fval };
    }
    if (PyBool_Check(o)) {
        const bool_obj: *PyBoolObject = @ptrCast(@alignCast(o));
        return .{ .bool = bool_obj.ob_digit != 0 };
    }
    if (PyUnicode_Check(o)) {
        // Return pointer as opaque - caller can cast to *PyObject for string ops
        return .{ .ptr = o };
    }
    // Default: wrap as ptr
    return .{ .ptr = o };
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
        // Python convention: nan never has sign
        if (std.math.isNan(val)) return try allocator.dupe(u8, "nan");
        if (std.math.isInf(val)) return try allocator.dupe(u8, if (val < 0) "-inf" else "inf");
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
            // For C extension types, try to call tp_str or tp_repr
            const type_obj = Py_TYPE(obj);
            if (type_obj.tp_str) |str_func| {
                const str_result = str_func(obj);
                // Check if result is a string type (PyUnicode) and print it
                const result_type = Py_TYPE(str_result);
                if (result_type == &PyUnicode_Type or
                    std.mem.eql(u8, std.mem.span(result_type.tp_name), "str"))
                {
                    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(str_result));
                    const len: usize = @intCast(str_obj.length);
                    std.debug.print("{s}", .{str_obj.data[0..len]});
                    return;
                }
            }
            if (type_obj.tp_repr) |repr_func| {
                const repr_result = repr_func(obj);
                const result_type = Py_TYPE(repr_result);
                if (result_type == &PyUnicode_Type or
                    std.mem.eql(u8, std.mem.span(result_type.tp_name), "str"))
                {
                    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(repr_result));
                    const len: usize = @intCast(str_obj.length);
                    std.debug.print("{s}", .{str_obj.data[0..len]});
                    return;
                }
            }
            // Fallback: print type name and pointer
            std.debug.print("<{s} at {*}>", .{ std.mem.span(type_obj.tp_name), obj });
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

// Re-export FeatureMacros from feature_macros.zig
pub const FeatureMacros = feature_macros_mod.FeatureMacros;

/// Python file type - re-exported from pyfile.zig
pub const PyFile = pyfile.PyFile;

// Re-export string runtime operations from string_runtime.zig
pub const stringSplitWhitespace = string_runtime.stringSplitWhitespace;
pub const strRepeat = string_runtime.strRepeat;

// Re-export tuple operations from tuple_runtime.zig
pub const tupleConcat = tuple_runtime.tupleConcat;
pub const TupleConcatResult = tuple_runtime.TupleConcatResult;
pub const tupleMultiply = tuple_runtime.tupleMultiply;
pub const TupleMultiplyResult = tuple_runtime.TupleMultiplyResult;
pub const tupleRepeat = tuple_runtime.tupleRepeat;
pub const sliceRepeatDynamic = tuple_runtime.sliceRepeatDynamic;
pub const getElemType = tuple_runtime.getElemType;

// Re-export whitespace operations from whitespace.zig
pub const isUnicodeWhitespace = whitespace.isUnicodeWhitespace;
pub const isUnicodeCodepointWhitespace = whitespace.isUnicodeCodepointWhitespace;
pub const isStringAllWhitespace = whitespace.isStringAllWhitespace;

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
pub const assertEqualGeneric = builtins.assertEqualGeneric;
pub const pyEqual = builtins.pyEqual;
pub const pyFloat = float_ops.pyFloat;
pub const PyPowResult = builtins.PyPowResult;
// pyPow is defined locally in this file with more comprehensive special case handling
pub const PyBytes = builtins.PyBytes;
pub const pyStr = builtins.pyStr;

// Re-export type name functions from type_name.zig
pub const pyTypeName = type_name.pyTypeName;

// Import and re-export float operations
pub const float_ops = @import("runtime/float_ops.zig");
pub const divideFloat = float_ops.divideFloat;
pub const floatFromHex = float_ops.floatFromHex;
pub const floatGetFormat = float_ops.floatGetFormat;
pub const toFloat = float_ops.toFloat;
pub const subtractNum = float_ops.subtractNum;
pub const addNum = float_ops.addNum;
pub const mulNum = float_ops.mulNum;
pub const numToFloat = float_ops.numToFloat;
pub const floatIsInteger = float_ops.floatIsInteger;

// Import and re-export integer operations
pub const int_ops = @import("runtime/int_ops.zig");
pub const toInt = int_ops.toInt;
pub const toIntBig = int_ops.toIntBig;

pub const packInt = int_convert.packInt;
pub const int__new__ = int_ops.int__new__;
pub const divideInt = int_ops.divideInt;
pub const moduloInt = int_ops.moduloInt;
pub const pyIntFromAny = int_ops.pyIntFromAny;

pub const pyStrFromAny = type_name.pyStrFromAny;
pub const intToString = int_ops.intToString;
pub const parseIntUnicode = int_ops.parseIntUnicode;
pub const parseIntToBigInt = int_ops.parseIntToBigInt;
pub const intBuiltinCall = int_ops.intBuiltinCall;
pub const intFromBytes = int_ops.intFromBytes;
pub const intToBytes = int_ops.intToBytes;
pub const floatAsIntegerRatio = float_ops.floatAsIntegerRatio;
pub const floatAsIntegerRatioBigInt = float_ops.floatAsIntegerRatioBigInt;
pub const IntegerRatioResult = float_ops.IntegerRatioResult;
pub const floatHex = float_ops.floatHex;
pub const floatToHex = float_ops.floatToHex;
pub const floatFloor = float_ops.floatFloor;
pub const floatFloorBig = float_ops.floatFloorBig;
pub const floatFloorAny = float_ops.floatFloorAny;
pub const floatCeil = float_ops.floatCeil;
pub const floatCeilBig = float_ops.floatCeilBig;
pub const floatCeilAny = float_ops.floatCeilAny;
pub const floatTrunc = float_ops.floatTrunc;
pub const IntResult = float_ops.IntResult;
pub const FloorCeilResult = float_ops.FloorCeilResult;
pub const floatRound = float_ops.floatRound;
pub const floatBuiltinCall = float_ops.floatBuiltinCall;
pub const floatBuiltinCallBytes = float_ops.floatBuiltinCallBytes;
pub const boolBuiltinCall = float_ops.boolBuiltinCall;
pub const parseFloatWithUnicode = float_ops.parseFloatWithUnicode;
pub const parseFloatStr = float_ops.parseFloatStr;

// Re-export type builtins from type_builtins.zig
pub const boolBuiltin = type_builtins.boolBuiltin;
pub const intBuiltin = type_builtins.intBuiltin;
pub const floatBuiltin = type_builtins.floatBuiltin;
pub const strBuiltin = type_builtins.strBuiltin;
pub const bytesBuiltin = type_builtins.bytesBuiltin;
pub const listBuiltin = type_builtins.listBuiltin;
pub const dictBuiltin = type_builtins.dictBuiltin;
pub const setBuiltin = type_builtins.setBuiltin;
pub const tupleBuiltin = type_builtins.tupleBuiltin;
pub const frozensetBuiltin = type_builtins.frozensetBuiltin;
pub const typeBuiltin = type_builtins.typeBuiltin;
pub const objectBuiltin = type_builtins.objectBuiltin;
pub const complexBuiltin = type_builtins.complexBuiltin;

// Re-export format operations from format_ops.zig
pub const FormatMode = format_ops.FormatMode;
pub const formatInt = format_ops.formatInt;

// Re-export container operations from container_ops.zig
pub const setEqual = container_ops.setEqual;
pub const arrayLessThan = container_ops.arrayLessThan;

/// Generic 'in' operator for any type - works with ArrayLists, slices, etc.
/// Wrapper around container_ops.containsGeneric with NativeList and pyAnyEql bound
pub fn containsGeneric(container: anytype, item: anytype) bool {
    return container_ops.containsGeneric(NativeList, pyAnyEql, container, item);
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
const dict_module = @import("Objects/dictobject.zig");
pub const PyDict = dict_module.PyDict;

// HTTP, async, JSON, regex, sys, and dynamic execution modules
// HTTP uses pool.zig/server.zig which have Mutex - not available on freestanding
pub const http = if (is_freestanding) void else @import("Lib/http.zig");
// WebSocket client (maps to Python's websockets library)
pub const websocket = if (is_freestanding) void else @import("Lib/websocket.zig");
// Async modules require threading (not available on freestanding)
pub const async_runtime = if (is_freestanding) void else @import("Lib/async.zig");
pub const asyncio = if (is_freestanding) void else @import("Lib/asyncio.zig");
pub const parallel = if (is_freestanding) void else @import("runtime/parallel.zig");
pub const io = @import("Lib/io.zig");
pub const json = @import("Lib/json.zig");
pub const re = @import("Lib/re.zig");
pub const tokenizer = @import("runtime/tokenizer.zig");
pub const sys = @import("Lib/sys.zig");
pub const time = @import("Lib/time.zig");
pub const math = @import("Lib/math.zig");
pub const unittest = @import("Lib/unittest.zig");
pub const pathlib = @import("Lib/pathlib.zig");
pub const datetime = @import("Lib/datetime.zig");
// eval/exec use eval_cache which has Thread.Mutex - not available on freestanding
pub const eval_module = if (is_freestanding) void else @import("Python/ceval.zig");
pub const exec_module = if (is_freestanding) void else @import("Python/pythonrun.zig");
pub const gzip = @import("gzip");
pub const zlib = @import("Modules/zlibmodule.zig");
pub const hashlib = @import("Modules/_hashlib.zig");
pub const pickle = @import("Lib/pickle.zig");
pub const test_support = @import("runtime/test_support.zig");
pub const list_tests = @import("runtime/list_tests.zig");
pub const base64 = @import("Lib/base64.zig");
pub const pylong = @import("Objects/longobject.zig");
pub const TestBuffer = @import("runtime/testbuffer.zig");

// Green thread runtime (real M:N scheduler) - use module imports to avoid conflicts with h2
// Conditional on non-freestanding targets (browser WASM doesn't support threads)
pub const GreenThread = if (is_freestanding) void else @import("green_thread").GreenThread;
pub const Scheduler = if (is_freestanding) void else @import("scheduler").Scheduler;
pub var scheduler: if (is_freestanding) void else Scheduler = if (is_freestanding)
{} else undefined;
pub var scheduler_initialized = false;

// Netpoller for async I/O and timers (not available on freestanding)
pub const netpoller = if (is_freestanding) void else @import("netpoller");

// Export convenience functions (some require threading)
pub const httpGet = if (is_freestanding) void else http.getAsPyString;
pub const httpGetResponse = if (is_freestanding) void else http.getAsResponse;
pub const sleep = if (is_freestanding) void else async_runtime.sleep;
pub const now = if (is_freestanding) void else async_runtime.now;
pub const jsonLoads = json.loads;
pub const jsonDumps = json.dumps;
pub const reCompile = re.compile;
pub const reSearch = re.search;
pub const reMatch = re.match;

// Dynamic execution exports (require threading via eval_cache)
pub const eval = if (is_freestanding) void else eval_module.eval;
pub const exec = if (is_freestanding) void else exec_module.exec;
pub const compile_builtin = @import("Python/ast.zig").compile_builtin;
pub const dynamic_import = @import("runtime/dynamic_import.zig").dynamic_import;

// Bytecode execution (for comptime eval)
pub const bytecode = @import("Python/compile.zig");
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

// Type checking functions - re-exported from type_ops.zig
pub const isCallable = type_ops.isCallable;
pub const isSubclass = type_ops.isSubclass;
pub const isSubclassMulti = type_ops.isSubclassMulti;

// Re-export PyComplex from pycomplex.zig
pub const PyComplex = pycomplex.PyComplex;

// Re-export Decimal from decimal.zig
pub const Decimal = decimal_mod.Decimal;

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

// Hash operations - re-exported from hash_ops.zig
pub const pyHash = hash_ops.pyHash;
pub const pyPow = hash_ops.pyPow;

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

// Re-export list concat/repeat operations from concat_repeat.zig
pub const concatRuntime = concat_repeat.concatRuntime;
pub const repeatRuntime = concat_repeat.repeatRuntime;
pub const listRepeat = concat_repeat.listRepeat;

// Re-export pickle/marshal operations from pickle_marshal.zig
pub const marshalLoads = pickle_marshal.marshalLoads;
pub const pickleLoads = pickle_marshal.pickleLoads;
pub const pickleLoadsBool = pickle_marshal.pickleLoadsBool;

// Glob operations - re-exported from glob_ops.zig
pub const globMatch = glob_ops_mod.globMatch;
pub const matchCharClass = glob_ops_mod.matchCharClass;
pub const rglobCollect = glob_ops_mod.rglobCollect;

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

// List conversion helpers - re-exported from list_conversion.zig
pub const listFromTuple = list_conversion_mod.listFromTuple;
pub const listFromString = list_conversion_mod.listFromString;
pub const listFromAny = list_conversion_mod.listFromAny;

// =============================================================================
// DCE-Friendly Namespace Exports
// =============================================================================
// These namespace structs enable Zig's dead code elimination by only pulling in
// modules when explicitly accessed (e.g., runtime.Lib.json instead of runtime.json).
// The direct pub const exports above are kept for backwards compatibility.

/// Lib/ directory modules - Python standard library implementations
pub const Lib = struct {
    pub const json = @import("Lib/json.zig");
    pub const re = @import("Lib/re.zig");
    pub const sys = @import("Lib/sys.zig");
    pub const time = @import("Lib/time.zig");
    pub const math = @import("Lib/math.zig");
    pub const os = @import("Lib/os.zig");
    pub const io = @import("Lib/io.zig");
    pub const typing = @import("Lib/typing.zig");
    pub const pathlib = @import("Lib/pathlib.zig");
    pub const datetime = @import("Lib/datetime.zig");
    pub const calendar = @import("Lib/calendar.zig");
    pub const itertools = @import("Lib/itertools.zig");
    pub const collections = @import("Lib/collections.zig");
    pub const unittest = @import("Lib/unittest.zig");
    pub const pickle = @import("Lib/pickle.zig");
    pub const base64 = @import("Lib/base64.zig");
    pub const http = if (is_freestanding) void else @import("Lib/http.zig");
    pub const websocket = if (is_freestanding) void else @import("Lib/websocket.zig");
    pub const asyncio = if (is_freestanding) void else @import("Lib/asyncio.zig");
};

/// Modules/ directory - C extension module implementations
pub const Modules = struct {
    pub const ctypes = @import("Modules/_ctypes.zig");
    pub const hashlib = @import("Modules/_hashlib.zig");
    pub const zlib = @import("Modules/zlibmodule.zig");
    pub const _string = @import("Modules/_string.zig");
    pub const _functools = @import("Modules/_functools.zig");
    pub const _operator = @import("Modules/_operator.zig");
    pub const _collections = @import("Modules/_collections/_collections.zig");
    pub const _bisect = @import("Modules/_bisect.zig");
    pub const _heapq = @import("Modules/_heapq.zig");
    pub const _struct = @import("Modules/_struct.zig");
    pub const _random = @import("Modules/_random.zig");
    pub const _pickle = @import("Modules/_pickle.zig");
};
