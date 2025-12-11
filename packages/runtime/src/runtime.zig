/// metal0 Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const builtin = @import("builtin");
const allocator_helper = @import("utils.allocator_helper");

/// Browser WASM (freestanding) has no threading or OS support
pub const is_freestanding = print_utils.is_freestanding;

// Re-export print functions from print_utils.zig
pub const print = print_utils.print;
pub const println = print_utils.println;

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

/// Print utilities
pub const print_utils = @import("runtime/print_utils.zig");

/// Dynamic closure for Python scope semantics
pub const dynamic_closure = @import("runtime/dynamic_closure.zig");

/// Miscellaneous utilities
pub const misc_utils = @import("runtime/misc_utils.zig");

/// PyObject casting utilities
pub const pyobject_cast = @import("runtime/pyobject_cast.zig");

// Re-export DynamicClosure from dynamic_closure.zig
pub const DynamicClosure = dynamic_closure.DynamicClosure;

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
// CPython Compatibility Layer - imported from cpython.zig
// =============================================================================
// All CPython-compatible types, type objects, type checks, and reference
// counting are now in cpython.zig. Import and re-export here for compatibility.
pub const cpython = @import("cpython.zig");

// Re-export all CPython types for backwards compatibility
pub const Py_ssize_t = cpython.Py_ssize_t;
pub const PyObject = cpython.PyObject;
pub const PyVarObject = cpython.PyVarObject;
pub const Py_TPFLAGS = cpython.Py_TPFLAGS;
pub const PyTypeObject = cpython.PyTypeObject;
pub const PyLongObject = cpython.PyLongObject;
pub const PyFloatObject = cpython.PyFloatObject;
pub const PyComplexObject = cpython.PyComplexObject;
pub const PyBoolObject = cpython.PyBoolObject;
pub const PyBigIntObject = cpython.PyBigIntObject;
pub const PyListObject = cpython.PyListObject;
pub const PyTupleObject = cpython.PyTupleObject;
pub const PyDictObject = cpython.PyDictObject;
pub const PyBytesObject = cpython.PyBytesObject;
pub const PyUnicodeObject = cpython.PyUnicodeObject;
pub const PyNoneStruct = cpython.PyNoneStruct;
pub const PyFileObject = cpython.PyFileObject;
pub const PySet_MINSIZE = cpython.PySet_MINSIZE;
pub const setentry = cpython.setentry;
pub const PySetObject = cpython.PySetObject;
pub const DEQUE_BLOCKLEN = cpython.DEQUE_BLOCKLEN;
pub const DequeBlock = cpython.DequeBlock;
pub const PyDequeObject = cpython.PyDequeObject;

// Note: Type object singletons (PyLong_Type, etc.) are NOT re-exported to avoid
// pointer-to-pointer issues. Access them via: runtime.cpython.PyLong_Type
// e.g., const PyLong_Type = &runtime.cpython.PyLong_Type;
pub const Py_None = cpython.Py_None;

// Re-export reference counting and type checking functions
pub const Py_INCREF = cpython.Py_INCREF;
pub const Py_DECREF = cpython.Py_DECREF;
pub const Py_XINCREF = cpython.Py_XINCREF;
pub const Py_XDECREF = cpython.Py_XDECREF;
pub const Py_TYPE = cpython.Py_TYPE;
pub const Py_IS_TYPE = cpython.Py_IS_TYPE;
pub const PyLong_Check = cpython.PyLong_Check;
pub const PyFloat_Check = cpython.PyFloat_Check;
pub const PyComplex_Check = cpython.PyComplex_Check;
pub const PyBool_Check = cpython.PyBool_Check;
pub const PyList_Check = cpython.PyList_Check;
pub const PyTuple_Check = cpython.PyTuple_Check;
pub const PyDict_Check = cpython.PyDict_Check;
pub const PyUnicode_Check = cpython.PyUnicode_Check;
pub const PyBytes_Check = cpython.PyBytes_Check;
pub const PyBigInt_Check = cpython.PyBigInt_Check;
pub const PySet_Check = cpython.PySet_Check;
pub const PyFrozenSet_Check = cpython.PyFrozenSet_Check;
pub const PyAnySet_Check = cpython.PyAnySet_Check;
pub const PyDeque_Check = cpython.PyDeque_Check;
pub const Py_SIZE = cpython.Py_SIZE;
pub const Py_SET_SIZE = cpython.Py_SET_SIZE;

