/// metal0 Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const builtin = @import("builtin");
/// Re-export allocator_helper for generated code (so it can use runtime.allocator_helper)
pub const allocator_helper = @import("utils.allocator_helper");
/// Re-export fast_allocator directly for convenience (also ensures allocator_helper is used)
pub const fast_allocator = allocator_helper.fast_allocator;

/// Browser WASM (freestanding) has no threading or OS support
pub const is_freestanding = print_utils.is_freestanding;

// Re-export print functions from print_utils.zig
pub const print = print_utils.print;
pub const println = print_utils.println;

/// Re-export hashmap_helper for generated code (so it can use runtime.hashmap_helper)
pub const hashmap_helper = @import("utils.hashmap_helper");

// Type-erased callable (prevents monomorphization explosion in decorators)
const callable = @import("runtime/callable.zig");
pub const AnyCallable = callable.AnyCallable;

const pyint = @import("Objects/intobject.zig");
pub const PyInt = pyint.PyInt;
const pyfloat = @import("Objects/floatobject.zig");
pub const PyFloat = pyfloat.PyFloat;
const pybool = @import("Objects/boolobject.zig");
pub const PyBool = pybool.PyBool;
pub const Py_True = pybool.Py_True;
pub const Py_False = pybool.Py_False;
const pylist = @import("Objects/listobject.zig");
pub const pystring = @import("Objects/unicodeobject.zig");
pub const PyString = pystring.PyString;
const pytuple = @import("Objects/tupleobject.zig");
const pyfile = @import("Objects/fileobject.zig");
const pydict = @import("Objects/dictobject.zig");
pub const PyDict = pydict.PyDict;
const pytype_mod = @import("Objects/pytype.zig");
pub const PyType = pytype_mod.PyType;
pub const typeNew = pytype_mod.typeNew;
pub const typeCall = pytype_mod.typeCall;
pub const dynamicType = pytype_mod.dynamicType;
pub const initBuiltinType = pytype_mod.initBuiltinType;
pub const getBuiltinType = pytype_mod.getBuiltinType;

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

/// Export copy module for Python's copy module (copy.Error, copy.error, etc.)
pub const copy = @import("Lib/copy.zig");

/// Export itertools operations for native codegen (fixes comptime explosion in itertools functions)
pub const itertools_ops = @import("runtime/itertools_ops.zig");

/// Export list operations for native codegen (fixes comptime explosion in list literal casting)
pub const list_ops = @import("runtime/list_ops.zig");

/// Export operator operations for reducing operator callable monomorphization
pub const operator_ops = @import("runtime/operator_ops.zig");

/// Export comparison operations for reducing comparison monomorphization
/// Use comparison_ops.eqI64, ltF64, etc. instead of operator.eq with anytype
pub const comparison_ops = @import("runtime/comparison_ops.zig");

/// Export BigInt operations for reducing parenthesization complexity in generated code
/// Use bigint_ops.add(a, b, alloc) instead of ((a.add(&b, alloc) catch @panic("OOM")))
pub const bigint_ops = @import("runtime/bigint_ops.zig");

/// Export UnifiedInt operations - auto-promoting integer arithmetic (i64 -> BigInt on overflow)
/// Use unified_int_ops.add(a, b, alloc) for Python's unlimited precision int semantics
pub const unified_int_ops = @import("runtime/unified_int_ops.zig");

/// Bytecode VM - Dynamic Python execution for eval(), exec(), dynamic import, etc.
/// The VM dispatches to existing runtime functions for actual Python semantics.
pub const bytecode = @import("bytecode.zig");

// =============================================================================
// Modular submodules (split from runtime.zig for organization)
// These are available as separate imports for new code:
// Usage: @import("runtime").bool_ops.toBool or @import("runtime/bool_ops.zig").toBool
// The original functions remain in runtime.zig for backwards compatibility.
// =============================================================================

/// Builtins module - Python built-in functions
pub const builtins = @import("runtime/builtins.zig");

/// Integer operations module (int() builtin, parsing, etc.)
pub const int_ops = @import("runtime/int_ops.zig");
/// Direct export for assertRaises(ValueError, int, ...) pattern
pub const intBuiltinCall = int_ops.intBuiltinCall;

/// Boolean operations module
pub const bool_ops = @import("runtime/bool_ops.zig");

/// Equality operations module
pub const equality_mod = @import("runtime/equality.zig");

/// Hash operations module
pub const hash_ops = @import("runtime/hash_ops.zig");

/// Traceback field stubs for AOT compilation
pub const traceback_stub = @import("runtime/traceback_stub.zig");

/// Type operations module
pub const type_ops = @import("runtime/type_ops.zig");

/// Type predicates (isIntInfo, isFloatInfo, etc.)
pub const type_predicates = @import("runtime/type_predicates.zig");

/// Numbers ABC support for issubclass(x, numbers.Number) etc.
pub const numbers_abc = @import("runtime/numbers_abc.zig");
pub const NumbersABC = numbers_abc.NumbersABC;
pub const isNumbersSubclass = type_ops.isNumbersSubclass;
pub const isNumbersSubclassType = type_ops.isNumbersSubclassType;
pub const parseNumbersABC = type_ops.parseNumbersABC;

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

