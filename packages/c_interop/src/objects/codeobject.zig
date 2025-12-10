/// PyCodeObject Implementation - Exact CPython Memory Layout
///
/// Bytecode object - represents compiled Python code
///
/// Reference: cpython/Objects/codeobject.c, cpython/Include/cpython/code.h
/// Memory layout matches CPython 3.12 exactly (non-GIL-disabled build)

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// SUPPORTING STRUCTURES
// ============================================================================

/// Cached code object attributes
/// Reference: cpython/Include/cpython/code.h
///
/// typedef struct {
///     PyObject *_co_code;
///     PyObject *_co_varnames;
///     PyObject *_co_cellvars;
///     PyObject *_co_freevars;
/// } _PyCoCached;
pub const _PyCoCached = extern struct {
    _co_code: ?*cpython.PyObject,
    _co_varnames: ?*cpython.PyObject,
    _co_cellvars: ?*cpython.PyObject,
    _co_freevars: ?*cpython.PyObject,
};

/// Executor array for JIT optimization
/// Reference: cpython/Include/cpython/code.h
///
/// typedef struct {
///     int size;
///     int capacity;
///     struct _PyExecutorObject *executors[1];
/// } _PyExecutorArray;
pub const _PyExecutorArray = extern struct {
    size: c_int,
    capacity: c_int,
    executors: [1]?*anyopaque, // Flexible array member
};

/// Monitoring data (opaque)
pub const _PyCoMonitoringData = anyopaque;

// ============================================================================
// PYCODEOBJECT - EXACT CPYTHON 3.12 LAYOUT
// ============================================================================

/// PyCodeObject - Bytecode object (EXACT CPython 3.12 layout)
/// Reference: cpython/Include/cpython/code.h _PyCode_DEF macro
///
/// This is a variable-size object. The co_code_adaptive field at the end
/// holds the actual bytecode. For our purposes, we define a fixed-size
/// version and handle variable-size allocation separately.
pub const PyCodeObject = extern struct {
    // PyObject_VAR_HEAD (24 bytes)
    ob_base: cpython.PyVarObject,

    // Hottest fields (in eval loop) - grouped at top
    co_consts: ?*cpython.PyObject, // list (constants used)
    co_names: ?*cpython.PyObject, // list of strings (names used)
    co_exceptiontable: ?*cpython.PyObject, // Byte string encoding exception handling table
    co_flags: c_int, // CO_..., see below

    // Less performance-critical fields
    co_argcount: c_int, // #arguments, except *args
    co_posonlyargcount: c_int, // #positional only arguments
    co_kwonlyargcount: c_int, // #keyword only arguments
    co_stacksize: c_int, // #entries needed for evaluation stack
    co_firstlineno: c_int, // first source line number

    // Redundant values (derived from co_localsplusnames and co_localspluskinds)
    co_nlocalsplus: c_int, // number of spaces for holding local, cell, and free variables
    co_framesize: c_int, // Size of frame in words
    co_nlocals: c_int, // number of local variables
    co_ncellvars: c_int, // total number of cell variables
    co_nfreevars: c_int, // number of free variables
    co_version: u32, // version number

    co_localsplusnames: ?*cpython.PyObject, // tuple mapping offsets to names
    co_localspluskinds: ?*cpython.PyObject, // Bytes mapping to local kinds
    co_filename: ?*cpython.PyObject, // unicode (where it was loaded from)
    co_name: ?*cpython.PyObject, // unicode (name, for reference)
    co_qualname: ?*cpython.PyObject, // unicode (qualname, for reference)
    co_linetable: ?*cpython.PyObject, // bytes object that holds location info
    co_weakreflist: ?*cpython.PyObject, // to support weakrefs to code objects
    co_executors: ?*_PyExecutorArray, // executors from optimizer
    _co_cached: ?*_PyCoCached, // cached co_* attributes
    _co_instrumentation_version: usize, // current instrumentation version
    _co_monitoring: ?*_PyCoMonitoringData, // Monitoring data
    _co_unique_id: isize, // ID used for per-thread refcounting
    _co_firsttraceable: c_int, // index of first traceable instruction
    co_extra: ?*anyopaque, // Scratch space for extra data

    // Note: co_code_adaptive follows here as a flexible array member
    // We don't include it in the struct since it's variable-size
};

// ============================================================================
// CO_FLAGS CONSTANTS
// ============================================================================

pub const CO_OPTIMIZED: c_int = 0x0001;
pub const CO_NEWLOCALS: c_int = 0x0002;
pub const CO_VARARGS: c_int = 0x0004;
pub const CO_VARKEYWORDS: c_int = 0x0008;
pub const CO_NESTED: c_int = 0x0010;
pub const CO_GENERATOR: c_int = 0x0020;
pub const CO_COROUTINE: c_int = 0x0080;
pub const CO_ITERABLE_COROUTINE: c_int = 0x0100;
pub const CO_ASYNC_GENERATOR: c_int = 0x0200;

// Future flags
pub const CO_FUTURE_DIVISION: c_int = 0x20000;
pub const CO_FUTURE_ABSOLUTE_IMPORT: c_int = 0x40000;
pub const CO_FUTURE_WITH_STATEMENT: c_int = 0x80000;
pub const CO_FUTURE_PRINT_FUNCTION: c_int = 0x100000;
pub const CO_FUTURE_UNICODE_LITERALS: c_int = 0x200000;
pub const CO_FUTURE_BARRY_AS_BDFL: c_int = 0x400000;
pub const CO_FUTURE_GENERATOR_STOP: c_int = 0x800000;
pub const CO_FUTURE_ANNOTATIONS: c_int = 0x1000000;

