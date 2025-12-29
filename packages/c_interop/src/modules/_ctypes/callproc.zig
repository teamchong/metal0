/// _ctypes/callproc - Foreign function call procedures
///
/// Implements CPython's Modules/_ctypes/callproc.c
/// Provides the mechanism for calling foreign functions
///
/// Reference: cpython/Modules/_ctypes/callproc.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// FFI TYPE TAGS
// ============================================================================

/// Type tags for argument conversion
pub const FFI_TYPE_VOID: u8 = 0;
pub const FFI_TYPE_INT: u8 = 1;
pub const FFI_TYPE_FLOAT: u8 = 2;
pub const FFI_TYPE_DOUBLE: u8 = 3;
pub const FFI_TYPE_LONGDOUBLE: u8 = 4;
pub const FFI_TYPE_UINT8: u8 = 5;
pub const FFI_TYPE_SINT8: u8 = 6;
pub const FFI_TYPE_UINT16: u8 = 7;
pub const FFI_TYPE_SINT16: u8 = 8;
pub const FFI_TYPE_UINT32: u8 = 9;
pub const FFI_TYPE_SINT32: u8 = 10;
pub const FFI_TYPE_UINT64: u8 = 11;
pub const FFI_TYPE_SINT64: u8 = 12;
pub const FFI_TYPE_POINTER: u8 = 13;
pub const FFI_TYPE_STRUCT: u8 = 14;

// ============================================================================
// ARGUMENT CONVERSION
// ============================================================================

/// Converted C argument value
const CValue = union {
    v_void: void,
    v_int: c_int,
    v_uint: c_uint,
    v_long: c_long,
    v_ulong: c_ulong,
    v_longlong: c_longlong,
    v_ulonglong: c_ulonglong,
    v_float: f32,
    v_double: f64,
    v_pointer: ?*anyopaque,
    v_char: u8,
    v_short: c_short,
    v_ushort: c_ushort,
    v_bytes: [16]u8,
};

/// Convert Python object to C value based on type tag
fn convertPyToC(obj: *cpython.PyObject, tag: u8) ?CValue {
    const pylong = @import("../../objects/longobject.zig");
    const pyfloat = @import("../../objects/floatobject.zig");
    const pybytes = @import("../../objects/bytesobject.zig");
    const pyunicode = @import("../../objects/unicodeobject.zig");
    const noneobject = @import("../../objects/noneobject.zig");

    switch (tag) {
        FFI_TYPE_VOID => return CValue{ .v_void = {} },

        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_int = @intCast(pylong.PyLong_AsLong(obj)) };
            }
            return null;
        },

        FFI_TYPE_UINT32 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_uint = @intCast(pylong.PyLong_AsUnsignedLong(obj)) };
            }
            return null;
        },

        FFI_TYPE_SINT64 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_longlong = pylong.PyLong_AsLongLong(obj) };
            }
            return null;
        },

        FFI_TYPE_UINT64 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_ulonglong = pylong.PyLong_AsUnsignedLongLong(obj) };
            }
            return null;
        },

        FFI_TYPE_SINT8 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_char = @intCast(pylong.PyLong_AsLong(obj) & 0xFF) };
            }
            return null;
        },

        FFI_TYPE_UINT8 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_char = @intCast(pylong.PyLong_AsUnsignedLong(obj) & 0xFF) };
            }
            return null;
        },

        FFI_TYPE_SINT16 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_short = @intCast(pylong.PyLong_AsLong(obj)) };
            }
            return null;
        },

        FFI_TYPE_UINT16 => {
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_ushort = @intCast(pylong.PyLong_AsUnsignedLong(obj)) };
            }
            return null;
        },

        FFI_TYPE_FLOAT => {
            if (pyfloat.PyFloat_Check(obj) != 0) {
                return CValue{ .v_float = @floatCast(pyfloat.PyFloat_AsDouble(obj)) };
            }
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_float = @floatCast(@as(f64, @floatFromInt(pylong.PyLong_AsLong(obj)))) };
            }
            return null;
        },

        FFI_TYPE_DOUBLE => {
            if (pyfloat.PyFloat_Check(obj) != 0) {
                return CValue{ .v_double = pyfloat.PyFloat_AsDouble(obj) };
            }
            if (pylong.PyLong_Check(obj)) {
                return CValue{ .v_double = @floatFromInt(pylong.PyLong_AsLong(obj)) };
            }
            return null;
        },

        FFI_TYPE_POINTER => {
            // None -> NULL
            if (obj == &noneobject._Py_NoneStruct) {
                return CValue{ .v_pointer = null };
            }
            // bytes -> char*
            if (pybytes.PyBytes_Check(obj) != 0) {
                const ptr = pybytes.PyBytes_AsString(obj);
                return CValue{ .v_pointer = @ptrCast(@constCast(ptr)) };
            }
            // str -> char* (UTF-8)
            if (pyunicode.PyUnicode_Check(obj) != 0) {
                const ptr = pyunicode.PyUnicode_AsUTF8(obj);
                return CValue{ .v_pointer = @ptrCast(@constCast(ptr)) };
            }
            // CData -> pointer to data
            if (isCDataObject(obj)) {
                const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(obj));
                return CValue{ .v_pointer = @ptrCast(cdata.b_ptr) };
            }
            // int -> pointer (for addresses)
            if (pylong.PyLong_Check(obj)) {
                const addr = pylong.PyLong_AsVoidPtr(obj);
                return CValue{ .v_pointer = addr };
            }
            return null;
        },

        else => return null,
    }
}