/// Convert PyObject pointer to a list (for list() builtin on PyObject)
/// Returns PyValue.list containing the elements
/// Note: This function returns a slice backed by static storage for small lists
/// or the original list's internal storage. Caller should not modify.
pub fn pyObjectToList(obj: *PyObject) PyValue {
    const cast = pyobject_cast.cast;
    const Static = struct {
        threadlocal var buffer: [64]PyValue = undefined;
    };

    if (PyList_Check(obj)) {
        const list_obj = cast(PyListObject, obj);
        const size = list_obj.ob_base.ob_size;
        if (size <= 0 or list_obj.ob_item == null) return .{ .list = &[_]PyValue{} };
        return convertItemsToValue(list_obj.ob_item.?, @intCast(size), &Static.buffer);
    }
    if (PyTuple_Check(obj)) {
        const tuple_obj = cast(PyTupleObject, obj);
        const size = tuple_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &[_]PyValue{} };
        return convertItemsToValue(@ptrCast(&tuple_obj.ob_item), @intCast(size), &Static.buffer);
    }
    return .{ .list = &[_]PyValue{} };
}

fn convertItemsToValue(items: [*]*PyObject, count: usize, buffer: *[64]PyValue) PyValue {
    if (count <= 64) {
        for (0..count) |i| buffer[i] = pyObjectToPyValue(items[i]);
        return .{ .list = buffer[0..count] };
    }
    const heap_buffer = std.heap.c_allocator.alloc(PyValue, count) catch {
        for (0..64) |i| buffer[i] = pyObjectToPyValue(items[i]);
        return .{ .list = buffer[0..64] };
    };
    for (0..count) |i| heap_buffer[i] = pyObjectToPyValue(items[i]);
    return .{ .list = heap_buffer };
}

/// Convert a single PyObject to PyValue
fn pyObjectToPyValue(obj: ?*PyObject) PyValue {
    const cast = pyobject_cast.cast;
    const o = obj orelse return .{ .none = {} };
    if (PyLong_Check(o)) return .{ .int = @intCast(cast(PyLongObject, o).ob_digit) };
    if (PyFloat_Check(o)) return .{ .float = cast(PyFloatObject, o).ob_fval };
    if (PyBool_Check(o)) return .{ .bool = cast(PyBoolObject, o).ob_digit != 0 };
    return .{ .ptr = o };
}