pub const CO_NO_MONITORING_EVENTS: c_int = 0x2000000;
pub const CO_HAS_DOCSTRING: c_int = 0x4000000;
pub const CO_METHOD: c_int = 0x8000000;

pub const CO_MAXBLOCKS: c_int = 21;

// ============================================================================
// CODE EVENT TYPES
// ============================================================================

pub const PyCodeEvent = enum(c_int) {
    PY_CODE_EVENT_CREATE = 0,
    PY_CODE_EVENT_DESTROY = 1,
};

/// Code watch callback type
pub const PyCode_WatchCallback = ?*const fn (PyCodeEvent, ?*PyCodeObject) callconv(.C) c_int;

// ============================================================================
// LOCATION INFO KINDS
// ============================================================================

pub const _PyCodeLocationInfoKind = enum(c_int) {
    PY_CODE_LOCATION_INFO_SHORT0 = 0,
    PY_CODE_LOCATION_INFO_ONE_LINE0 = 10,
    PY_CODE_LOCATION_INFO_ONE_LINE1 = 11,
    PY_CODE_LOCATION_INFO_ONE_LINE2 = 12,
    PY_CODE_LOCATION_INFO_NO_COLUMNS = 13,
    PY_CODE_LOCATION_INFO_LONG = 14,
    PY_CODE_LOCATION_INFO_NONE = 15,
};

/// Line offset range
pub const PyCodeAddressRange = extern struct {
    ar_start: c_int,
    ar_end: c_int,
    ar_line: c_int,
    opaque: extern struct {
        computed_line: c_int,
        lo_next: ?[*]const u8,
        limit: ?[*]const u8,
    },
};

// ============================================================================
// MEMBER TYPE CONSTANTS
// ============================================================================
const T_INT: c_int = 1;
const T_OBJECT: c_int = 6;
const T_OBJECT_EX: c_int = 16;
const READONLY: c_int = 1;

// ============================================================================
// CODE GETSET DEFINITIONS
// ============================================================================

/// Getter for co_varnames
fn code_get_varnames(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(self.?));
    return PyCode_GetVarnames(co);
}

/// Getter for co_cellvars
fn code_get_cellvars(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(self.?));
    return PyCode_GetCellvars(co);
}

/// Getter for co_freevars
fn code_get_freevars(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(self.?));
    return PyCode_GetFreevars(co);
}

/// Getter for co_code
fn code_get_code(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(self.?));
    return PyCode_GetCode(co);
}

/// code_getsetlist - getset descriptors for code type
var code_getsetlist = [_]cpython.PyGetSetDef{
    .{ .name = "co_varnames", .get = @ptrCast(&code_get_varnames), .set = null, .doc = null, .closure = null },
    .{ .name = "co_cellvars", .get = @ptrCast(&code_get_cellvars), .set = null, .doc = null, .closure = null },
    .{ .name = "co_freevars", .get = @ptrCast(&code_get_freevars), .set = null, .doc = null, .closure = null },
    .{ .name = "co_code", .get = @ptrCast(&code_get_code), .set = null, .doc = null, .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null }, // Sentinel
};