/// Check if object is a CData object
fn isCDataObject(obj: *cpython.PyObject) bool {
    // Check if the type has CDataObject in its hierarchy
    const tp = obj.ob_type;
    if (tp.tp_base) |base| {
        const base_name = std.mem.span(base.tp_name orelse "unknown");
        if (std.mem.indexOf(u8, base_name, "CData") != null) {
            return true;
        }
    }
    const type_name = std.mem.span(tp.tp_name orelse "unknown");
    return std.mem.indexOf(u8, type_name, "CData") != null or
        std.mem.indexOf(u8, type_name, "c_") != null or
        std.mem.indexOf(u8, type_name, "POINTER") != null or
        std.mem.indexOf(u8, type_name, "Array") != null;
}

/// Get FFI type tag from ctypes type object
fn getTypeTag(type_obj: ?*cpython.PyObject) u8 {
    if (type_obj == null) return FFI_TYPE_VOID;

    // Check StgDict for ffi_type info
    const stgdict = @import("stgdict.zig").PyObject_stgdict(type_obj);
    if (stgdict) |sd| {
        // Use size to determine type
        const size = sd.size;
        if (size == 0) return FFI_TYPE_VOID;
        if (size == 1) return FFI_TYPE_SINT8;
        if (size == 2) return FFI_TYPE_SINT16;
        if (size == 4) return FFI_TYPE_SINT32;
        if (size == 8) return FFI_TYPE_SINT64;
        return FFI_TYPE_POINTER; // Default for unknown sizes
    }

    // Check type name for hints
    const type_name = std.mem.span(type_obj.?.ob_type.tp_name orelse "unknown");
    if (std.mem.indexOf(u8, type_name, "c_void_p") != null) return FFI_TYPE_POINTER;
    if (std.mem.indexOf(u8, type_name, "c_char_p") != null) return FFI_TYPE_POINTER;
    if (std.mem.indexOf(u8, type_name, "c_wchar_p") != null) return FFI_TYPE_POINTER;
    if (std.mem.indexOf(u8, type_name, "c_int") != null) return FFI_TYPE_SINT32;
    if (std.mem.indexOf(u8, type_name, "c_uint") != null) return FFI_TYPE_UINT32;
    if (std.mem.indexOf(u8, type_name, "c_long") != null) return FFI_TYPE_SINT64;
    if (std.mem.indexOf(u8, type_name, "c_ulong") != null) return FFI_TYPE_UINT64;
    if (std.mem.indexOf(u8, type_name, "c_float") != null) return FFI_TYPE_FLOAT;
    if (std.mem.indexOf(u8, type_name, "c_double") != null) return FFI_TYPE_DOUBLE;
    if (std.mem.indexOf(u8, type_name, "c_char") != null) return FFI_TYPE_SINT8;
    if (std.mem.indexOf(u8, type_name, "c_byte") != null) return FFI_TYPE_SINT8;
    if (std.mem.indexOf(u8, type_name, "c_ubyte") != null) return FFI_TYPE_UINT8;
    if (std.mem.indexOf(u8, type_name, "c_short") != null) return FFI_TYPE_SINT16;
    if (std.mem.indexOf(u8, type_name, "c_ushort") != null) return FFI_TYPE_UINT16;
    if (std.mem.indexOf(u8, type_name, "c_longlong") != null) return FFI_TYPE_SINT64;
    if (std.mem.indexOf(u8, type_name, "c_ulonglong") != null) return FFI_TYPE_UINT64;

    return FFI_TYPE_POINTER; // Default
}

