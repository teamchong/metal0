/// PyObject Utility Functions
/// Collection of utility functions for working with PyObjects

const std = @import("std");
const cpython = @import("../cpython.zig");
const pyobject_cast = @import("pyobject_cast.zig");
const legacy_compat = @import("legacy_compat.zig");
const bigint = @import("bigint");

// Import Objects modules
const pyint = @import("../Objects/intobject.zig");
const pyfloat = @import("../Objects/floatobject.zig");
const pylist = @import("../Objects/listobject.zig");
const pytuple = @import("../Objects/tupleobject.zig");
const pystring = @import("../Objects/unicodeobject.zig");
const dict_module = @import("../Objects/dictobject.zig");
const builtins = @import("builtins.zig");
const hashmap_helper = @import("utils.hashmap_helper");
const type_name = @import("type_name.zig");
const int_convert = @import("int_convert.zig");
const type_builtins = @import("type_builtins.zig");
const float_ops = @import("float_ops.zig");
const format_ops = @import("format_ops.zig");
const container_ops = @import("container_ops.zig");
const misc_utils = @import("misc_utils.zig");
const equality_mod = @import("equality.zig");

pub const PyObject = cpython.PyObject;
pub const PyLongObject = cpython.PyLongObject;
pub const PyFloatObject = cpython.PyFloatObject;
pub const PyBoolObject = cpython.PyBoolObject;
pub const PyListObject = cpython.PyListObject;
pub const PyTupleObject = cpython.PyTupleObject;
pub const PyDictObject = cpython.PyDictObject;
pub const PyUnicodeObject = cpython.PyUnicodeObject;
pub const PyBytesObject = cpython.PyBytesObject;
pub const Py_TYPE = cpython.Py_TYPE;
pub const getTypeId = legacy_compat.getTypeId;
pub const BigInt = bigint.BigInt;
pub const PyDict_Check = cpython.PyDict_Check;
pub const PyList_Check = cpython.PyList_Check;
pub const PyBigIntObject = cpython.PyBigIntObject;

// Access type methods from imported modules
const PyTuple = pytuple.PyTuple;
const PyInt = pyint.PyInt;
const NativeList = pylist.NativeList;
const PyString = pystring.PyString;
const PyList = pylist.PyList;
const PyDict = dict_module.PyDict;

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

// Re-export float operations (float_ops imported at top of file)
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
pub const int_ops = @import("int_ops.zig");
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
    return container_ops.containsGeneric(NativeList, equality_mod.pyAnyEql, container, item);
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

/// Compare PyObject with UnifiedInt (for eval() result comparisons with potentially large integers)
pub fn pyObjEqUnifiedInt(obj: *PyObject, value: anytype, allocator: std.mem.Allocator) bool {
    const UnifiedInt = @import("../Objects/pyint.zig").UnifiedInt;
    const V = @TypeOf(value);

    // Handle UnifiedInt value
    const unified_val: UnifiedInt = if (V == UnifiedInt)
        value
    else if (V == i64 or V == comptime_int)
        UnifiedInt.fromI64(value)
    else
        @compileError("pyObjEqUnifiedInt: unsupported value type");

    const type_id = getTypeId(obj);
    return switch (type_id) {
        .int => {
            const obj_val = PyInt.getValue(obj);
            return unified_val.eql(UnifiedInt.fromI64(obj_val), allocator) catch false;
        },
        .bigint => {
            // BigInt is already imported at module level
            const cast = pyobject_cast.cast;
            const big_obj = cast(PyBigIntObject, obj);
            const obj_unified = UnifiedInt.fromBigIntValue(allocator, &big_obj.value) catch return false;
            return unified_val.eql(obj_unified, allocator) catch false;
        },
        else => false,
    };
}

/// Extract int value from PyObject (for eval() results)
pub fn pyObjToInt(obj: *PyObject) i64 {
    return if (getTypeId(obj) == .int) PyInt.getValue(obj) else 0;
}

/// Extract float value from PyObject (for eval() results)
pub fn pyObjToFloat(obj: *PyObject) f64 {
    return switch (getTypeId(obj)) {
        .float => pyobject_cast.cast(PyFloatObject, obj).ob_fval,
        .int => @floatFromInt(PyInt.getValue(obj)),
        else => 0.0,
    };
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