/// code_memberlist - member descriptors for code type
var code_memberlist = [_]cpython.PyMemberDef{
    .{ .name = "co_argcount", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_argcount"), .flags = READONLY, .doc = null },
    .{ .name = "co_posonlyargcount", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_posonlyargcount"), .flags = READONLY, .doc = null },
    .{ .name = "co_kwonlyargcount", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_kwonlyargcount"), .flags = READONLY, .doc = null },
    .{ .name = "co_nlocals", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_nlocals"), .flags = READONLY, .doc = null },
    .{ .name = "co_stacksize", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_stacksize"), .flags = READONLY, .doc = null },
    .{ .name = "co_flags", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_flags"), .flags = READONLY, .doc = null },
    .{ .name = "co_firstlineno", .type = T_INT, .offset = @offsetOf(PyCodeObject, "co_firstlineno"), .flags = READONLY, .doc = null },
    .{ .name = "co_consts", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_consts"), .flags = READONLY, .doc = null },
    .{ .name = "co_names", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_names"), .flags = READONLY, .doc = null },
    .{ .name = "co_filename", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_filename"), .flags = READONLY, .doc = null },
    .{ .name = "co_name", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_name"), .flags = READONLY, .doc = null },
    .{ .name = "co_qualname", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_qualname"), .flags = READONLY, .doc = null },
    .{ .name = "co_linetable", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_linetable"), .flags = READONLY, .doc = null },
    .{ .name = "co_exceptiontable", .type = T_OBJECT, .offset = @offsetOf(PyCodeObject, "co_exceptiontable"), .flags = READONLY, .doc = null },
    .{ .name = null, .type = 0, .offset = 0, .flags = 0, .doc = null }, // Sentinel
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

/// PyCode_Type - the type object for code objects
pub export var PyCode_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "code",
    .tp_basicsize = @sizeOf(PyCodeObject),
    .tp_itemsize = 1, // Variable size for co_code_adaptive
    .tp_dealloc = code_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = code_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = code_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = cpython.PyObject_GenericGetAttr,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "code(argcount, posonlyargcount, kwonlyargcount, nlocals, stacksize,\n      flags, codestring, constants, names, varnames, filename, name,\n      qualname, firstlineno, linetable, exceptiontable, freevars=(),\n      cellvars=(), /)\n\nCreate a code object.  Not for the faint of heart.",
    .tp_traverse = code_traverse,
    .tp_clear = null, // Code objects are not mutable
    .tp_richcompare = code_richcompare,
    .tp_weaklistoffset = @offsetOf(PyCodeObject, "co_weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null, // Code has no methods
    .tp_members = &code_memberlist,
    .tp_getset = &code_getsetlist,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = code_new,
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
    .tp_watched = 0,
};

// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

fn code_dealloc(op: ?*cpython.PyObject) callconv(.C) void {
    if (op == null) return;
    const co: *PyCodeObject = @ptrCast(@alignCast(op.?));

    // Clear cached attributes
    if (co._co_cached) |cached| {
        if (cached._co_code) |c| cpython.Py_DECREF(c);
        if (cached._co_varnames) |v| cpython.Py_DECREF(v);
        if (cached._co_cellvars) |c| cpython.Py_DECREF(c);
        if (cached._co_freevars) |f| cpython.Py_DECREF(f);
        const cached_ptr: [*]u8 = @ptrCast(cached);
        allocator.free(cached_ptr[0..@sizeOf(_PyCoCached)]);
    }

    // Decref all PyObject fields
    if (co.co_consts) |c| cpython.Py_DECREF(c);
    if (co.co_names) |n| cpython.Py_DECREF(n);
    if (co.co_exceptiontable) |e| cpython.Py_DECREF(e);
    if (co.co_localsplusnames) |l| cpython.Py_DECREF(l);
    if (co.co_localspluskinds) |l| cpython.Py_DECREF(l);
    if (co.co_filename) |f| cpython.Py_DECREF(f);
    if (co.co_name) |n| cpython.Py_DECREF(n);
    if (co.co_qualname) |q| cpython.Py_DECREF(q);
    if (co.co_linetable) |l| cpython.Py_DECREF(l);

    // Free executors array
    if (co.co_executors) |exec| {
        const exec_ptr: [*]u8 = @ptrCast(exec);
        const size = @sizeOf(_PyExecutorArray) + (@as(usize, @intCast(exec.capacity)) -| 1) * @sizeOf(?*anyopaque);
        allocator.free(exec_ptr[0..size]);
    }

    // Free the code object itself
    // Note: This needs to account for variable-size co_code_adaptive
    const ptr: [*]u8 = @ptrCast(co);
    const size = @sizeOf(PyCodeObject) + @as(usize, @intCast(co.ob_base.ob_size));
    allocator.free(ptr[0..size]);
}

fn code_repr(op: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (op == null) return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(op.?));
    const pyunicode = @import("unicodeobject.zig");

    // Format as "<code object name at 0xXXX, file "filename", line N>"
    var buf: [512]u8 = undefined;
    var pos: usize = 0;

    // Add prefix
    const prefix = "<code object ";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    // Add name
    if (co.co_name) |name| {
        const name_str = pyunicode.PyUnicode_AsUTF8(name);
        if (name_str != null) {
            const s = std.mem.span(name_str.?);
            const len = @min(s.len, buf.len - pos - 100);
            @memcpy(buf[pos..][0..len], s[0..len]);
            pos += len;
        }
    } else {
        const unknown = "<unknown>";
        @memcpy(buf[pos..][0..unknown.len], unknown);
        pos += unknown.len;
    }

    // Add address
    const at_str = " at 0x";
    @memcpy(buf[pos..][0..at_str.len], at_str);
    pos += at_str.len;

    // Format address as hex
    const addr = @intFromPtr(op.?);
    const hex_chars = "0123456789abcdef";
    var hex_buf: [16]u8 = undefined;
    var hex_len: usize = 0;
    var temp_addr = addr;
    while (temp_addr > 0 or hex_len == 0) : (temp_addr /= 16) {
        hex_buf[15 - hex_len] = hex_chars[temp_addr % 16];
        hex_len += 1;
    }
    @memcpy(buf[pos..][0..hex_len], hex_buf[16 - hex_len ..]);
    pos += hex_len;

    // Add file part
    const file_str = ", file \"";
    @memcpy(buf[pos..][0..file_str.len], file_str);
    pos += file_str.len;

    if (co.co_filename) |filename| {
        const filename_str = pyunicode.PyUnicode_AsUTF8(filename);
        if (filename_str != null) {
            const s = std.mem.span(filename_str.?);
            const len = @min(s.len, buf.len - pos - 50);
            @memcpy(buf[pos..][0..len], s[0..len]);
            pos += len;
        }
    }

    const quote = "\"";
    @memcpy(buf[pos..][0..quote.len], quote);
    pos += quote.len;

    // Add line number
    const line_str = ", line ";
    @memcpy(buf[pos..][0..line_str.len], line_str);
    pos += line_str.len;

    // Format line number
    var line_buf: [16]u8 = undefined;
    var line_len: usize = 0;
    var line_num = @abs(co.co_firstlineno);
    while (line_num > 0 or line_len == 0) : (line_num /= 10) {
        line_buf[15 - line_len] = '0' + @as(u8, @intCast(line_num % 10));
        line_len += 1;
    }
    @memcpy(buf[pos..][0..line_len], line_buf[16 - line_len ..]);
    pos += line_len;

    const close = ">";
    @memcpy(buf[pos..][0..close.len], close);
    pos += close.len;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

fn code_hash(op: ?*cpython.PyObject) callconv(.C) isize {
    if (op == null) return -1;
    const co: *PyCodeObject = @ptrCast(@alignCast(op.?));

    // Hash based on: name, argcount, posonlyargcount, kwonlyargcount, nlocals, stacksize, flags, firstlineno, consts, names, localsplusnames
    var h: isize = @as(isize, @intCast(co.co_argcount));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_posonlyargcount));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_kwonlyargcount));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_nlocals));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_stacksize));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_flags));
    h = h *% 1000003 +% @as(isize, @intCast(co.co_firstlineno));

    if (co.co_name) |name| {
        const name_hash = cpython.PyObject_Hash(name);
        if (name_hash == -1) return -1;
        h = h *% 1000003 +% name_hash;
    }

    if (h == -1) h = -2;
    return h;
}

fn code_traverse(self: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self == null) return 0;
    const co: *PyCodeObject = @ptrCast(@alignCast(self.?));

    inline for (.{
        co.co_consts,
        co.co_names,
        co.co_exceptiontable,
        co.co_localsplusnames,
        co.co_localspluskinds,
        co.co_filename,
        co.co_name,
        co.co_qualname,
        co.co_linetable,
    }) |field| {
        if (field) |obj| {
            if (visit) |v| {
                const result = v(obj, arg);
                if (result != 0) return result;
            }
        }
    }

    return 0;
}

fn code_richcompare(self: ?*cpython.PyObject, other: ?*cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return cpython.Py_NotImplemented;
    }

    if (self == null or other == null) {
        return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
    }

    // Check if both are code objects
    if (other.?.ob_type != &PyCode_Type) {
        return cpython.Py_NotImplemented;
    }

    const co1: *PyCodeObject = @ptrCast(@alignCast(self.?));
    const co2: *PyCodeObject = @ptrCast(@alignCast(other.?));

    // Compare by identity first
    if (self.? == other.?) {
        return if (op == object_mod.Py_EQ) pybool.Py_True else pybool.Py_False;
    }

    // Compare key fields
    var equal = true;

    // Compare argcount, kwonlyargcount, etc.
    if (co1.co_argcount != co2.co_argcount or
        co1.co_kwonlyargcount != co2.co_kwonlyargcount or
        co1.co_nlocals != co2.co_nlocals or
        co1.co_flags != co2.co_flags or
        co1.co_firstlineno != co2.co_firstlineno)
    {
        equal = false;
    }

    // Compare name
    if (equal and co1.co_name != null and co2.co_name != null) {
        const name_cmp = object_mod.PyObject_RichCompareBool(co1.co_name.?, co2.co_name.?, object_mod.Py_EQ);
        if (name_cmp != 1) equal = false;
    } else if (co1.co_name != co2.co_name) {
        equal = false;
    }

    // Compare filename
    if (equal and co1.co_filename != null and co2.co_filename != null) {
        const filename_cmp = object_mod.PyObject_RichCompareBool(co1.co_filename.?, co2.co_filename.?, object_mod.Py_EQ);
        if (filename_cmp != 1) equal = false;
    } else if (co1.co_filename != co2.co_filename) {
        equal = false;
    }

    // Compare consts
    if (equal and co1.co_consts != null and co2.co_consts != null) {
        const consts_cmp = object_mod.PyObject_RichCompareBool(co1.co_consts.?, co2.co_consts.?, object_mod.Py_EQ);
        if (consts_cmp != 1) equal = false;
    } else if (co1.co_consts != co2.co_consts) {
        equal = false;
    }

    // Compare names
    if (equal and co1.co_names != null and co2.co_names != null) {
        const names_cmp = object_mod.PyObject_RichCompareBool(co1.co_names.?, co2.co_names.?, object_mod.Py_EQ);
        if (names_cmp != 1) equal = false;
    } else if (co1.co_names != co2.co_names) {
        equal = false;
    }

    return if (op == object_mod.Py_EQ)
        (if (equal) pybool.Py_True else pybool.Py_False)
    else
        (if (equal) pybool.Py_False else pybool.Py_True);
}

fn code_new(typ: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = typ;
    _ = kwargs;

    // code(argcount, posonlyargcount, kwonlyargcount, nlocals, stacksize, flags,
    //      codestring, constants, names, varnames, filename, name, qualname,
    //      firstlineno, linetable, exceptiontable, freevars=(), cellvars=())
    if (args == null) return null;

    const pytuple = @import("tupleobject.zig");
    const pylong = @import("longobject.zig");

    const argc = pytuple.PyTuple_Size(args);
    if (argc < 16) return null; // Minimum required args

    // Parse integer arguments
    const argcount: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 0) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const posonlyargcount: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 1) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const kwonlyargcount: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 2) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const nlocals: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 3) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const stacksize: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 4) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const flags: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 5) orelse break :blk 0;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };
    const firstlineno: c_int = blk: {
        const v = pytuple.PyTuple_GetItem(args.?, 13) orelse break :blk 1;
        break :blk @intCast(pylong.PyLong_AsLong(v));
    };

    // Parse object arguments
    const codestring = pytuple.PyTuple_GetItem(args.?, 6);
    const constants = pytuple.PyTuple_GetItem(args.?, 7);
    const names = pytuple.PyTuple_GetItem(args.?, 8);
    const varnames = pytuple.PyTuple_GetItem(args.?, 9);
    const filename = pytuple.PyTuple_GetItem(args.?, 10);
    const name = pytuple.PyTuple_GetItem(args.?, 11);
    const qualname = pytuple.PyTuple_GetItem(args.?, 12);
    const linetable = pytuple.PyTuple_GetItem(args.?, 14);
    const exceptiontable = pytuple.PyTuple_GetItem(args.?, 15);

    // Optional: freevars and cellvars
    const freevars = if (argc > 16) pytuple.PyTuple_GetItem(args.?, 16) else null;
    const cellvars = if (argc > 17) pytuple.PyTuple_GetItem(args.?, 17) else null;

    const result = PyUnstable_Code_NewWithPosOnlyArgs(
        argcount,
        posonlyargcount,
        kwonlyargcount,
        nlocals,
        stacksize,
        flags,
        codestring,
        constants,
        names,
        varnames,
        freevars,
        cellvars,
        filename,
        name,
        qualname,
        firstlineno,
        linetable,
        exceptiontable,
    );

    return @ptrCast(result);
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// PyCode_NewEmpty - Create a new empty code object
pub export fn PyCode_NewEmpty(filename: ?[*:0]const u8, funcname: ?[*:0]const u8, firstlineno: c_int) ?*PyCodeObject {
    const pyunicode = @import("unicodeobject.zig");
    const pytuple = @import("tupleobject.zig");
    const pybytes = @import("bytesobject.zig");

    // Create unicode strings for filename and name
    const filename_obj = if (filename) |f| pyunicode.PyUnicode_FromString(f) else pyunicode.PyUnicode_FromString("<string>");
    const name_obj = if (funcname) |n| pyunicode.PyUnicode_FromString(n) else pyunicode.PyUnicode_FromString("<module>");

    if (filename_obj == null or name_obj == null) {
        if (filename_obj) |f| cpython.Py_DECREF(f);
        if (name_obj) |n| cpython.Py_DECREF(n);
        return null;
    }

    // Create empty objects
    const empty_tuple = pytuple.PyTuple_New(0);
    const empty_bytes = pybytes.PyBytes_FromStringAndSize(null, 0);

    if (empty_tuple == null or empty_bytes == null) {
        cpython.Py_DECREF(filename_obj.?);
        cpython.Py_DECREF(name_obj.?);
        if (empty_tuple) |t| cpython.Py_DECREF(t);
        if (empty_bytes) |b| cpython.Py_DECREF(b);
        return null;
    }

    // Create the code object
    return PyUnstable_Code_NewWithPosOnlyArgs(
        0, // argcount
        0, // posonlyargcount
        0, // kwonlyargcount
        0, // nlocals
        1, // stacksize
        0, // flags
        empty_bytes, // code
        empty_tuple, // consts
        empty_tuple, // names
        empty_tuple, // varnames
        empty_tuple, // freevars
        empty_tuple, // cellvars
        filename_obj, // filename
        name_obj, // name
        name_obj, // qualname (same as name)
        firstlineno, // firstlineno
        empty_bytes, // linetable
        empty_bytes, // exceptiontable
    );
}