/// Convert C return value to Python object
fn convertCToPy(value: CValue, tag: u8) ?*cpython.PyObject {
    const pylong = @import("../../objects/longobject.zig");
    const pyfloat = @import("../../objects/floatobject.zig");
    const noneobject = @import("../../objects/noneobject.zig");

    switch (tag) {
        FFI_TYPE_VOID => {
            const none = &noneobject._Py_NoneStruct;
            cpython.Py_INCREF(none);
            return none;
        },

        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            return pylong.PyLong_FromLong(value.v_int);
        },

        FFI_TYPE_UINT32 => {
            return pylong.PyLong_FromUnsignedLong(value.v_uint);
        },

        FFI_TYPE_SINT64 => {
            return pylong.PyLong_FromLongLong(value.v_longlong);
        },

        FFI_TYPE_UINT64 => {
            return pylong.PyLong_FromUnsignedLongLong(value.v_ulonglong);
        },

        FFI_TYPE_SINT8, FFI_TYPE_UINT8 => {
            return pylong.PyLong_FromLong(@intCast(value.v_char));
        },

        FFI_TYPE_SINT16 => {
            return pylong.PyLong_FromLong(@intCast(value.v_short));
        },

        FFI_TYPE_UINT16 => {
            return pylong.PyLong_FromLong(@intCast(value.v_ushort));
        },

        FFI_TYPE_FLOAT => {
            return pyfloat.PyFloat_FromDouble(@floatCast(value.v_float));
        },

        FFI_TYPE_DOUBLE => {
            return pyfloat.PyFloat_FromDouble(value.v_double);
        },

        FFI_TYPE_POINTER => {
            if (value.v_pointer == null) {
                const none = &noneobject._Py_NoneStruct;
                cpython.Py_INCREF(none);
                return none;
            }
            return pylong.PyLong_FromVoidPtr(value.v_pointer);
        },

        else => {
            const none = &noneobject._Py_NoneStruct;
            cpython.Py_INCREF(none);
            return none;
        },
    }
}

// ============================================================================
// CALL IMPLEMENTATION
// ============================================================================

/// Maximum supported arguments for FFI calls
const MAX_ARGS = 32;

