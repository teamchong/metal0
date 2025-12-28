/// C Extension API Shim
/// Provides CPython-compatible C API functions for extension modules.
///
/// This allows C extensions compiled for CPython to work with metal0's runtime
/// by providing compatible function signatures and behavior.
///
/// Reference: https://docs.python.org/3/c-api/

const std = @import("std");
const Allocator = std.mem.Allocator;
const cpython = @import("../cpython.zig");
const PyObject = cpython.PyObject;
const PyTypeObject = cpython.PyTypeObject;
const Py_ssize_t = cpython.Py_ssize_t;

// =============================================================================
// Error Handling
// =============================================================================

/// Thread-local error state (simplified - not per-interpreter)
var current_exception: ?*PyObject = null;
var current_exception_value: ?*PyObject = null;
var current_exception_traceback: ?*PyObject = null;

/// Set an exception with a string message
pub fn PyErr_SetString(exc_type: *PyObject, message: [*:0]const u8) void {
    _ = message;
    current_exception = exc_type;
    // In full implementation, would create exception instance with message
}

/// Set an exception object directly
pub fn PyErr_SetObject(exc_type: *PyObject, exc_value: *PyObject) void {
    current_exception = exc_type;
    current_exception_value = exc_value;
}

/// Check if an exception is set
pub fn PyErr_Occurred() ?*PyObject {
    return current_exception;
}

/// Clear the current exception
pub fn PyErr_Clear() void {
    current_exception = null;
    current_exception_value = null;
    current_exception_traceback = null;
}

/// Fetch and clear exception (returns borrowed references)
pub fn PyErr_Fetch(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    ptype.* = current_exception;
    pvalue.* = current_exception_value;
    ptraceback.* = current_exception_traceback;
    PyErr_Clear();
}

// =============================================================================
// Argument Parsing
// =============================================================================

/// Format character types for PyArg_ParseTuple
const FormatType = enum {
    /// 's' - string (const char*)
    string,
    /// 'i' - int
    int_val,
    /// 'l' - long
    long_val,
    /// 'L' - long long
    longlong_val,
    /// 'f' - float
    float_val,
    /// 'd' - double
    double_val,
    /// 'O' - PyObject*
    object,
    /// 'O!' - PyObject* with type check
    typed_object,
    /// 'n' - Py_ssize_t
    ssize,
    /// 'p' - bool (predicate)
    predicate,
    /// '|' - optional args separator
    optional_sep,
    /// ':' - function name for errors
    func_name,
    /// ';' - custom error message
    error_msg,
};

/// Parse a single format character
fn parseFormatChar(c: u8) ?FormatType {
    return switch (c) {
        's' => .string,
        'i' => .int_val,
        'l' => .long_val,
        'L' => .longlong_val,
        'f' => .float_val,
        'd' => .double_val,
        'O' => .object,
        'n' => .ssize,
        'p' => .predicate,
        '|' => .optional_sep,
        ':' => .func_name,
        ';' => .error_msg,
        else => null,
    };
}

/// PyArg_ParseTuple - Parse positional arguments
/// Returns 1 on success, 0 on failure (with exception set)
///
/// Simplified implementation - handles common format codes
pub fn PyArg_ParseTuple(args: *PyObject, format: [*:0]const u8, va_args: anytype) c_int {
    // Verify args is a tuple
    if (!cpython.PyTuple_Check(args)) {
        PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected tuple");
        return 0;
    }

    const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(args));
    const argc: usize = @intCast(tuple.ob_base.ob_size);

    var arg_idx: usize = 0;
    var fmt_idx: usize = 0;
    var optional = false;
    var va_idx: usize = 0;

    while (format[fmt_idx] != 0) : (fmt_idx += 1) {
        const c = format[fmt_idx];

        // Handle special markers
        if (c == '|') {
            optional = true;
            continue;
        }
        if (c == ':' or c == ';') {
            // Rest is function name or error message - stop parsing
            break;
        }

        // Skip whitespace
        if (c == ' ' or c == '\t') continue;

        // Check if we have more arguments
        if (arg_idx >= argc) {
            if (!optional) {
                PyErr_SetString(@ptrCast(&cpython.PyType_Type), "not enough arguments");
                return 0;
            }
            // Optional args not provided - done
            break;
        }

        // Get current argument
        const arg = tuple.ob_item[arg_idx];

        // Parse based on format character
        const success = switch (c) {
            's' => parseString(arg, va_args, va_idx),
            'i' => parseInt(arg, va_args, va_idx),
            'l' => parseLong(arg, va_args, va_idx),
            'd' => parseDouble(arg, va_args, va_idx),
            'O' => blk: {
                // Check for 'O!' (typed object)
                if (format[fmt_idx + 1] == '!') {
                    fmt_idx += 1;
                    break :blk parseTypedObject(arg, va_args, va_idx);
                }
                break :blk parseObject(arg, va_args, va_idx);
            },
            'n' => parseSsize(arg, va_args, va_idx),
            'p' => parsePredicate(arg, va_args, va_idx),
            else => {
                // Unknown format - skip
                true;
            },
        };

        if (!success) {
            return 0;
        }

        arg_idx += 1;
        va_idx += 1;
    }

    return 1;
}