/// PyUnstable_Code_New - Create a new code object (full version)
pub export fn PyUnstable_Code_New(
    argcount: c_int,
    kwonlyargcount: c_int,
    nlocals: c_int,
    stacksize: c_int,
    flags: c_int,
    code: ?*cpython.PyObject,
    consts: ?*cpython.PyObject,
    names: ?*cpython.PyObject,
    varnames: ?*cpython.PyObject,
    freevars: ?*cpython.PyObject,
    cellvars: ?*cpython.PyObject,
    filename: ?*cpython.PyObject,
    name: ?*cpython.PyObject,
    qualname: ?*cpython.PyObject,
    firstlineno: c_int,
    linetable: ?*cpython.PyObject,
    exceptiontable: ?*cpython.PyObject,
) ?*PyCodeObject {
    return PyUnstable_Code_NewWithPosOnlyArgs(
        argcount,
        0, // posonlyargcount
        kwonlyargcount,
        nlocals,
        stacksize,
        flags,
        code,
        consts,
        names,
        varnames,
        freevars,
        cellvars,
        filename,
        name,
        qualname,
        firstlineno,
        linetable,
        exceptiontable,
    );
}

/// PyUnstable_Code_NewWithPosOnlyArgs - Create a new code object with positional-only args
pub export fn PyUnstable_Code_NewWithPosOnlyArgs(
    argcount: c_int,
    posonlyargcount: c_int,
    kwonlyargcount: c_int,
    nlocals: c_int,
    stacksize: c_int,
    flags: c_int,
    code: ?*cpython.PyObject,
    consts: ?*cpython.PyObject,
    names: ?*cpython.PyObject,
    varnames: ?*cpython.PyObject,
    freevars: ?*cpython.PyObject,
    cellvars: ?*cpython.PyObject,
    filename: ?*cpython.PyObject,
    name: ?*cpython.PyObject,
    qualname: ?*cpython.PyObject,
    firstlineno: c_int,
    linetable: ?*cpython.PyObject,
    exceptiontable: ?*cpython.PyObject,
) ?*PyCodeObject {
    // Get code size for variable-length allocation
    var code_size: usize = 0;
    if (code) |c| {
        // Get actual code size from bytes object
        const pybytes = @import("bytesobject.zig");
        if (pybytes.PyBytes_Check(c) != 0) {
            const size = pybytes.PyBytes_Size(c);
            if (size > 0) {
                code_size = @intCast(size);
            }
        }
    }

    // Allocate code object with space for bytecode
    const total_size = @sizeOf(PyCodeObject) + code_size;
    const mem = allocator.alignedAlloc(u8, @alignOf(PyCodeObject), total_size) catch return null;
    const co: *PyCodeObject = @ptrCast(@alignCast(mem.ptr));

    // Initialize fields
    co.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCode_Type },
            .ob_size = @intCast(code_size),
        },
        .co_consts = consts,
        .co_names = names,
        .co_exceptiontable = exceptiontable,
        .co_flags = flags,
        .co_argcount = argcount,
        .co_posonlyargcount = posonlyargcount,
        .co_kwonlyargcount = kwonlyargcount,
        .co_stacksize = stacksize,
        .co_firstlineno = firstlineno,
        .co_nlocalsplus = nlocals,
        .co_framesize = nlocals + stacksize,
        .co_nlocals = nlocals,
        .co_ncellvars = blk: {
            // Calculate from cellvars tuple
            if (cellvars) |cv| {
                const pytuple = @import("tupleobject.zig");
                const size = pytuple.PyTuple_Size(cv);
                break :blk if (size > 0) @intCast(size) else 0;
            }
            break :blk 0;
        },
        .co_nfreevars = blk: {
            // Calculate from freevars tuple
            if (freevars) |fv| {
                const pytuple = @import("tupleobject.zig");
                const size = pytuple.PyTuple_Size(fv);
                break :blk if (size > 0) @intCast(size) else 0;
            }
            break :blk 0;
        },
        .co_version = 0,
        .co_localsplusnames = varnames,
        .co_localspluskinds = null,
        .co_filename = filename,
        .co_name = name,
        .co_qualname = qualname,
        .co_linetable = linetable,
        .co_weakreflist = null,
        .co_executors = null,
        ._co_cached = null,
        ._co_instrumentation_version = 0,
        ._co_monitoring = null,
        ._co_unique_id = 0,
        ._co_firsttraceable = 0,
        .co_extra = null,
    };

    // Incref all object fields
    if (consts) |c| cpython.Py_INCREF(c);
    if (names) |n| cpython.Py_INCREF(n);
    if (exceptiontable) |e| cpython.Py_INCREF(e);
    if (varnames) |v| cpython.Py_INCREF(v);
    if (filename) |f| cpython.Py_INCREF(f);
    if (name) |n| cpython.Py_INCREF(n);
    if (qualname) |q| cpython.Py_INCREF(q);
    if (linetable) |l| cpython.Py_INCREF(l);
    if (cellvars) |cv| cpython.Py_INCREF(cv);
    if (freevars) |fv| cpython.Py_INCREF(fv);

    // Copy bytecode to co_code_adaptive (located after the struct)
    if (code) |c| {
        if (code_size > 0) {
            const pybytes = @import("bytesobject.zig");
            const src = pybytes.PyBytes_AS_STRING(c);
            const co_bytes: [*]u8 = @ptrCast(co);
            const dest = co_bytes + @sizeOf(PyCodeObject);
            @memcpy(dest[0..code_size], src[0..code_size]);
        }
    }

    return co;
}