/// Extract value from PyObject for comparisons (returns f64)
pub fn pyObjectToValue(obj: *PyObject) f64 {
    const cast = pyobject_cast.cast;
    if (PyFloat_Check(obj)) return cast(PyFloatObject, obj).ob_fval;
    if (PyLong_Check(obj)) return @floatFromInt(cast(PyLongObject, obj).ob_digit);
    if (PyBool_Check(obj)) return @floatFromInt(cast(PyBoolObject, obj).ob_digit);
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
// Legacy Compatibility - imported from runtime/legacy_compat.zig
// =============================================================================
const legacy_compat = @import("runtime/legacy_compat.zig");
pub const TypeId = legacy_compat.TypeId;
pub const getTypeId = legacy_compat.getTypeId;
pub const incref = legacy_compat.incref;
pub const decref = legacy_compat.decref;

/// Check if a PyObject is truthy (Python truthiness semantics)
/// Returns false for: None, False, 0, empty string, empty list/dict
/// Returns true for everything else
pub fn pyTruthy(obj: *PyObject) bool {
    const cast = pyobject_cast.cast;
    const type_id = getTypeId(obj);
    return switch (type_id) {
        .none => false,
        .bool => cast(PyBoolObject, obj).ob_digit != 0,
        .int => cast(PyLongObject, obj).ob_digit != 0,
        .float => cast(PyFloatObject, obj).ob_fval != 0.0,
        .string => cast(PyUnicodeObject, obj).length > 0,
        .list => cast(PyListObject, obj).ob_base.ob_size > 0,
        .dict => cast(PyDictObject, obj).ma_used > 0,
        .tuple => cast(PyTupleObject, obj).ob_base.ob_size > 0,
        else => true, // All other types (file, regex, etc.) are truthy
    };
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    printPyObjectImpl(obj, false);
}

/// Internal: print PyObject with quote_strings flag for container elements
fn printPyObjectImpl(obj: *PyObject, quote_strings: bool) void {
    const cast = pyobject_cast.cast;
    const type_id = getTypeId(obj);
    switch (type_id) {
        .int => std.debug.print("{}", .{cast(PyLongObject, obj).ob_digit}),
        .float => std.debug.print("{d}", .{cast(PyFloatObject, obj).ob_fval}),
        .bool => std.debug.print("{s}", .{if (cast(PyBoolObject, obj).ob_digit != 0) "True" else "False"}),
        .string => {
            const str_obj = cast(PyUnicodeObject, obj);
            const len: usize = @intCast(str_obj.length);
            if (quote_strings) {
                std.debug.print("'{s}'", .{str_obj.data[0..len]});
            } else {
                std.debug.print("{s}", .{str_obj.data[0..len]});
            }
        },
        .none => std.debug.print("None", .{}),
        .list => printList(obj),
        .tuple => PyTuple.print(obj),
        .dict => printDict(obj),
        else => printUnknownType(obj),
    }
}

/// Print unknown/extension types using tp_str or tp_repr
fn printUnknownType(obj: *PyObject) void {
    const cast = pyobject_cast.cast;
    const type_obj = Py_TYPE(obj);
    // Try tp_str first
    if (type_obj.tp_str) |str_func| {
        if (tryPrintStringResult(cast, str_func(obj))) return;
    }
    // Try tp_repr
    if (type_obj.tp_repr) |repr_func| {
        if (tryPrintStringResult(cast, repr_func(obj))) return;
    }
    // Fallback: print type name and pointer
    std.debug.print("<{s} at {*}>", .{ std.mem.span(type_obj.tp_name), obj });
}

/// Try to print a string result from tp_str/tp_repr
fn tryPrintStringResult(cast: anytype, result: *PyObject) bool {
    const result_type = Py_TYPE(result);
    if (result_type == &cpython.PyUnicode_Type or
        std.mem.eql(u8, std.mem.span(result_type.tp_name), "str"))
    {
        const str_obj = cast(PyUnicodeObject, result);
        const len: usize = @intCast(str_obj.length);
        std.debug.print("{s}", .{str_obj.data[0..len]});
        return true;
    }
    return false;
}

/// Helper function to print a dict in Python format: {'key': value, ...}
fn printDict(obj: *PyObject) void {
    std.debug.assert(PyDict_Check(obj));
    const cast = pyobject_cast.cast;
    const dict_obj = cast(PyDictObject, obj);

    std.debug.print("{{", .{});
    if (dict_obj.ma_keys) |keys_ptr| {
        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
        var iter = map.iterator();
        var idx: usize = 0;
        while (iter.next()) |entry| {
            if (idx > 0) std.debug.print(", ", .{});
            std.debug.print("'{s}': ", .{entry.key_ptr.*});
            printPyObjectImpl(entry.value_ptr.*, true);
            idx += 1;
        }
    }
    std.debug.print("}}", .{});
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(PyList_Check(obj));
    const cast = pyobject_cast.cast;
    const list_obj = cast(PyListObject, obj);
    const size: usize = @intCast(list_obj.ob_base.ob_size);

    std.debug.print("[", .{});
    for (0..size) |i| {
        if (i > 0) std.debug.print(", ", .{});
        printPyObjectImpl(list_obj.ob_item[i], true); // Reuse printPyObjectImpl
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
    return switch (getTypeId(haystack)) {
        .string => PyString.contains(haystack, needle),
        .list => PyList.contains(haystack, needle),
        .dict => if (getTypeId(needle) == .string) PyDict.contains(haystack, PyString.getValue(needle)) else false,
        else => false,
    };
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
pub const pickle = @import("Lib/pickle/pickle.zig");
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

// Tests moved to runtime/runtime_tests.zig
test {
    _ = @import("runtime/runtime_tests.zig");
}

// Hash operations - re-exported from hash_ops.zig
pub const pyHash = hash_ops.pyHash;
pub const pyPow = hash_ops.pyPow;

/// Python len() builtin for PyObject* types
pub fn pyLen(obj: *PyObject) usize {
    return switch (getTypeId(obj)) {
        .list => PyList.len(obj),
        .dict => PyDict.len(obj),
        .tuple => PyTuple.len(obj),
        .string => PyString.len(obj),
        else => 0,
    };
}

/// Compare PyObject with integer (for eval() result comparisons)
pub fn pyObjEqInt(obj: *PyObject, value: i64) bool {
    return if (getTypeId(obj) == .int) PyInt.getValue(obj) == value else false;
}

/// Extract int value from PyObject (for eval() results)
pub fn pyObjToInt(obj: *PyObject) i64 {
    return if (getTypeId(obj) == .int) PyInt.getValue(obj) else 0;
}

/// Extract BigInt value from PyObject (for eval() results with large integers)
pub fn pyObjToBigInt(obj: *PyObject, allocator: std.mem.Allocator) BigInt {
    const cast = pyobject_cast.cast;
    const zero = BigInt.fromInt(allocator, 0) catch unreachable;
    return switch (getTypeId(obj)) {
        .bigint => cast(PyBigIntObject, obj).value.clone(allocator) catch zero,
        .int => BigInt.fromInt(allocator, PyInt.getValue(obj)) catch zero,
        else => zero,
    };
}

// Re-export misc utilities from misc_utils.zig
pub const arrayListGet = misc_utils.arrayListGet;
pub const concat = misc_utils.concat;

/// Create a unique base object instance (for sentinel values)
/// Each call returns a new unique object that can be compared by identity
pub fn createObject() *PyObject {
    // Use a static struct for identity comparison with proper alignment
    // Each call creates a unique instance at comptime
    const Sentinel = struct { _marker: u64 align(@alignOf(PyObject)) = 0 };
    const sentinel = Sentinel{};
    return @ptrCast(@alignCast(@constCast(&sentinel)));
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
    pub const pickle = @import("Lib/pickle/pickle.zig");
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