// Re-export tuple operations for direct codegen access
pub const tupleConcat = tuple_runtime.tupleConcat;
pub const tupleMultiply = tuple_runtime.tupleMultiply;
pub const tupleRepeat = tuple_runtime.tupleRepeat;

/// Type builtin stubs (boolBuiltin, intBuiltin, etc.)
pub const type_builtins = @import("runtime/type_builtins.zig");

/// Whitespace detection (isUnicodeWhitespace, isUnicodeCodepointWhitespace, isStringAllWhitespace)
pub const whitespace = @import("runtime/whitespace.zig");

/// Container operations (setEqual, arrayLessThan)
pub const container_ops = @import("runtime/container_ops.zig");

/// Container dispatch helpers (getSlice, getLen, toIterSlice) - reduces monomorphization
pub const container_dispatch = @import("runtime/container_dispatch.zig");

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

// Re-export string operations for codegen
pub const strRepeat = string_runtime.strRepeat;
pub const stringSplitWhitespace = string_runtime.stringSplitWhitespace;

/// Bltinmodule sequences (len, all, any, etc.)
const bltinmodule_sequences = @import("Python/bltinmodule/sequences.zig");

// Re-export builtinLen for codegen
pub const builtinLen = bltinmodule_sequences.len_builtin;

/// Type name and string conversion utilities
pub const type_name = @import("runtime/type_name.zig");
pub const pyTypeName = type_name.pyTypeName;
pub const pyStrFromAny = type_name.pyStrFromAny;
pub const pyFloatFromAny = type_name.pyFloatFromAny;

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

/// PyDefaultDict - Python-compatible defaultdict with default_factory and __missing__
pub const pydefaultdict = @import("runtime/pydefaultdict.zig");
pub const PyDefaultDict = pydefaultdict.PyDefaultDict;
pub const IntDefaultDict = pydefaultdict.IntDefaultDict;
pub const FactoryType = pydefaultdict.FactoryType;

// Re-export DynamicClosure from dynamic_closure.zig
pub const DynamicClosure = dynamic_closure.DynamicClosure;

/// Global scheduler initialization flag for async/await codegen
/// Used by generated code to check if scheduler is initialized before spawning tasks
pub var scheduler_initialized: bool = false;

/// Re-export Scheduler type from scheduler module for async/await codegen
pub const Scheduler = @import("scheduler").Scheduler;

/// Global scheduler instance for async/await codegen
pub var scheduler: ?Scheduler = null;

// Re-export logic operations from logic_ops.zig
pub const pyOr = logic_ops.pyOr;
pub const pyAnd = logic_ops.pyAnd;

// Re-export assertion functions from builtins for unittest
pub const assertEqualGeneric = builtins.assertEqualGeneric;

// Re-export bytes helper for codegen
pub const extractBytesData = builtins.extractBytesData;

// Re-export compile_builtin from Python/ast.zig for codegen
pub const compile_builtin = @import("Python/ast.zig").compile_builtin;

// Re-export eval/exec from Python modules for codegen
pub const eval = @import("Python/ceval.zig").eval;
pub const evalWithScope = @import("Python/ceval.zig").evalWithScope;
pub const exec = @import("Python/pythonrun.zig").exec;
pub const execWithScope = @import("Python/pythonrun.zig").execWithScope;

// Re-export BytecodeProgram and VM for codegen
pub const BytecodeProgram = @import("Python/compile.zig").BytecodeProgram;
pub const BytecodeVM = @import("Python/compile.zig").VM;

// Re-export builtins dict for eval/exec (three-tier lookup: locals -> globals -> builtins)
pub const builtins_dict = @import("Python/builtins_dict.zig");

// Re-export test_support and unittest for unittest codegen
pub const test_support = @import("Lib/test/support.zig");
pub const unittest = @import("Lib/unittest.zig");

// Re-export all type builtins for codegen (via existing type_builtins import at line 100)
pub const boolBuiltinCall = type_builtins.boolBuiltinCall;
pub const boolBuiltin = type_builtins.boolBuiltin;
pub const intBuiltin = type_builtins.intBuiltin;
pub const floatBuiltin = type_builtins.floatBuiltin;
pub const floatBuiltinCall = @import("runtime/float_ops.zig").floatBuiltinCall;
pub const parseFloatWithUnicode = @import("runtime/float_ops/parsing.zig").parseFloatWithUnicode;
pub const parseFloatStr = @import("runtime/float_ops/parsing.zig").parseFloatStr;
pub const floatIsInteger = @import("runtime/float_ops/conversion.zig").floatIsInteger;
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
pub const hasattr_builtin = @import("runtime/dynamic_attrs.zig").hasattr_builtin;

// Re-export pyDict helpers for Two-Flow runtime
pub const pyDictKeys = builtins.pyDictKeys;
pub const pyDictValues = builtins.pyDictValues;
pub const pyDictItems = builtins.pyDictItems;
pub const pyDictPop = builtins.pyDictPop;
pub const pyDictUpdate = builtins.pyDictUpdate;
pub const pyDictCopy = builtins.pyDictCopy;
pub const pyDictSetdefault = builtins.pyDictSetdefault;