/// PyCode_Addr2Line - Get line number for bytecode offset
pub export fn PyCode_Addr2Line(co: ?*PyCodeObject, addrq: c_int) c_int {
    if (co == null) return -1;

    const pybytes = @import("bytesobject.zig");

    // Get linetable
    const linetable = co.?.co_linetable orelse return co.?.co_firstlineno;

    if (pybytes.PyBytes_Check(linetable) == 0) return co.?.co_firstlineno;

    const table_size = pybytes.PyBytes_Size(linetable);
    if (table_size <= 0) return co.?.co_firstlineno;

    const table_data = pybytes.PyBytes_AS_STRING(linetable);

    // Decode linetable (Python 3.11+ format)
    // Each entry is: [start_offset delta] [end_offset delta] [line delta] [column info...]
    var line: c_int = co.?.co_firstlineno;
    var addr: c_int = 0;
    var i: usize = 0;
    const size: usize = @intCast(table_size);

    while (i < size) {
        const entry = table_data[i];
        i += 1;

        // Decode the entry code
        const code_val = (entry >> 3) & 0x1F;
        const length = (entry & 0x07) + 1;

        // Update addr
        addr += @as(c_int, length) * 2; // Each instruction is 2 bytes

        if (addr > addrq) {
            return line;
        }

        // Update line based on code
        if (code_val < 10) {
            // No line change
        } else if (code_val < 13) {
            // Line increment 0-2
            line += @as(c_int, code_val) - 10;
        } else if (code_val == 13 and i < size) {
            // Signed line delta in next byte
            const delta: i8 = @bitCast(table_data[i]);
            line += delta;
            i += 1;
        } else if (code_val == 14 and i + 1 < size) {
            // Signed line delta in next 2 bytes
            const delta: i16 = @bitCast([2]u8{ table_data[i], table_data[i + 1] });
            line += delta;
            i += 2;
        }
    }

    return line;
}