/// _ctypes_callproc - Call a C function
/// This is the core FFI mechanism for calling foreign functions
pub export fn _ctypes_callproc(
    pProc: ?*anyopaque,
    arguments: ?*cpython.PyObject,
    flags: c_int,
    argtypes: ?*cpython.PyObject,
    restype: ?*cpython.PyObject,
    checker: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    _ = flags;
    _ = checker;

    if (pProc == null) return null;

    const pytuple = @import("../../objects/tupleobject.zig");
    const noneobject = @import("../../objects/noneobject.zig");

    // Get argument count
    const argc: usize = if (arguments != null and pytuple.PyTuple_Check(arguments.?) != 0)
        @intCast(pytuple.PyTuple_Size(arguments.?))
    else
        0;

    if (argc > MAX_ARGS) return null;

    // Get return type tag
    const ret_tag = getTypeTag(restype);

    // Prepare argument values
    var arg_values: [MAX_ARGS]CValue = undefined;
    var arg_tags: [MAX_ARGS]u8 = undefined;

    for (0..argc) |i| {
        // Get argument object
        const arg_obj = pytuple.PyTuple_GetItem(arguments.?, @intCast(i));
        if (arg_obj == null) return null;

        // Get argument type
        var arg_type: ?*cpython.PyObject = null;
        if (argtypes != null and pytuple.PyTuple_Check(argtypes.?) != 0) {
            if (i < @as(usize, @intCast(pytuple.PyTuple_Size(argtypes.?)))) {
                arg_type = pytuple.PyTuple_GetItem(argtypes.?, @intCast(i));
            }
        }

        // Determine type tag
        arg_tags[i] = if (arg_type != null) getTypeTag(arg_type) else inferTypeTag(arg_obj.?);

        // Convert argument
        const converted = convertPyToC(arg_obj.?, arg_tags[i]);
        if (converted == null) return null;
        arg_values[i] = converted.?;
    }

    // Call the function based on argument count and types
    // We use a switch on argc to handle different arities
    const result: CValue = switch (argc) {
        0 => callFunc0(pProc.?, ret_tag),
        1 => callFunc1(pProc.?, ret_tag, arg_values[0], arg_tags[0]),
        2 => callFunc2(pProc.?, ret_tag, arg_values[0..2].*, arg_tags[0..2].*),
        3 => callFunc3(pProc.?, ret_tag, arg_values[0..3].*, arg_tags[0..3].*),
        4 => callFunc4(pProc.?, ret_tag, arg_values[0..4].*, arg_tags[0..4].*),
        5 => callFunc5(pProc.?, ret_tag, arg_values[0..5].*, arg_tags[0..5].*),
        6 => callFunc6(pProc.?, ret_tag, arg_values[0..6].*, arg_tags[0..6].*),
        else => {
            // For more args, use generic call
            return callFuncGeneric(pProc.?, ret_tag, arg_values[0..argc], arg_tags[0..argc]);
        },
    };

    // Convert result to Python
    const py_result = convertCToPy(result, ret_tag);
    if (py_result == null) {
        const none = &noneobject._Py_NoneStruct;
        cpython.Py_INCREF(none);
        return none;
    }

    return py_result;
}

/// Infer type tag from Python object
fn inferTypeTag(obj: *cpython.PyObject) u8 {
    const pylong = @import("../../objects/longobject.zig");
    const pyfloat = @import("../../objects/floatobject.zig");
    const pybytes = @import("../../objects/bytesobject.zig");
    const pyunicode = @import("../../objects/unicodeobject.zig");
    const noneobject = @import("../../objects/noneobject.zig");

    if (obj == &noneobject._Py_NoneStruct) return FFI_TYPE_POINTER;
    if (pylong.PyLong_Check(obj)) return FFI_TYPE_SINT64;
    if (pyfloat.PyFloat_Check(obj) != 0) return FFI_TYPE_DOUBLE;
    if (pybytes.PyBytes_Check(obj) != 0) return FFI_TYPE_POINTER;
    if (pyunicode.PyUnicode_Check(obj) != 0) return FFI_TYPE_POINTER;
    if (isCDataObject(obj)) return FFI_TYPE_POINTER;
    return FFI_TYPE_POINTER;
}

// ============================================================================
// FUNCTION CALL TRAMPOLINES
// ============================================================================