// Re-export pickle for codegen (use actual pickle implementation with loads/dumps)
pub const pickle = @import("Lib/pickle/pickle.zig");

// Re-export format_ops for codegen
pub const formatInt = @import("runtime/format_ops.zig").formatInt;

// Re-export PyComplex for codegen (use pycomplex.zig which has fromValue)
pub const PyComplex = @import("runtime/pycomplex.zig").PyComplex;

// Re-export type_ops for codegen
pub const isCallable = @import("runtime/type_ops.zig").isCallable;
pub const isSubclass = @import("runtime/type_ops.zig").isSubclass;
pub const isSubclassMulti = @import("runtime/type_ops.zig").isSubclassMulti;
pub const registerVirtualSubclass = @import("runtime/type_ops.zig").registerVirtualSubclass;
pub const isVirtualSubclass = @import("runtime/type_ops.zig").isVirtualSubclass;
pub const clearRegistryForClass = @import("runtime/type_ops.zig").clearRegistryForClass;
pub const getRegistryCountForClass = @import("runtime/type_ops.zig").getRegistryCountForClass;

// Re-export float_ops for codegen
pub const divideFloat = @import("runtime/float_ops.zig").divideFloat;
pub const floatFloorBig = @import("runtime/float_ops/rounding.zig").floatFloorBig;
pub const floatCeilBig = @import("runtime/float_ops/rounding.zig").floatCeilBig;
pub const IntResult = @import("runtime/float_ops/rounding.zig").IntResult;
pub const floatAsIntegerRatioBigInt = @import("runtime/float_ops/ratio.zig").floatAsIntegerRatioBigInt;
pub const floatAsIntegerRatio = @import("runtime/float_ops/ratio.zig").floatAsIntegerRatio;
pub const toFloat = @import("runtime/float_ops/conversion.zig").toFloat;
pub const toIntBig = @import("runtime/int_ops.zig").toIntBig;

// Re-export hash operations for codegen
pub const pyHash = @import("runtime/hash_ops.zig").pyHash;

// Re-export float format and pack operations for codegen
pub const floatGetFormat = @import("runtime/float_ops/conversion.zig").floatGetFormat;
pub const packInt = @import("runtime/int_convert.zig").packInt;

// Re-export math module for codegen (runtime.math.isnan, etc.)
// Wrapper that adds PyPowResult support
pub const math = struct {
    // Re-export all std.math constants
    pub const inf = std.math.inf;
    pub const nan = std.math.nan;
    pub const e = std.math.e;
    pub const pi = std.math.pi;
    pub const tau = std.math.tau;

    // Re-export std.math functions
    pub const pow = std.math.pow;
    pub const sqrt = std.math.sqrt;
    pub const log = std.math.log;
    pub const log2 = std.math.log2;
    pub const log10 = std.math.log10;
    pub const exp = std.math.exp;
    pub const exp2 = std.math.exp2;
    pub const floor = std.math.floor;
    pub const ceil = std.math.ceil;
    pub const round = std.math.round;
    pub const trunc = std.math.trunc;
    pub const fabs = std.math.fabs;
    /// copysign with PyPowResult and PyValue support
    pub fn copysign(magnitude: anytype, sign_val: anytype) @TypeOf(magnitude) {
        const T = @TypeOf(magnitude);
        const S = @TypeOf(sign_val);
        const PyValueType = object_zig.PyValue;
        // Handle PyValue for sign value
        if (S == PyValueType) {
            const sign_f = switch (sign_val) {
                .float => |f| f,
                .int => |i| @as(f64, @floatFromInt(i)),
                .complex => |c| c.real, // Use real part for sign
                else => 0.0,
            };
            return std.math.copysign(magnitude, sign_f);
        }
        // Handle PyPowResult for sign value
        if (S == builtins.PyPowResult) {
            const sign_f = sign_val.toFloat(); // NaN for complex
            return std.math.copysign(magnitude, sign_f);
        }
        // Handle PyValue for magnitude
        if (T == PyValueType) {
            const mag_f = switch (magnitude) {
                .float => |f| f,
                .int => |i| @as(f64, @floatFromInt(i)),
                .complex => |c| c.real,
                else => 0.0,
            };
            return PyValueType{ .float = std.math.copysign(mag_f, sign_val) };
        }
        // Handle PyPowResult for magnitude
        if (T == builtins.PyPowResult) {
            const mag_f = magnitude.toFloat();
            return .{ .float_val = std.math.copysign(mag_f, sign_val) };
        }
        // Default to std.math.copysign
        return std.math.copysign(magnitude, sign_val);
    }
    pub const sin = std.math.sin;
    pub const cos = std.math.cos;
    pub const tan = std.math.tan;
    pub const asin = std.math.asin;
    pub const acos = std.math.acos;
    pub const atan = std.math.atan;
    pub const atan2 = std.math.atan2;
    pub const sinh = std.math.sinh;
    pub const cosh = std.math.cosh;
    pub const tanh = std.math.tanh;
    pub const asinh = std.math.asinh;
    pub const acosh = std.math.acosh;
    pub const atanh = std.math.atanh;
    pub const maxInt = std.math.maxInt;
    pub const minInt = std.math.minInt;
    pub const floatMax = std.math.floatMax;
    pub const floatMin = std.math.floatMin;
    pub const clamp = std.math.clamp;
    pub const sign = std.math.sign;

    /// isNan with PyPowResult and PyValue support
    pub fn isNan(value: anytype) bool {
        const T = @TypeOf(value);
        const PyValueType = object_zig.PyValue;
        // Handle PyValue tagged union
        if (T == PyValueType) {
            return switch (value) {
                .float => |f| std.math.isNan(f),
                .complex => |c| std.math.isNan(c.real) or std.math.isNan(c.imag),
                else => false,
            };
        }
        // Handle PyPowResult tagged union
        if (T == builtins.PyPowResult) {
            return value.isNan();
        }
        // Default to std.math.isNan for floats
        return std.math.isNan(value);
    }

    /// isInf with PyPowResult and PyValue support
    pub fn isInf(value: anytype) bool {
        const T = @TypeOf(value);
        const PyValueType = object_zig.PyValue;
        // Handle PyValue tagged union
        if (T == PyValueType) {
            return switch (value) {
                .float => |f| std.math.isInf(f),
                .complex => |c| std.math.isInf(c.real) or std.math.isInf(c.imag),
                else => false,
            };
        }
        // Handle PyPowResult tagged union
        if (T == builtins.PyPowResult) {
            return value.isInf();
        }
        // Default to std.math.isInf for floats
        return std.math.isInf(value);
    }

    /// isFinite with PyPowResult support
    pub fn isFinite(value: anytype) bool {
        return !isNan(value) and !isInf(value);
    }
};