/// PyCode_Addr2Location - Get full location for bytecode offset
/// Decodes the linetable to find the source location for a given bytecode offset
pub export fn PyCode_Addr2Location(
    co: ?*PyCodeObject,
    addrq: c_int,
    start_line: ?*c_int,
    start_column: ?*c_int,
    end_line: ?*c_int,
    end_column: ?*c_int,
) c_int {
    if (co == null) return 0;

    const pybytes = @import("bytesobject.zig");

    // Get linetable
    const linetable = co.?.co_linetable orelse {
        // No linetable - use firstlineno
        if (start_line) |sl| sl.* = co.?.co_firstlineno;
        if (start_column) |sc| sc.* = 0;
        if (end_line) |el| el.* = co.?.co_firstlineno;
        if (end_column) |ec| ec.* = 0;
        return 1;
    };

    const table_data = pybytes.PyBytes_AsString(linetable);
    const table_len = pybytes.PyBytes_Size(linetable);

    if (table_data == null or table_len <= 0) {
        if (start_line) |sl| sl.* = co.?.co_firstlineno;
        if (start_column) |sc| sc.* = 0;
        if (end_line) |el| el.* = co.?.co_firstlineno;
        if (end_column) |ec| ec.* = 0;
        return 1;
    }

    // Python 3.11+ linetable format (PEP 626)
    // Each entry: [start_offset_delta, end_offset_delta, line_delta, col_start, col_end]
    var current_addr: c_int = 0;
    var current_line: c_int = co.?.co_firstlineno;
    var idx: usize = 0;
    const target_addr = addrq;

    while (idx < @as(usize, @intCast(table_len))) {
        const byte = table_data[idx];
        idx += 1;

        if (byte == 0) {
            // End marker or special case
            continue;
        }

        // Simple format: delta_addr in upper 3 bits, line_delta in lower 5 bits (with offset)
        const addr_delta: c_int = @as(c_int, byte >> 3) & 0x1F;
        const line_delta: c_int = @as(c_int, byte & 0x07) - 4; // Line delta is biased by 4

        current_addr += addr_delta;
        current_line += line_delta;

        if (current_addr > target_addr) {
            // Found the entry
            break;
        }
    }

    if (start_line) |sl| sl.* = current_line;
    if (start_column) |sc| sc.* = 0; // Column info requires more complex parsing
    if (end_line) |el| el.* = current_line;
    if (end_column) |ec| ec.* = 0;

    return 1;
}