// Individual type parsers
fn parseString(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (!cpython.PyUnicode_Check(arg)) {
        PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected string");
        return false;
    }
    const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(arg));
    // Store pointer to string data
    if (idx < va_args.len) {
        va_args[idx].* = str_obj.data;
    }
    return true;
}

fn parseInt(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (!cpython.PyLong_Check(arg)) {
        PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected int");
        return false;
    }
    const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(arg));
    if (idx < va_args.len) {
        va_args[idx].* = @intCast(long_obj.ob_digit);
    }
    return true;
}

fn parseLong(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (!cpython.PyLong_Check(arg)) {
        PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected int");
        return false;
    }
    const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(arg));
    if (idx < va_args.len) {
        va_args[idx].* = long_obj.ob_digit;
    }
    return true;
}

fn parseDouble(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (cpython.PyFloat_Check(arg)) {
        const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(arg));
        if (idx < va_args.len) {
            va_args[idx].* = float_obj.ob_fval;
        }
        return true;
    }
    if (cpython.PyLong_Check(arg)) {
        const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(arg));
        if (idx < va_args.len) {
            va_args[idx].* = @floatFromInt(long_obj.ob_digit);
        }
        return true;
    }
    PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected number");
    return false;
}

fn parseObject(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (idx < va_args.len) {
        va_args[idx].* = arg;
    }
    return true;
}

fn parseTypedObject(arg: *PyObject, va_args: anytype, idx: usize) bool {
    // For O!, we need type + pointer - simplified to just object for now
    if (idx < va_args.len) {
        va_args[idx].* = arg;
    }
    return true;
}

fn parseSsize(arg: *PyObject, va_args: anytype, idx: usize) bool {
    if (!cpython.PyLong_Check(arg)) {
        PyErr_SetString(@ptrCast(&cpython.PyType_Type), "expected int");
        return false;
    }
    const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(arg));
    if (idx < va_args.len) {
        va_args[idx].* = @intCast(long_obj.ob_digit);
    }
    return true;
}

fn parsePredicate(arg: *PyObject, va_args: anytype, idx: usize) bool {
    // Any object - check truthiness
    const is_true: c_int = if (cpython.PyBool_Check(arg)) blk: {
        const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(arg));
        break :blk if (bool_obj.ob_digit != 0) 1 else 0;
    } else if (cpython.PyLong_Check(arg)) blk: {
        const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(arg));
        break :blk if (long_obj.ob_digit != 0) 1 else 0;
    } else blk: {
        // Non-None objects are truthy
        break :blk if (arg != cpython.Py_None) 1 else 0;
    };

    if (idx < va_args.len) {
        va_args[idx].* = is_true;
    }
    return true;
}

/// PyArg_ParseTupleAndKeywords - Parse positional and keyword arguments
pub fn PyArg_ParseTupleAndKeywords(
    args: *PyObject,
    kwargs: ?*PyObject,
    format: [*:0]const u8,
    kwlist: [*]const [*:0]const u8,
    va_args: anytype,
) c_int {
    _ = kwargs;
    _ = kwlist;
    // Simplified - just parse positional args for now
    return PyArg_ParseTuple(args, format, va_args);
}

// =============================================================================
// Value Building
// =============================================================================