// Re-export list operations for codegen
pub const PyList = @import("Objects/listobject.zig").PyList;

// Re-export whitespace for codegen
pub const isStringAllWhitespace = @import("runtime/whitespace.zig").isStringAllWhitespace;

// Re-export file operations for codegen
pub const PyFile = @import("Objects/fileobject.zig").PyFile;

// Re-export Fraction type for codegen (reduces monomorphization from inline struct)
pub const Fraction = @import("Objects/fraction.zig").Fraction;

// Re-export numeric operations for codegen
pub const addNum = @import("runtime/float_ops.zig").addNum;
pub const subtractNum = @import("runtime/float_ops.zig").subtractNum;
pub const intFromBytes = @import("runtime/int_ops.zig").intFromBytes;
pub const parseIntToBigInt = @import("runtime/int_ops.zig").parseIntToBigInt;
pub const parseIntUnicode = @import("runtime/int_ops.zig").parseIntUnicode;
pub const bigIntCompare = @import("runtime/builtins/types.zig").bigIntCompare;
pub const int__new__ = @import("runtime/int_ops.zig").int__new__;

// Re-export class operations for codegen
const class_ops = @import("runtime/builtins/operators.zig");
pub const pyEqual = class_ops.pyEqual;
pub const classInstanceEq = class_ops.classInstanceEq;
pub const classInstanceNe = class_ops.classInstanceNe;
pub const classInstanceLt = class_ops.classInstanceLt;
pub const classInstanceLe = class_ops.classInstanceLe;
pub const classInstanceGt = class_ops.classInstanceGt;
pub const classInstanceGe = class_ops.classInstanceGe;

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

/// Export Metal GPU acceleration module (macOS only)
/// Uses comptime checks for platform-specific compilation
pub const metal = @import("metal/metal.zig");

/// Export typing module types
pub const typing = @import("Lib/typing.zig");

/// Export dynamic attribute access stubs
const dynamic_attrs = @import("runtime/dynamic_attrs.zig");

/// Export PyValue for dynamic attributes
const object_zig = @import("Objects/object.zig");
pub const PyValue = object_zig.PyValue;
/// Convert any value to PyValue (O(n) instantiations instead of O(n²))
pub const toPyValue = object_zig.toPyValue;
/// HashMap with PyValue keys - for dicts with non-string keys (tuples, ints, bools, etc.)
pub const PyValueHashMap = object_zig.PyValueHashMap;
/// Hash context for PyValue keys (exposed for custom hashmap usage)
pub const PyValueHashContext = object_zig.PyValueHashContext;

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
// TypedClosure - explicit arg/return types, eliminates anytype monomorphization at call sites
pub const TypedClosure0 = closure_impl.TypedClosure0;
pub const TypedClosure1 = closure_impl.TypedClosure1;
pub const TypedClosure2 = closure_impl.TypedClosure2;
pub const TypedClosure3 = closure_impl.TypedClosure3;
pub const TypedClosure4 = closure_impl.TypedClosure4;
pub const TypedClosure5 = closure_impl.TypedClosure5;
pub const TypedClosure6 = closure_impl.TypedClosure6;
pub const TypedClosure7 = closure_impl.TypedClosure7;

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
pub const pyStrMod = runtime_format.pyMod; // String formatting (% on strings)
pub const pyMod = operator_ops.pyModNumeric; // Numeric modulo (returns f64)
pub const moduloRuntime = operator_ops.moduloRuntime; // Alias for aug_assign/comp_conditions
pub const pyFlooredModInt = operator_ops.pyFlooredModInt; // Integer modulo with Python floored semantics
pub const pyFloatMod = runtime_format.pyFloatMod;
pub const pyFloatFloorDiv = runtime_format.pyFloatFloorDiv;
pub const pyStringFormat = runtime_format.pyStringFormat;