/// Call function with 0 arguments
fn callFunc0(proc: *anyopaque, ret_tag: u8) CValue {
    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn () callconv(.C) void = @ptrCast(@alignCast(proc));
            func();
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn () callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func() };
        },
        FFI_TYPE_UINT32 => {
            const func: *const fn () callconv(.C) c_uint = @ptrCast(@alignCast(proc));
            return CValue{ .v_uint = func() };
        },
        FFI_TYPE_SINT64 => {
            const func: *const fn () callconv(.C) c_longlong = @ptrCast(@alignCast(proc));
            return CValue{ .v_longlong = func() };
        },
        FFI_TYPE_UINT64 => {
            const func: *const fn () callconv(.C) c_ulonglong = @ptrCast(@alignCast(proc));
            return CValue{ .v_ulonglong = func() };
        },
        FFI_TYPE_FLOAT => {
            const func: *const fn () callconv(.C) f32 = @ptrCast(@alignCast(proc));
            return CValue{ .v_float = func() };
        },
        FFI_TYPE_DOUBLE => {
            const func: *const fn () callconv(.C) f64 = @ptrCast(@alignCast(proc));
            return CValue{ .v_double = func() };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn () callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func() };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 1 argument
fn callFunc1(proc: *anyopaque, ret_tag: u8, arg: CValue, arg_tag: u8) CValue {
    // Get argument as generic pointer-sized value
    const a0: usize = argToUsize(arg, arg_tag);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0) };
        },
        FFI_TYPE_SINT64 => {
            const func: *const fn (usize) callconv(.C) c_longlong = @ptrCast(@alignCast(proc));
            return CValue{ .v_longlong = func(a0) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0) };
        },
        FFI_TYPE_DOUBLE => {
            const func: *const fn (usize) callconv(.C) f64 = @ptrCast(@alignCast(proc));
            return CValue{ .v_double = func(a0) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 2 arguments
fn callFunc2(proc: *anyopaque, ret_tag: u8, args: [2]CValue, tags: [2]u8) CValue {
    const a0 = argToUsize(args[0], tags[0]);
    const a1 = argToUsize(args[1], tags[1]);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize, usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0, a1);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0, a1) };
        },
        FFI_TYPE_SINT64 => {
            const func: *const fn (usize, usize) callconv(.C) c_longlong = @ptrCast(@alignCast(proc));
            return CValue{ .v_longlong = func(a0, a1) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0, a1) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 3 arguments
fn callFunc3(proc: *anyopaque, ret_tag: u8, args: [3]CValue, tags: [3]u8) CValue {
    const a0 = argToUsize(args[0], tags[0]);
    const a1 = argToUsize(args[1], tags[1]);
    const a2 = argToUsize(args[2], tags[2]);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize, usize, usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0, a1, a2);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize, usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0, a1, a2) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize, usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0, a1, a2) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 4 arguments
fn callFunc4(proc: *anyopaque, ret_tag: u8, args: [4]CValue, tags: [4]u8) CValue {
    const a0 = argToUsize(args[0], tags[0]);
    const a1 = argToUsize(args[1], tags[1]);
    const a2 = argToUsize(args[2], tags[2]);
    const a3 = argToUsize(args[3], tags[3]);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize, usize, usize, usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0, a1, a2, a3);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize, usize, usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0, a1, a2, a3) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize, usize, usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0, a1, a2, a3) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 5 arguments
fn callFunc5(proc: *anyopaque, ret_tag: u8, args: [5]CValue, tags: [5]u8) CValue {
    const a0 = argToUsize(args[0], tags[0]);
    const a1 = argToUsize(args[1], tags[1]);
    const a2 = argToUsize(args[2], tags[2]);
    const a3 = argToUsize(args[3], tags[3]);
    const a4 = argToUsize(args[4], tags[4]);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize, usize, usize, usize, usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0, a1, a2, a3, a4);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize, usize, usize, usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0, a1, a2, a3, a4) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize, usize, usize, usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0, a1, a2, a3, a4) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Call function with 6 arguments