/// Build format types
const BuildType = enum {
    none, // N
    int_val, // i
    long_val, // l
    longlong_val, // L
    float_val, // f
    double_val, // d
    string, // s
    object, // O
    tuple_start, // (
    tuple_end, // )
    list_start, // [
    list_end, // ]
};

/// Py_BuildValue - Build a Python object from C values
/// Returns new reference or NULL on error
pub fn Py_BuildValue(allocator: Allocator, format: [*:0]const u8, args: anytype) ?*PyObject {
    var fmt_idx: usize = 0;
    var arg_idx: usize = 0;

    // Empty format returns None
    if (format[0] == 0) {
        cpython.Py_INCREF(cpython.Py_None);
        return cpython.Py_None;
    }

    // Single value
    const result = buildSingleValue(allocator, format, &fmt_idx, args, &arg_idx);
    return result;
}

fn buildSingleValue(allocator: Allocator, format: [*:0]const u8, fmt_idx: *usize, args: anytype, arg_idx: *usize) ?*PyObject {
    const c = format[fmt_idx.*];
    if (c == 0) return null;

    fmt_idx.* += 1;

    return switch (c) {
        'N', 'n' => cpython.Py_None,
        'i' => blk: {
            if (arg_idx.* < args.len) {
                const val: c_int = args[arg_idx.*];
                arg_idx.* += 1;
                break :blk buildLong(allocator, val);
            }
            break :blk null;
        },
        'l' => blk: {
            if (arg_idx.* < args.len) {
                const val: c_long = args[arg_idx.*];
                arg_idx.* += 1;
                break :blk buildLong(allocator, val);
            }
            break :blk null;
        },
        'd', 'f' => blk: {
            if (arg_idx.* < args.len) {
                const val: f64 = args[arg_idx.*];
                arg_idx.* += 1;
                break :blk buildFloat(allocator, val);
            }
            break :blk null;
        },
        's' => blk: {
            if (arg_idx.* < args.len) {
                const val: [*:0]const u8 = args[arg_idx.*];
                arg_idx.* += 1;
                break :blk buildString(allocator, val);
            }
            break :blk null;
        },
        'O' => blk: {
            if (arg_idx.* < args.len) {
                const obj: *PyObject = args[arg_idx.*];
                arg_idx.* += 1;
                cpython.Py_INCREF(obj);
                break :blk obj;
            }
            break :blk null;
        },
        '(' => buildTuple(allocator, format, fmt_idx, args, arg_idx),
        '[' => buildList(allocator, format, fmt_idx, args, arg_idx),
        else => null,
    };
}

fn buildLong(allocator: Allocator, val: anytype) ?*PyObject {
    const obj = allocator.create(cpython.PyLongObject) catch return null;
    obj.* = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &cpython.PyLong_Type,
            },
            .ob_size = 1,
        },
        .ob_digit = @intCast(val),
    };
    return @ptrCast(obj);
}

fn buildFloat(allocator: Allocator, val: f64) ?*PyObject {
    const obj = allocator.create(cpython.PyFloatObject) catch return null;
    obj.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &cpython.PyFloat_Type,
        },
        .ob_fval = val,
    };
    return @ptrCast(obj);
}

fn buildString(allocator: Allocator, val: [*:0]const u8) ?*PyObject {
    const len = std.mem.len(val);
    const obj = allocator.create(cpython.PyUnicodeObject) catch return null;
    obj.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &cpython.PyUnicode_Type,
        },
        .length = @intCast(len),
        .hash = -1,
        .state = 0,
        ._padding = 0,
        .data = val,
    };
    return @ptrCast(obj);
}