/// Unified Format Dispatcher - ALL formatting should go through this
/// Usage:
///   pyFormatDispatch(alloc, value, .str, null)     // str(value)
///   pyFormatDispatch(alloc, value, .repr, null)    // repr(value)
///   pyFormatDispatch(alloc, value, .format, ".2f") // format(value, ".2f")
pub const format_dispatch = @import("Python/format_dispatch.zig");
pub const pyFormatDispatch = format_dispatch.pyFormatDispatch;
pub const FormatMode = format_dispatch.FormatMode;

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

// Full Python exception objects with __traceback__, __context__, __cause__
pub const PyException = exceptions.PyException;
pub const PyTraceback = exceptions.PyTraceback;
pub const getExceptionFull = exceptions.getExceptionFull;
pub const setExceptionFull = exceptions.setExceptionFull;

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
// Unified comparison: use PyValue.from(a).eql(PyValue.from(b)) or pyValueCompare(a, b)
pub const pyValueCompare = equality_mod.pyValueCompare;
// DEPRECATED: pyAnyEql - use pyValueCompare or PyValue.from().eql() instead
pub const pyAnyEql = equality_mod.pyAnyEql;
pub const pyIdentical = equality_mod.pyIdentical;
pub const iterSlice = equality_mod.iterSlice;
// PyValue-only equality (no monomorphization) - use for uncertain types
pub const pyValueEql = equality_mod.pyValueEql;
pub const intEql = equality_mod.intEql;
pub const floatEql = equality_mod.floatEql;
pub const stringEql = equality_mod.stringEql;
pub const boolEql = equality_mod.boolEql;

// PyValue-First comparison operators (compile ONCE - no monomorphization)
pub const pyValueLt = equality_mod.pyValueLt;
pub const pyValueLe = equality_mod.pyValueLe;
pub const pyValueGt = equality_mod.pyValueGt;
pub const pyValueGe = equality_mod.pyValueGe;
pub const pyValueNe = equality_mod.pyValueNe;

// Bool operations - re-exported from bool_ops.zig
pub const toBool = bool_ops.toBool;
pub const toBoolWithError = bool_ops.toBoolWithError;
pub const toBoolValue = bool_ops.toBoolValue;
pub const validateBoolReturn = bool_ops.validateBoolReturn;
pub const validateFloatReturn = bool_ops.validateFloatReturn;
pub const bool__new__ = bool_ops.bool__new__;
pub const boolFromBytes = bool_ops.boolFromBytes;

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
pub const PyNone_Check = cpython.PyNone_Check;
pub const PyBigInt_Check = cpython.PyBigInt_Check;
pub const PySet_Check = cpython.PySet_Check;
pub const PyFrozenSet_Check = cpython.PyFrozenSet_Check;
pub const PyAnySet_Check = cpython.PyAnySet_Check;
pub const PyDeque_Check = cpython.PyDeque_Check;
pub const PyBuiltinFunction = cpython.PyBuiltinFunction;
pub const PyBuiltinFunctionObject = cpython.PyBuiltinFunctionObject;
pub const PyBuiltinFunction_Type = cpython.PyBuiltinFunction_Type;
pub const PyBuiltinFunction_Check = cpython.PyBuiltinFunction_Check;
pub const BuiltinFn = cpython.BuiltinFn;
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
        threadlocal var small_list: std.ArrayListUnmanaged(PyValue) = .{};
        threadlocal var empty_list: std.ArrayListUnmanaged(PyValue) = .{};
    };

    if (PyList_Check(obj)) {
        const list_obj = cast(PyListObject, obj);
        const size = list_obj.ob_base.ob_size;
        if (size <= 0 or list_obj.ob_item == null) return .{ .list = &Static.empty_list };
        return convertItemsToValue(list_obj.ob_item.?, @intCast(size), &Static.buffer, &Static.small_list);
    }
    if (PyTuple_Check(obj)) {
        const tuple_obj = cast(PyTupleObject, obj);
        const size = tuple_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &Static.empty_list };
        return convertItemsToValue(@ptrCast(&tuple_obj.ob_item), @intCast(size), &Static.buffer, &Static.small_list);
    }
    return .{ .list = &Static.empty_list };
}