fn callFunc6(proc: *anyopaque, ret_tag: u8, args: [6]CValue, tags: [6]u8) CValue {
    const a0 = argToUsize(args[0], tags[0]);
    const a1 = argToUsize(args[1], tags[1]);
    const a2 = argToUsize(args[2], tags[2]);
    const a3 = argToUsize(args[3], tags[3]);
    const a4 = argToUsize(args[4], tags[4]);
    const a5 = argToUsize(args[5], tags[5]);

    switch (ret_tag) {
        FFI_TYPE_VOID => {
            const func: *const fn (usize, usize, usize, usize, usize, usize) callconv(.C) void = @ptrCast(@alignCast(proc));
            func(a0, a1, a2, a3, a4, a5);
            return CValue{ .v_void = {} };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => {
            const func: *const fn (usize, usize, usize, usize, usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            return CValue{ .v_int = func(a0, a1, a2, a3, a4, a5) };
        },
        FFI_TYPE_POINTER => {
            const func: *const fn (usize, usize, usize, usize, usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            return CValue{ .v_pointer = func(a0, a1, a2, a3, a4, a5) };
        },
        else => return CValue{ .v_void = {} },
    }
}

/// Generic call for more than 6 arguments - uses stack array
fn callFuncGeneric(proc: *anyopaque, ret_tag: u8, args: []CValue, tags: []u8) ?*cpython.PyObject {
    // For generic calls, we build an array and use inline asm or a trampoline
    // This is a simplified implementation that handles up to 16 args
    if (args.len > 16) return null;

    var arg_array: [16]usize = undefined;
    for (args, tags, 0..) |arg, tag, i| {
        arg_array[i] = argToUsize(arg, tag);
    }

    // Call with the array - simplified for common cases
    const result: CValue = switch (ret_tag) {
        FFI_TYPE_POINTER => blk: {
            const func: *const fn ([*]usize, usize) callconv(.C) ?*anyopaque = @ptrCast(@alignCast(proc));
            break :blk CValue{ .v_pointer = func(&arg_array, args.len) };
        },
        FFI_TYPE_INT, FFI_TYPE_SINT32 => blk: {
            const func: *const fn ([*]usize, usize) callconv(.C) c_int = @ptrCast(@alignCast(proc));
            break :blk CValue{ .v_int = func(&arg_array, args.len) };
        },
        else => CValue{ .v_void = {} },
    };

    return convertCToPy(result, ret_tag);
}

/// Convert CValue to usize for passing to functions
fn argToUsize(val: CValue, tag: u8) usize {
    return switch (tag) {
        FFI_TYPE_INT, FFI_TYPE_SINT32 => @bitCast(@as(isize, @intCast(val.v_int))),
        FFI_TYPE_UINT32 => @intCast(val.v_uint),
        FFI_TYPE_SINT64 => @bitCast(val.v_longlong),
        FFI_TYPE_UINT64 => @intCast(val.v_ulonglong),
        FFI_TYPE_SINT8, FFI_TYPE_UINT8 => @intCast(val.v_char),
        FFI_TYPE_SINT16 => @bitCast(@as(isize, @intCast(val.v_short))),
        FFI_TYPE_UINT16 => @intCast(val.v_ushort),
        FFI_TYPE_FLOAT => @bitCast(@as(u32, @bitCast(val.v_float))),
        FFI_TYPE_DOUBLE => @bitCast(val.v_double),
        FFI_TYPE_POINTER => @intFromPtr(val.v_pointer),
        else => 0,
    };
}

// ============================================================================
// PCARG METHODS
// ============================================================================

/// PyCArg_new - Create new PyCArg object
fn PyCArg_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.PyCArgObject), @sizeOf(ctypes.PyCArgObject)) catch return null;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(mem.ptr));

    carg.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCArg_Type },
        .pffi_type = null,
        .tag = 0,
        .value = undefined,
        .obj = null,
        .size = 0,
    };

    return @ptrCast(carg);
}