fn buildTuple(allocator: Allocator, format: [*:0]const u8, fmt_idx: *usize, args: anytype, arg_idx: *usize) ?*PyObject {
    // Count elements until ')'
    var count: usize = 0;
    var temp_idx = fmt_idx.*;
    while (format[temp_idx] != 0 and format[temp_idx] != ')') : (temp_idx += 1) {
        if (format[temp_idx] != ' ' and format[temp_idx] != ',') {
            count += 1;
        }
    }

    // Allocate tuple
    const tuple_size = @sizeOf(cpython.PyTupleObject) + count * @sizeOf(*PyObject);
    const mem = allocator.alignedAlloc(u8, @alignOf(cpython.PyTupleObject), tuple_size) catch return null;
    const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(mem.ptr));

    tuple.* = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &cpython.PyTuple_Type,
            },
            .ob_size = @intCast(count),
        },
        .ob_item = @ptrCast(@alignCast(mem.ptr + @sizeOf(cpython.PyTupleObject))),
    };

    // Fill elements
    var i: usize = 0;
    while (format[fmt_idx.*] != 0 and format[fmt_idx.*] != ')') {
        if (format[fmt_idx.*] == ' ' or format[fmt_idx.*] == ',') {
            fmt_idx.* += 1;
            continue;
        }
        if (buildSingleValue(allocator, format, fmt_idx, args, arg_idx)) |obj| {
            tuple.ob_item[i] = obj;
            i += 1;
        }
    }

    // Skip ')'
    if (format[fmt_idx.*] == ')') fmt_idx.* += 1;

    return @ptrCast(tuple);
}

fn buildList(allocator: Allocator, format: [*:0]const u8, fmt_idx: *usize, args: anytype, arg_idx: *usize) ?*PyObject {
    _ = allocator;
    _ = format;
    _ = fmt_idx;
    _ = args;
    _ = arg_idx;
    // Simplified - not implemented yet
    return null;
}

// =============================================================================
// Module Creation
// =============================================================================

/// PyModuleDef_Base - Base of module definition
pub const PyModuleDef_Base = extern struct {
    ob_base: PyObject,
    m_init: ?*const fn () callconv(.C) *PyObject,
    m_index: Py_ssize_t,
    m_copy: ?*PyObject,
};

/// PyMethodDef - Method definition for module methods
pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: ?*const fn (*PyObject, *PyObject) callconv(.C) *PyObject,
    ml_flags: c_int,
    ml_doc: ?[*:0]const u8,
};

/// Method flags
pub const METH_VARARGS: c_int = 0x0001;
pub const METH_KEYWORDS: c_int = 0x0002;
pub const METH_NOARGS: c_int = 0x0004;
pub const METH_O: c_int = 0x0008;
pub const METH_CLASS: c_int = 0x0010;
pub const METH_STATIC: c_int = 0x0020;

/// PyModuleDef - Module definition (CPython 3.x compatible)
pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base,
    m_name: ?[*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: Py_ssize_t,
    m_methods: ?[*]PyMethodDef,
    m_slots: ?*anyopaque,
    m_traverse: ?*anyopaque,
    m_clear: ?*anyopaque,
    m_free: ?*anyopaque,
};

/// PyModuleObject - Module instance
pub const PyModuleObject = extern struct {
    ob_base: PyObject,
    md_dict: ?*PyObject,
    md_def: ?*PyModuleDef,
    md_state: ?*anyopaque,
    md_weaklist: ?*PyObject,
    md_name: ?*PyObject,
};

/// Module type singleton
pub var PyModule_Type: PyTypeObject = cpython.makeTypeObject("module", @sizeOf(PyModuleObject), 0);

/// PyModule_Create2 - Create a new module object
pub fn PyModule_Create2(def: *PyModuleDef, module_api_version: c_int) ?*PyObject {
    _ = module_api_version;

    // Use global allocator for now
    const allocator = std.heap.c_allocator;

    const module = allocator.create(PyModuleObject) catch return null;
    module.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyModule_Type,
        },
        .md_dict = null,
        .md_def = def,
        .md_state = null,
        .md_weaklist = null,
        .md_name = null,
    };

    // Set module name if provided
    if (def.m_name) |name| {
        module.md_name = buildString(allocator, name);
    }

    // TODO: Add methods from m_methods

    return @ptrCast(module);
}

/// PyModule_Create - Create module (calls PyModule_Create2)
pub fn PyModule_Create(def: *PyModuleDef) ?*PyObject {
    return PyModule_Create2(def, 3); // Python 3.x API version
}

/// PyModule_AddObject - Add an object to module dict
pub fn PyModule_AddObject(module: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    _ = module;
    _ = name;
    _ = value;
    // TODO: Implement - add to module's md_dict
    return 0;
}

/// PyModule_AddIntConstant - Add an int constant to module
pub fn PyModule_AddIntConstant(module: *PyObject, name: [*:0]const u8, value: c_long) c_int {
    const allocator = std.heap.c_allocator;
    const obj = buildLong(allocator, value) orelse return -1;
    return PyModule_AddObject(module, name, obj);
}