fn convertItemsToValue(items: [*]*PyObject, count: usize, buffer: *[64]PyValue, small_list: *std.ArrayListUnmanaged(PyValue)) PyValue {
    if (count <= 64) {
        for (0..count) |i| buffer[i] = pyObjectToPyValue(items[i]);
        // Point small_list.items to the static buffer slice
        small_list.items.ptr = buffer;
        small_list.items.len = count;
        small_list.capacity = count;
        return .{ .list = small_list };
    }
    // For large lists, allocate both the ArrayList and items on heap
    const list_ptr = std.heap.c_allocator.create(std.ArrayListUnmanaged(PyValue)) catch {
        // Fallback: use buffer for first 64 elements
        for (0..64) |i| buffer[i] = pyObjectToPyValue(items[i]);
        small_list.items.ptr = buffer;
        small_list.items.len = 64;
        small_list.capacity = 64;
        return .{ .list = small_list };
    };
    const heap_buffer = std.heap.c_allocator.alloc(PyValue, count) catch {
        std.heap.c_allocator.destroy(list_ptr);
        for (0..64) |i| buffer[i] = pyObjectToPyValue(items[i]);
        small_list.items.ptr = buffer;
        small_list.items.len = 64;
        small_list.capacity = 64;
        return .{ .list = small_list };
    };
    for (0..count) |i| heap_buffer[i] = pyObjectToPyValue(items[i]);
    list_ptr.* = .{ .items = heap_buffer, .capacity = count };
    return .{ .list = list_ptr };
}

/// Convert a single PyObject to PyValue
fn pyObjectToPyValue(obj: ?*PyObject) PyValue {
    const cast = pyobject_cast.cast;
    const o = obj orelse return .{ .none = {} };
    if (PyLong_Check(o)) return .{ .int = cast(PyLongObject, o).getValue() };
    if (PyFloat_Check(o)) return .{ .float = cast(PyFloatObject, o).ob_fval };
    if (PyBool_Check(o)) return .{ .bool = cast(PyBoolObject, o).getValue() };
    return .{ .ptr = o };
}

