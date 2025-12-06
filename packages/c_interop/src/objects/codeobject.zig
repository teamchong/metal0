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
    .tp_methods = null, // TODO: code_methods
    .tp_members = null, // TODO: code_memberlist
    .tp_getset = null, // TODO: code_getsetlist
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
    // TODO: Format as "<code object name at 0xXXX, file "filename", line N>"
    return null;
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
    _ = self;
    _ = other;
    _ = op;
    // TODO: Implement rich comparison
    return null;
}

fn code_new(typ: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = typ;
    _ = args;
    _ = kwargs;
    // TODO: Parse arguments and create code object
    return null;
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// PyCode_NewEmpty - Create a new empty code object
pub export fn PyCode_NewEmpty(filename: ?[*:0]const u8, funcname: ?[*:0]const u8, firstlineno: c_int) ?*PyCodeObject {
    _ = filename;
    _ = funcname;
    _ = firstlineno;
    // TODO: Implement empty code object creation
    return null;
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
        // Assuming code is a bytes object
        _ = c;
        // TODO: Get actual code size from bytes object
        code_size = 0;
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
        .co_ncellvars = 0, // TODO: Calculate from cellvars
        .co_nfreevars = 0, // TODO: Calculate from freevars
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

    _ = freevars;
    _ = cellvars;

    // Copy bytecode
    if (code) |c| {
        _ = c;
        // TODO: Copy bytecode to co_code_adaptive
    }

    return co;
}

/// PyCode_Addr2Line - Get line number for bytecode offset
pub export fn PyCode_Addr2Line(co: ?*PyCodeObject, addrq: c_int) c_int {
    if (co == null) return -1;
    _ = addrq;
    // TODO: Decode linetable to find line number
    return co.?.co_firstlineno;
}

/// PyCode_Addr2Location - Get full location for bytecode offset
pub export fn PyCode_Addr2Location(
    co: ?*PyCodeObject,
    addrq: c_int,
    start_line: ?*c_int,
    start_column: ?*c_int,
    end_line: ?*c_int,
    end_column: ?*c_int,
) c_int {
    if (co == null) return 0;
    _ = addrq;

    // TODO: Decode linetable for full location
    if (start_line) |sl| sl.* = co.?.co_firstlineno;
    if (start_column) |sc| sc.* = 0;
    if (end_line) |el| el.* = co.?.co_firstlineno;
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

    // TODO: Create bytes object from co_code_adaptive
    return null;
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

    // TODO: Extract varnames from co_localsplusnames
    return null;
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

    // TODO: Extract cellvars from co_localsplusnames
    return null;
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

    // TODO: Extract freevars from co_localsplusnames
    return null;
}

/// PyUnstable_Code_GetExtra - Get extra data at index
pub export fn PyUnstable_Code_GetExtra(code: ?*cpython.PyObject, index: isize, extra: ?*?*anyopaque) c_int {
    _ = code;
    _ = index;
    _ = extra;
    // TODO: Implement co_extra access
    return -1;
}

/// PyUnstable_Code_SetExtra - Set extra data at index
pub export fn PyUnstable_Code_SetExtra(code: ?*cpython.PyObject, index: isize, extra: ?*anyopaque) c_int {
    _ = code;
    _ = index;
    _ = extra;
    // TODO: Implement co_extra access
    return -1;
}

/// PyCode_AddWatcher - Register code object lifecycle callback
pub export fn PyCode_AddWatcher(callback: PyCode_WatchCallback) c_int {
    _ = callback;
    // TODO: Implement watcher registration
    return -1;
}

/// PyCode_ClearWatcher - Unregister code object lifecycle callback
pub export fn PyCode_ClearWatcher(watcher_id: c_int) c_int {
    _ = watcher_id;
    // TODO: Implement watcher unregistration
    return -1;
}

/// PyCode_Optimize - Optimize bytecode (legacy API)
pub export fn PyCode_Optimize(code: ?*cpython.PyObject, consts: ?*cpython.PyObject, names: ?*cpython.PyObject, lnotab: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = code;
    _ = consts;
    _ = names;
    _ = lnotab;
    // TODO: Implement bytecode optimization
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