/// PyModule_AddStringConstant - Add a string constant to module
pub fn PyModule_AddStringConstant(module: *PyObject, name: [*:0]const u8, value: [*:0]const u8) c_int {
    const allocator = std.heap.c_allocator;
    const obj = buildString(allocator, value) orelse return -1;
    return PyModule_AddObject(module, name, obj);
}

// =============================================================================
// Object Protocol
// =============================================================================

/// PyObject_GetAttrString - Get attribute by name
pub fn PyObject_GetAttrString(obj: *PyObject, name: [*:0]const u8) ?*PyObject {
    _ = obj;
    _ = name;
    // TODO: Implement attribute lookup
    return null;
}

/// PyObject_SetAttrString - Set attribute by name
pub fn PyObject_SetAttrString(obj: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    _ = obj;
    _ = name;
    _ = value;
    // TODO: Implement attribute setting
    return 0;
}

/// PyObject_Call - Call an object
pub fn PyObject_Call(callable: *PyObject, args: *PyObject, kwargs: ?*PyObject) ?*PyObject {
    _ = callable;
    _ = args;
    _ = kwargs;
    // TODO: Implement calling protocol
    return null;
}

/// PyObject_Repr - Get repr() of object
pub fn PyObject_Repr(obj: *PyObject) ?*PyObject {
    if (obj.ob_type.tp_repr) |repr_fn| {
        return repr_fn(obj);
    }
    return null;
}

/// PyObject_Str - Get str() of object
pub fn PyObject_Str(obj: *PyObject) ?*PyObject {
    if (obj.ob_type.tp_str) |str_fn| {
        return str_fn(obj);
    }
    return PyObject_Repr(obj);
}

// =============================================================================
// Sequence Protocol
// =============================================================================

/// PySequence_Length - Get length of sequence
pub fn PySequence_Length(seq: *PyObject) Py_ssize_t {
    return cpython.Py_SIZE(seq);
}

/// PySequence_GetItem - Get item from sequence
pub fn PySequence_GetItem(seq: *PyObject, index: Py_ssize_t) ?*PyObject {
    if (cpython.PyList_Check(seq)) {
        const list: *cpython.PyListObject = @ptrCast(@alignCast(seq));
        if (index >= 0 and index < list.ob_base.ob_size) {
            const item = list.ob_item[@intCast(index)];
            cpython.Py_INCREF(item);
            return item;
        }
    }
    if (cpython.PyTuple_Check(seq)) {
        const tuple: *cpython.PyTupleObject = @ptrCast(@alignCast(seq));
        if (index >= 0 and index < tuple.ob_base.ob_size) {
            const item = tuple.ob_item[@intCast(index)];
            cpython.Py_INCREF(item);
            return item;
        }
    }
    return null;
}

// =============================================================================
// Initialization
// =============================================================================

var initialized: bool = false;

/// Initialize the C extension API
pub fn init() void {
    if (initialized) return;

    // Fix up type object pointers
    PyModule_Type.ob_base.ob_base.ob_type = &cpython.PyType_Type;

    initialized = true;
}

/// Reset state (for testing)
pub fn reset() void {
    PyErr_Clear();
    initialized = false;
}

// =============================================================================
// Tests
// =============================================================================

test "error handling" {
    PyErr_Clear();
    try std.testing.expect(PyErr_Occurred() == null);

    PyErr_SetString(@ptrCast(&cpython.PyType_Type), "test error");
    try std.testing.expect(PyErr_Occurred() != null);

    PyErr_Clear();
    try std.testing.expect(PyErr_Occurred() == null);
}

test "build long" {
    const allocator = std.testing.allocator;
    const obj = buildLong(allocator, 42);
    try std.testing.expect(obj != null);
    defer allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(@alignCast(obj.?))));

    const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(obj.?));
    try std.testing.expectEqual(@as(i64, 42), long_obj.ob_digit);
}

test "build float" {
    const allocator = std.testing.allocator;
    const obj = buildFloat(allocator, 3.14);
    try std.testing.expect(obj != null);
    defer allocator.destroy(@as(*cpython.PyFloatObject, @ptrCast(@alignCast(obj.?))));

    const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(obj.?));
    try std.testing.expectEqual(@as(f64, 3.14), float_obj.ob_fval);
}