/// Extract value from PyObject for comparisons (returns f64)
pub fn pyObjectToValue(obj: *PyObject) f64 {
    const cast = pyobject_cast.cast;
    if (PyFloat_Check(obj)) return cast(PyFloatObject, obj).ob_fval;
    if (PyLong_Check(obj)) return @floatFromInt(cast(PyLongObject, obj).getValue());
    if (PyBool_Check(obj)) return @floatFromInt(@as(i64, @intFromBool(cast(PyBoolObject, obj).getValue())));
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
/// PyObject utility functions - imported from runtime/pyobject_utils.zig
const pyobject_utils = @import("runtime/pyobject_utils.zig");
pub const pyTruthy = pyobject_utils.pyTruthy;
pub const printPyObject = pyobject_utils.printPyObject;
pub const printList = pyobject_utils.printList;
pub const containsGeneric = pyobject_utils.containsGeneric;
pub const contains = pyobject_utils.contains;
pub const pyLen = pyobject_utils.pyLen;
pub const pyObjEqInt = pyobject_utils.pyObjEqInt;
pub const pyObjEqUnifiedInt = pyobject_utils.pyObjEqUnifiedInt;
pub const pyObjToInt = pyobject_utils.pyObjToInt;
pub const pyObjToFloat = pyobject_utils.pyObjToFloat;
pub const pyObjToBigInt = pyobject_utils.pyObjToBigInt;
pub const createObject = pyobject_utils.createObject;

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

// =============================================================================
// Additional runtime exports for codegen (systematic addition)
// =============================================================================

// Operator functions from builtins
pub const operatorEq = builtins.operatorEq;
pub const operatorNe = builtins.operatorNe;
pub const operatorLe = builtins.operatorLe;
pub const bigIntDivmod = builtins.bigIntDivmod;

// Set operations from builtins
pub const pySetAdd = builtins.pySetAdd;
pub const pySetRemove = builtins.pySetRemove;
pub const pySetClear = builtins.pySetClear;
pub const pySetPop = builtins.pySetPop;

// =============================================================================
// PyValue-First Container Operations (compile ONCE - no monomorphization)
// Use these for uncertain types to prevent compile explosion
// =============================================================================

// List operations
pub const pyListAppendPV = builtins.pyListAppendPV;
pub const pyListExtendPV = builtins.pyListExtendPV;
pub const pyListInsertPV = builtins.pyListInsertPV;
pub const pyListPopPV = builtins.pyListPopPV;
pub const pyListRemovePV = builtins.pyListRemovePV;
pub const pyListClearPV = builtins.pyListClearPV;
pub const pyListReversePV = builtins.pyListReversePV;
pub const pyListSortPV = builtins.pyListSortPV;
pub const listExtendIterable = builtins.listExtendIterable;

// Generic container operations
pub const pyLenPV = builtins.pyLenPV;
pub const pyContainsPV = builtins.pyContainsPV;
pub const pyGetItemPV = builtins.pyGetItemPV;
pub const pySetItemPV = builtins.pySetItemPV;

// Dict operations
pub const pyDictGetPV = builtins.pyDictGetPV;
pub const pyDictSetPV = builtins.pyDictSetPV;
pub const pyDictPopPV = builtins.pyDictPopPV;
pub const pyDictUpdatePV = builtins.pyDictUpdatePV;
pub const pyDictKeysPV = builtins.pyDictKeysPV;
pub const pyDictValuesPV = builtins.pyDictValuesPV;
pub const pyDictItemsPV = builtins.pyDictItemsPV;
pub const pyDictClearPV = builtins.pyDictClearPV;
pub const pyDictContainsPV = builtins.pyDictContainsPV;

// Set operations
pub const pySetAddPV = builtins.pySetAddPV;
pub const pySetRemovePV = builtins.pySetRemovePV;
pub const pySetDiscardPV = builtins.pySetDiscardPV;
pub const pySetPopPVFunc = builtins.pySetPopPVFunc;
pub const pySetClearPV = builtins.pySetClearPV;
pub const pySetContainsPV = builtins.pySetContainsPV;

// Additional float operations
pub const floatHex = @import("runtime/float_ops.zig").floatHex;

// Additional int operations
pub const pyIntFromAny = @import("runtime/int_ops.zig").pyIntFromAny;

// String concat from misc_utils
pub const concat = misc_utils.concat;

// Dynamic attribute operations
pub const dir_builtin = dynamic_attrs.dir_builtin;
pub const getattr_builtin = dynamic_attrs.getattr_builtin;
pub const structGetattr = dynamic_attrs.structGetattr;
pub const globals_builtin = dynamic_attrs.globals_builtin;
pub const getAttrDynamic = dynamic_attrs.getAttrDynamic;

// Container operations - setEqual already exported via container_ops
// Additional setEqual export for backward compat
pub const setEqual = container_ops.setEqual;

// Hashlib re-export for direct access (runtime.hashlib)
pub const hashlib = @import("Modules/_hashlib.zig");

// Datetime direct exports for runtime.datetime.Date, etc.
pub const datetime = @import("Lib/datetime.zig");

// Importlib direct export
pub const importlib = @import("Lib/importlib.zig");

// Inspect module direct export with generator state constants
pub const inspect = @import("Lib/inspect.zig");

/// Dynamic import for __import__() builtin
/// Uses the import system to load modules at runtime
pub fn dynamic_import(allocator: std.mem.Allocator, module_name: []const u8) !*PyObject {
    const import_mod = @import("Python/import.zig");
    const module = import_mod.importModule(allocator, module_name) catch |err| {
        // If import fails, return Py_None to allow graceful degradation
        // This matches Python's behavior of returning None for failed optional imports
        std.log.debug("dynamic_import failed for '{s}': {}", .{ module_name, err });
        return Py_None;
    };
    return @ptrCast(module);
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

// List conversion helpers - re-exported from list_conversion.zig
pub const listFromTuple = list_conversion_mod.listFromTuple;
pub const listFromString = list_conversion_mod.listFromString;
pub const listFromAny = list_conversion_mod.listFromAny;
pub const listEquals = list_conversion_mod.listEquals;

// Backwards compatibility exports for direct module access (e.g., runtime.json)
pub const json = @import("Lib/json.zig");
pub const jsonLoads = json.loads;
pub const jsonDumps = json.dumps;

// Re-export stdlib modules for codegen (runtime.re, runtime.sys, etc.)
pub const re = @import("Lib/re.zig");
pub const sys = @import("Lib/sys.zig");
pub const time = @import("Lib/time.zig");

// =============================================================================
// DCE-Friendly Namespace Exports
// =============================================================================
// These namespace structs enable Zig's dead code elimination by only pulling in
// modules when explicitly accessed (e.g., runtime.Lib.json instead of runtime.json).
// The direct pub const exports above are kept for backwards compatibility.

/// Lib/ directory modules - Python standard library implementations
/// This is a CURATED list of modules that are known to compile correctly.
/// For a full list of available modules, see Lib_exports.zig (run: zig build gen-stdlib)
pub const Lib = struct {
    // Python stdlib modules (alphabetical, underscores first)
    pub const __future__ = @import("Lib/__future__.zig");
    pub const _compression = @import("Lib/_compression.zig");
    pub const _testcapi = @import("Lib/_testcapi.zig");
    pub const _testconsole = @import("Lib/_testconsole.zig");
    pub const _testexternalinspection = @import("Lib/_testexternalinspection.zig");
    pub const sre_constants = @import("Lib/sre_constants.zig");
    pub const sre_compile = @import("Lib/sre_compile.zig");
    pub const sre_parse = @import("Lib/sre_parse.zig");

    pub const array = @import("Lib/array.zig");
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
    pub const stringprep = @import("Lib/stringprep.zig");
    pub const contextlib = @import("Lib/contextlib.zig");
    pub const copyreg = @import("Lib/copyreg.zig");
    pub const copy = @import("Lib/copy.zig");
    pub const textwrap = @import("Lib/textwrap.zig");
    pub const tempfile = if (is_freestanding) void else @import("Lib/tempfile.zig");
    pub const weakref = @import("Lib/weakref.zig");
    pub const warnings = @import("Lib/warnings.zig");
    pub const types = @import("Lib/types.zig");
    pub const operator = @import("Lib/operator.zig");
    pub const inspect = @import("Lib/inspect.zig");
    pub const doctest = @import("Lib/doctest.zig");
    pub const errno = @import("Lib/errno.zig");
    pub const importlib = @import("Lib/importlib.zig");
    pub const abc = @import("Lib/abc.zig");
    pub const _py_abc = @import("Lib/_py_abc.zig");
    pub const @"struct" = @import("Lib/struct.zig");
    pub const codecs = @import("Lib/codecs.zig");
    pub const encodings = @import("Lib/encodings.zig");
    pub const csv = @import("Lib/csv.zig");
    pub const heapq = @import("Lib/heapq.zig");
    pub const numbers = @import("Lib/numbers.zig");
    pub const stat = @import("Lib/stat.zig");
    pub const dataclasses = @import("Lib/dataclasses.zig");
    pub const pprint = @import("Lib/pprint.zig");
    pub const pytest = @import("Lib/pytest.zig");
    pub const difflib = @import("Lib/difflib.zig");
    pub const functools = @import("Lib/functools.zig");
    pub const random = @import("Lib/random.zig");
    pub const string = @import("Lib/string.zig");
    pub const fractions = @import("Lib/fractions.zig");
    pub const decimal = @import("Lib/decimal.zig");
    pub const @"enum" = @import("Lib/enum.zig");
    pub const shutil = if (is_freestanding) void else @import("Lib/shutil.zig");
    pub const subprocess = if (is_freestanding) void else @import("Lib/subprocess.zig");
    pub const http = if (is_freestanding) void else @import("Lib/http.zig");
    pub const websocket = if (is_freestanding) void else @import("Lib/websocket.zig");
    pub const asyncio = if (is_freestanding) void else @import("Lib/asyncio.zig");

    // Additional modules for comprehensive coverage (vetted modules only)
    pub const genericpath = @import("Lib/genericpath.zig");
    pub const filecmp = @import("Lib/filecmp.zig");
    pub const graphlib = @import("Lib/graphlib.zig");
    pub const sysconfig = @import("Lib/sysconfig.zig");
    pub const hashlib = @import("Lib/hashlib.zig");
    pub const fnmatch = @import("Lib/fnmatch.zig");
    pub const glob = @import("Lib/glob.zig");
    pub const bz2 = @import("Lib/bz2.zig");
    pub const lzma = @import("Lib/lzma.zig");
    pub const tarfile = @import("Lib/tarfile.zig");
    pub const zipfile = @import("Lib/zipfile.zig");
    pub const posixpath = @import("Lib/posixpath.zig");
    pub const ntpath = @import("Lib/ntpath.zig");
    pub const locale = @import("Lib/locale.zig");
    pub const bisect = @import("Lib/bisect.zig");
    pub const hmac = @import("Lib/hmac.zig");
    pub const uuid = @import("Lib/uuid.zig");
    pub const ipaddress = @import("Lib/ipaddress.zig");
    pub const quopri = @import("Lib/quopri.zig");
    pub const _hashlib = @import("Modules/_hashlib.zig");
    pub const traceback = @import("Lib/traceback.zig");
    pub const linecache = @import("Lib/linecache.zig");
    pub const keyword = @import("Lib/keyword.zig");
    pub const token = @import("Lib/token.zig");
    pub const tokenize = @import("Lib/tokenize.zig");
    pub const opcode = @import("Lib/opcode.zig");
    pub const symtable = @import("Lib/symtable.zig");
    pub const codeop = @import("Lib/codeop.zig");
    pub const profile = @import("Lib/profile.zig");
    pub const timeit = @import("Lib/timeit.zig");
    pub const trace = @import("Lib/trace.zig");
    pub const pyexpat = @import("Lib/pyexpat.zig");
    pub const socket = if (is_freestanding) void else @import("Lib/socket.zig");
    pub const threading = if (is_freestanding) void else @import("Lib/threading.zig");
    pub const queue = @import("Lib/queue.zig");
    pub const winreg = @import("Lib/winreg.zig"); // Windows registry (stubs on non-Windows)
    pub const msvcrt = @import("Lib/msvcrt.zig"); // MSVC runtime (stubs on non-Windows)
    pub const test_ = @import("Lib/test/support.zig"); // test is reserved, use test_

    // Modules added for CPython test compatibility
    pub const platform = @import("Lib/platform.zig");
    pub const secrets = @import("Lib/secrets.zig");
    pub const configparser = @import("Lib/configparser.zig");
    pub const argparse = @import("Lib/argparse.zig");
    pub const html = @import("Lib/html.zig");
    pub const xml = @import("Lib/xml.zig");
    pub const email = @import("Lib/email.zig");
    pub const signal = @import("Lib/signal.zig");
    pub const statistics = @import("Lib/statistics.zig");
    pub const gzip = @import("Lib/gzip.zig");
    pub const logging = @import("Lib/logging.zig");
    pub const _pylong = @import("Lib/_pylong.zig");
    pub const _pydecimal = @import("Lib/_pydecimal.zig");
    pub const _pyio = @import("Lib/_pyio.zig");
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

/// Python/ directory - CPython internal modules
pub const Python = struct {
    pub const ast_opt = @import("Python/ast_opt.zig");
    pub const formatter_unicode = @import("Python/formatter_unicode.zig");
    pub const cextapi = @import("Python/cextapi.zig");
    pub const importdl = @import("Python/importdl.zig");
    pub const dynload_shlib = @import("Python/dynload_shlib.zig");
    pub const capsule = @import("Python/capsule.zig");
    pub const ext_plugin = @import("Python/ext_plugin.zig");
};