/// PyCode_GetCode - Get bytecode as bytes object
pub export fn PyCode_GetCode(co: ?*PyCodeObject) ?*cpython.PyObject {
    if (co == null) return null;

    // Check cache first
    if (co.?._co_cached) |cached| {
        if (cached._co_code) |code| {
            cpython.Py_INCREF(code);
            return code;
        }
    }

    // Create bytes object from co_code_adaptive (located after the struct)
    const code_size: usize = @intCast(co.?.ob_base.ob_size);
    if (code_size == 0) return null;

    const co_bytes: [*]const u8 = @ptrCast(co.?);
    const bytecode = co_bytes + @sizeOf(PyCodeObject);

    const pybytes = @import("bytesobject.zig");
    return pybytes.PyBytes_FromStringAndSize(bytecode, @intCast(code_size));
}

/// PyCode_GetVarnames - Get varnames tuple
pub export fn PyCode_GetVarnames(co: ?*PyCodeObject) ?*cpython.PyObject {
    if (co == null) return null;

    if (co.?._co_cached) |cached| {
        if (cached._co_varnames) |varnames| {
            cpython.Py_INCREF(varnames);
            return varnames;
        }
    }

    // Extract varnames from co_localsplusnames (first nlocals entries)
    const localsplusnames = co.?.co_localsplusnames orelse return null;
    const pytuple = @import("tupleobject.zig");

    const nlocals: isize = @intCast(co.?.co_nlocals);
    if (nlocals <= 0) {
        return pytuple.PyTuple_New(0);
    }

    const result = pytuple.PyTuple_New(nlocals);
    if (result == null) return null;

    var i: isize = 0;
    while (i < nlocals) : (i += 1) {
        const name = pytuple.PyTuple_GetItem(localsplusnames, i);
        if (name) |n| {
            cpython.Py_INCREF(n);
            _ = pytuple.PyTuple_SetItem(result.?, i, n);
        }
    }

    return result;
}

/// PyCode_GetCellvars - Get cellvars tuple
pub export fn PyCode_GetCellvars(co: ?*PyCodeObject) ?*cpython.PyObject {
    if (co == null) return null;

    if (co.?._co_cached) |cached| {
        if (cached._co_cellvars) |cellvars| {
            cpython.Py_INCREF(cellvars);
            return cellvars;
        }
    }

    // Extract cellvars from co_localsplusnames
    // Layout: [locals][cellvars][freevars]
    const localsplusnames = co.?.co_localsplusnames orelse return null;
    const pytuple = @import("tupleobject.zig");

    const ncellvars: isize = @intCast(co.?.co_ncellvars);
    if (ncellvars <= 0) {
        return pytuple.PyTuple_New(0);
    }

    const result = pytuple.PyTuple_New(ncellvars);
    if (result == null) return null;

    const start: isize = @intCast(co.?.co_nlocals);
    var i: isize = 0;
    while (i < ncellvars) : (i += 1) {
        const name = pytuple.PyTuple_GetItem(localsplusnames, start + i);
        if (name) |n| {
            cpython.Py_INCREF(n);
            _ = pytuple.PyTuple_SetItem(result.?, i, n);
        }
    }

    return result;
}