/// PyCArg_dealloc - Destructor
fn PyCArg_dealloc(self: ?*cpython.PyObject) callconv(.C) void {
    if (self == null) return;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(self.?));

    if (carg.obj) |p| p.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(carg);
    allocator.free(ptr[0..@sizeOf(ctypes.PyCArgObject)]);
}

/// PyCArg_repr - String representation
fn PyCArg_repr(self: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(self.?));

    const pyunicode = @import("../../objects/unicodeobject.zig");
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "<CArgObject tag={d} size={d}>", .{ carg.tag, carg.size }) catch return null;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(len.len));
}

// ============================================================================
// ADDITIONAL API
// ============================================================================

/// _ctypes_get_ffi_type - Get ffi_type for a ctypes type
pub export fn _ctypes_get_ffi_type(obj: ?*cpython.PyObject) callconv(.c) ?*anyopaque {
    if (obj == null) return null;

    // Get StgDict from type
    const stgdict = @import("stgdict.zig").PyObject_stgdict(obj);
    if (stgdict == null) return null;

    return stgdict.?.ffi_type_pointer;
}

/// ConvParam - Convert a Python object to a C parameter
pub export fn ConvParam(obj: ?*cpython.PyObject, index: c_int, pa: ?*ctypes.PyCArgObject) callconv(.c) c_int {
    if (obj == null or pa == null) return -1;
    _ = index;

    const pylong = @import("../../objects/longobject.zig");
    const pyfloat = @import("../../objects/floatobject.zig");
    const pybytes = @import("../../objects/bytesobject.zig");
    const noneobject = @import("../../objects/noneobject.zig");

    // Handle None -> NULL pointer
    if (obj.? == &noneobject._Py_NoneStruct) {
        pa.?.tag = FFI_TYPE_POINTER;
        pa.?.value = .{ .D = 0 };
        pa.?.size = @sizeOf(*anyopaque);
        return 0;
    }

    // Handle int -> c_long
    if (pylong.PyLong_Check(obj.?)) {
        pa.?.tag = FFI_TYPE_SINT64;
        pa.?.value.ll = pylong.PyLong_AsLongLong(obj.?);
        pa.?.size = @sizeOf(c_longlong);
        return 0;
    }

    // Handle float -> c_double
    if (pyfloat.PyFloat_Check(obj.?) != 0) {
        pa.?.tag = FFI_TYPE_DOUBLE;
        pa.?.value.d = pyfloat.PyFloat_AsDouble(obj.?);
        pa.?.size = @sizeOf(f64);
        return 0;
    }

    // Handle bytes -> char*
    if (pybytes.PyBytes_Check(obj.?) != 0) {
        pa.?.tag = FFI_TYPE_POINTER;
        const ptr = pybytes.PyBytes_AsString(obj.?);
        pa.?.value = .{ .D = 0 };
        @as(*?*anyopaque, @ptrCast(&pa.?.value)).* = @ptrCast(@constCast(ptr));
        pa.?.size = @sizeOf(*anyopaque);
        pa.?.obj = obj;
        obj.?.ob_refcnt += 1;
        return 0;
    }

    // Handle CData -> pointer to data
    if (isCDataObject(obj.?)) {
        const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(obj.?));
        pa.?.tag = FFI_TYPE_POINTER;
        pa.?.value = .{ .D = 0 };
        @as(*?*anyopaque, @ptrCast(&pa.?.value)).* = @ptrCast(cdata.b_ptr);
        pa.?.size = @sizeOf(*anyopaque);
        pa.?.obj = obj;
        obj.?.ob_refcnt += 1;
        return 0;
    }

    return -1;
}

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyCArg_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes.CArgObject",
    .tp_basicsize = @sizeOf(ctypes.PyCArgObject),
    .tp_itemsize = 0,
    .tp_dealloc = PyCArg_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = PyCArg_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "C argument object",
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
    .tp_new = PyCArg_new,
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