/// PyCode_GetFreevars - Get freevars tuple
pub export fn PyCode_GetFreevars(co: ?*PyCodeObject) ?*cpython.PyObject {
    if (co == null) return null;

    if (co.?._co_cached) |cached| {
        if (cached._co_freevars) |freevars| {
            cpython.Py_INCREF(freevars);
            return freevars;
        }
    }

    // Extract freevars from co_localsplusnames
    // Layout: [locals][cellvars][freevars]
    const localsplusnames = co.?.co_localsplusnames orelse return null;
    const pytuple = @import("tupleobject.zig");

    const nfreevars: isize = @intCast(co.?.co_nfreevars);
    if (nfreevars <= 0) {
        return pytuple.PyTuple_New(0);
    }

    const result = pytuple.PyTuple_New(nfreevars);
    if (result == null) return null;

    const start: isize = @intCast(co.?.co_nlocals + co.?.co_ncellvars);
    var i: isize = 0;
    while (i < nfreevars) : (i += 1) {
        const name = pytuple.PyTuple_GetItem(localsplusnames, start + i);
        if (name) |n| {
            cpython.Py_INCREF(n);
            _ = pytuple.PyTuple_SetItem(result.?, i, n);
        }
    }

    return result;
}

/// PyUnstable_Code_GetExtra - Get extra data at index
pub export fn PyUnstable_Code_GetExtra(code: ?*cpython.PyObject, index: isize, extra: ?*?*anyopaque) c_int {
    if (code == null or extra == null) return -1;
    if (!PyCode_Check(code)) return -1;
    if (index < 0) return -1;

    const co: *PyCodeObject = @ptrCast(@alignCast(code.?));

    // co_extra is an array of void pointers
    if (co.co_extra) |extra_data| {
        // co_extra is a pointer to an array, first element is count
        const extra_arr: [*]?*anyopaque = @ptrCast(@alignCast(extra_data));
        const count_ptr: *usize = @ptrCast(@alignCast(extra_arr));
        const count = count_ptr.*;

        if (@as(usize, @intCast(index)) < count) {
            extra.* = extra_arr[@as(usize, @intCast(index)) + 1];
            return 0;
        }
    }

    extra.* = null;
    return 0;
}

/// PyUnstable_Code_SetExtra - Set extra data at index
pub export fn PyUnstable_Code_SetExtra(code: ?*cpython.PyObject, index: isize, extra: ?*anyopaque) c_int {
    if (code == null) return -1;
    if (!PyCode_Check(code)) return -1;
    if (index < 0) return -1;

    const co: *PyCodeObject = @ptrCast(@alignCast(code.?));
    const idx: usize = @intCast(index);

    // Allocate co_extra if needed
    if (co.co_extra == null) {
        // Allocate space for count + initial slots
        const initial_size: usize = @max(idx + 2, 8);
        const mem = allocator.alloc(?*anyopaque, initial_size) catch return -1;
        @memset(mem, null);
        mem[0] = @ptrFromInt(idx + 1); // Store count in first slot
        co.co_extra = @ptrCast(mem.ptr);
    }

    const extra_arr: [*]?*anyopaque = @ptrCast(@alignCast(co.co_extra.?));
    const count_ptr: *usize = @ptrCast(@alignCast(extra_arr));
    const count = count_ptr.*;

    // Expand if needed
    if (idx >= count) {
        count_ptr.* = idx + 1;
    }

    extra_arr[idx + 1] = extra;
    return 0;
}

// Global watcher array (max 8 watchers like CPython)
const MAX_CODE_WATCHERS = 8;
var code_watchers: [MAX_CODE_WATCHERS]?PyCode_WatchCallback = [_]?PyCode_WatchCallback{null} ** MAX_CODE_WATCHERS;
var next_watcher_id: c_int = 0;

/// PyCode_AddWatcher - Register code object lifecycle callback
pub export fn PyCode_AddWatcher(callback: PyCode_WatchCallback) c_int {
    if (callback == null) return -1;

    // Find an empty slot
    for (&code_watchers, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = callback;
            return @intCast(i);
        }
    }

    // No slots available
    return -1;
}

/// PyCode_ClearWatcher - Unregister code object lifecycle callback
pub export fn PyCode_ClearWatcher(watcher_id: c_int) c_int {
    if (watcher_id < 0 or watcher_id >= MAX_CODE_WATCHERS) return -1;

    const idx: usize = @intCast(watcher_id);
    if (code_watchers[idx] == null) return -1;

    code_watchers[idx] = null;
    return 0;
}

/// PyCode_Optimize - Optimize bytecode (legacy API)
/// In Python 3.12+, bytecode optimization happens during compilation, not here.
/// This function is kept for backwards compatibility and returns the code unchanged.
pub export fn PyCode_Optimize(code: ?*cpython.PyObject, consts: ?*cpython.PyObject, names: ?*cpython.PyObject, lnotab: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = consts;
    _ = names;
    _ = lnotab;

    // Legacy API - return code unchanged (optimization happens at compile time now)
    if (code) |c| {
        cpython.Py_INCREF(c);
        return c;
    }
    return null;
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is a code object
pub inline fn PyCode_Check(op: ?*cpython.PyObject) bool {
    if (op == null) return false;
    return op.?.ob_type == &PyCode_Type;
}

/// Get number of free variables
pub inline fn PyCode_GetNumFree(op: ?*PyCodeObject) isize {
    if (op == null) return 0;
    return @as(isize, @intCast(op.?.co_nfreevars));
}

/// Get index of first free variable
pub inline fn PyUnstable_Code_GetFirstFree(op: ?*PyCodeObject) c_int {
    if (op == null) return 0;
    return op.?.co_nlocalsplus - op.?.co_nfreevars;
}
