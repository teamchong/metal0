/// C Interop module - exports all CPython stdlib C library wrappers
/// Also provides Python C API for loading C extension modules (numpy, pandas, etc.)
///
/// This is metal0's DROP-IN REPLACEMENT for libpython - we provide the C API ourselves.
const std = @import("std");

// CPython stdlib wrappers
pub const sqlite3 = @import("sqlite3.zig");
pub const zlib = @import("zlib.zig");
pub const ssl = @import("ssl.zig");

// CPython C API - our own implementation (drop-in replacement for libpython)
pub const cpython = @import("src/cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// MODULE LOADING VIA DLOPEN
// ============================================================================

/// Module cache - stores loaded C extension modules
var module_cache: ?std.StringHashMap(*cpython.PyObject) = null;

fn getModuleCache() *std.StringHashMap(*cpython.PyObject) {
    if (module_cache == null) {
        module_cache = std.StringHashMap(*cpython.PyObject).init(allocator);
    }
    return &module_cache.?;
}

/// Load a C extension module by name (e.g., "numpy", "pandas")
/// Returns cached module if already loaded
pub fn loadModule(module_name: []const u8) ?*cpython.PyObject {
    const cache = getModuleCache();

    // Check cache first
    if (cache.get(module_name)) |module| {
        return module;
    }

    // Try to load the extension module via dlopen
    const module = loadExtensionModule(module_name) orelse return null;

    // Cache it
    const name_copy = allocator.dupe(u8, module_name) catch return null;
    cache.put(name_copy, module) catch {
        allocator.free(name_copy);
        return null;
    };

    return module;
}

/// Load C extension module from .so/.dylib file
fn loadExtensionModule(name: []const u8) ?*cpython.PyObject {
    // Build search paths - check common locations
    const search_paths = [_][]const u8{
        ".venv/lib/python3.12/site-packages/",
        ".venv/lib/python3.11/site-packages/",
        "/usr/local/lib/python3.12/site-packages/",
        "/usr/local/lib/python3.11/site-packages/",
        "/opt/homebrew/lib/python3.12/site-packages/",
        "/opt/homebrew/lib/python3.11/site-packages/",
    };

    for (search_paths) |base_path| {
        if (tryLoadExtension(base_path, name)) |module| {
            return module;
        }
    }

    return null;
}

/// Try loading extension from specific path
fn tryLoadExtension(base_path: []const u8, name: []const u8) ?*cpython.PyObject {
    // Build path: base_path + name + extension
    var path_buf: [1024]u8 = undefined;

    // Try .cpython-312-darwin.so
    {
        var i: usize = 0;
        @memcpy(path_buf[i..][0..base_path.len], base_path);
        i += base_path.len;
        @memcpy(path_buf[i..][0..name.len], name);
        i += name.len;
        const ext = ".cpython-312-darwin.so";
        @memcpy(path_buf[i..][0..ext.len], ext);
        i += ext.len;
        path_buf[i] = 0;

        if (loadSharedLibrary(path_buf[0..i :0], name)) |module| {
            return module;
        }
    }

    // Try .cpython-311-darwin.so
    {
        var i: usize = 0;
        @memcpy(path_buf[i..][0..base_path.len], base_path);
        i += base_path.len;
        @memcpy(path_buf[i..][0..name.len], name);
        i += name.len;
        const ext = ".cpython-311-darwin.so";
        @memcpy(path_buf[i..][0..ext.len], ext);
        i += ext.len;
        path_buf[i] = 0;

        if (loadSharedLibrary(path_buf[0..i :0], name)) |module| {
            return module;
        }
    }

    // Try .so
    {
        var i: usize = 0;
        @memcpy(path_buf[i..][0..base_path.len], base_path);
        i += base_path.len;
        @memcpy(path_buf[i..][0..name.len], name);
        i += name.len;
        const ext = ".so";
        @memcpy(path_buf[i..][0..ext.len], ext);
        i += ext.len;
        path_buf[i] = 0;

        if (loadSharedLibrary(path_buf[0..i :0], name)) |module| {
            return module;
        }
    }

    // Try .dylib
    {
        var i: usize = 0;
        @memcpy(path_buf[i..][0..base_path.len], base_path);
        i += base_path.len;
        @memcpy(path_buf[i..][0..name.len], name);
        i += name.len;
        const ext = ".dylib";
        @memcpy(path_buf[i..][0..ext.len], ext);
        i += ext.len;
        path_buf[i] = 0;

        if (loadSharedLibrary(path_buf[0..i :0], name)) |module| {
            return module;
        }
    }

    return null;
}

// ============================================================================
// EXPORTED CPYTHON C API SYMBOLS
// These are exported so that C extension modules (.so files) can find them
// when loaded via dlopen. Required for numpy, pandas, etc.
// ============================================================================

export fn Py_INCREF(op: ?*cpython.PyObject) callconv(.c) void {
    if (op) |obj| {
        obj.ob_refcnt += 1;
    }
}

export fn Py_DECREF(op: ?*cpython.PyObject) callconv(.c) void {
    if (op) |obj| {
        obj.ob_refcnt -= 1;
        if (obj.ob_refcnt == 0) {
            if (obj.ob_type.tp_dealloc) |dealloc| {
                dealloc(obj);
            }
        }
    }
}

export fn PyErr_SetString(_: ?*anyopaque, _: ?[*:0]const u8) callconv(.c) void {
    // TODO: Implement proper error handling
}

export fn PyErr_Occurred() callconv(.c) ?*anyopaque {
    return null; // No error
}

export fn PyErr_Clear() callconv(.c) void {
    // Clear error state
}

export fn PyArg_ParseTuple(_: ?*cpython.PyObject, _: [*:0]const u8, ...) callconv(.c) c_int {
    // Stub - returns success
    return 1;
}

export fn PyArg_ParseTupleAndKeywords(_: ?*cpython.PyObject, _: ?*cpython.PyObject, _: [*:0]const u8, _: [*]?[*:0]const u8, ...) callconv(.c) c_int {
    return 1;
}

export fn PyBool_FromLong(v: c_long) callconv(.c) ?*cpython.PyObject {
    initTypes();
    if (v != 0) {
        return &_Py_TrueStruct;
    } else {
        return &_Py_FalseStruct;
    }
}

/// Load shared library and call PyInit function
fn loadSharedLibrary(path: [:0]const u8, name: []const u8) ?*cpython.PyObject {
    // RTLD_NOW = resolve all symbols immediately
    const handle = std.c.dlopen(path, .{ .NOW = true }) orelse return null;

    // Build init function name: PyInit_{name}
    var init_name_buf: [256]u8 = undefined;
    const init_name = std.fmt.bufPrintZ(&init_name_buf, "PyInit_{s}", .{name}) catch {
        _ = std.c.dlclose(handle);
        return null;
    };

    // Get init function pointer
    const init_func_ptr = std.c.dlsym(handle, init_name) orelse {
        _ = std.c.dlclose(handle);
        return null;
    };

    // Cast and call init function
    const init_func: *const fn () callconv(.c) ?*cpython.PyObject = @ptrCast(@alignCast(init_func_ptr));
    return init_func();
}

// ============================================================================
// PYOBJECT CREATION (Our implementations)
// ============================================================================

/// Python long object with simple i64 storage
const PyLongObject = extern struct {
    ob_base: cpython.PyVarObject,
    value: i64,
};

/// Python float object
const PyFloatObject = extern struct {
    ob_base: cpython.PyObject,
    ob_fval: f64,
};

/// Python Unicode (string) object - simplified
const PyUnicodeObject = extern struct {
    ob_base: cpython.PyObject,
    length: isize,
    hash: isize,
    // Flexible array of UTF-8 data follows
};

/// Python tuple object
const PyTupleObject = extern struct {
    ob_base: cpython.PyVarObject,
    // Items array follows (inline)
};

// Type objects (simplified - just need tp_name for basic functionality)
var PyLong_Type: cpython.PyTypeObject = undefined;
var PyFloat_Type: cpython.PyTypeObject = undefined;
var PyUnicode_Type: cpython.PyTypeObject = undefined;
var PyTuple_Type: cpython.PyTypeObject = undefined;

var types_initialized = false;

fn initTypes() void {
    if (types_initialized) return;

    // Complete type object initialization with ALL required fields
    PyLong_Type = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, .ob_size = 0 },
        .tp_name = "int",
        .tp_basicsize = @sizeOf(PyLongObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_LONG_SUBCLASS,
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
        .tp_watched = 0,
        .tp_versions_used = 0,
    };

    PyFloat_Type = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, .ob_size = 0 },
        .tp_name = "float",
        .tp_basicsize = @sizeOf(PyFloatObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
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
        .tp_watched = 0,
        .tp_versions_used = 0,
    };

    PyUnicode_Type = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, .ob_size = 0 },
        .tp_name = "str",
        .tp_basicsize = @sizeOf(PyUnicodeObject),
        .tp_itemsize = 1,
        .tp_dealloc = null,
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_UNICODE_SUBCLASS,
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
        .tp_watched = 0,
        .tp_versions_used = 0,
    };

    PyTuple_Type = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined }, .ob_size = 0 },
        .tp_name = "tuple",
        .tp_basicsize = @sizeOf(PyTupleObject),
        .tp_itemsize = @sizeOf(?*cpython.PyObject),
        .tp_dealloc = null,
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_TUPLE_SUBCLASS,
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
        .tp_watched = 0,
        .tp_versions_used = 0,
    };

    types_initialized = true;
}

/// Create PyLong from i64
fn PyLong_FromLongLong(value: i64) ?*cpython.PyObject {
    initTypes();

    const obj = allocator.create(PyLongObject) catch return null;
    obj.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyLong_Type },
            .ob_size = 1,
        },
        .value = value,
    };
    return @ptrCast(obj);
}

/// Create PyFloat from f64
fn PyFloat_FromDouble(value: f64) ?*cpython.PyObject {
    initTypes();

    const obj = allocator.create(PyFloatObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyFloat_Type },
        .ob_fval = value,
    };
    return @ptrCast(obj);
}

/// Create PyUnicode from string and size
fn PyUnicode_FromStringAndSize(str: ?[*]const u8, size: isize) ?*cpython.PyObject {
    initTypes();

    if (str == null or size < 0) return null;

    const usize_len: usize = @intCast(size);
    const total_size = @sizeOf(PyUnicodeObject) + usize_len + 1;

    const mem = allocator.alloc(u8, total_size) catch return null;
    const obj: *PyUnicodeObject = @ptrCast(@alignCast(mem.ptr));

    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyUnicode_Type },
        .length = size,
        .hash = -1, // Uncached
    };

    // Copy string data after the struct
    const data_ptr = mem.ptr + @sizeOf(PyUnicodeObject);
    @memcpy(data_ptr[0..usize_len], str.?[0..usize_len]);
    data_ptr[usize_len] = 0; // Null terminate

    return @ptrCast(obj);
}

/// Create empty tuple of given size
fn PyTuple_New(size: isize) ?*cpython.PyObject {
    initTypes();

    if (size < 0) return null;

    const usize_len: usize = @intCast(size);
    const items_size = usize_len * @sizeOf(?*cpython.PyObject);
    const total_size = @sizeOf(PyTupleObject) + items_size;

    const mem = allocator.alloc(u8, total_size) catch return null;
    @memset(mem, 0);

    const obj: *PyTupleObject = @ptrCast(@alignCast(mem.ptr));
    obj.* = .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyTuple_Type },
            .ob_size = size,
        },
    };

    return @ptrCast(obj);
}

/// Set item in tuple (steals reference to item)
fn PyTuple_SetItem(op: *cpython.PyObject, idx: isize, item: *cpython.PyObject) c_int {
    const tuple: *PyTupleObject = @ptrCast(@alignCast(op));
    const size = tuple.ob_base.ob_size;

    if (idx < 0 or idx >= size) return -1;

    // Get pointer to items array (after tuple header)
    const items_ptr: [*]?*cpython.PyObject = @ptrFromInt(@intFromPtr(tuple) + @sizeOf(PyTupleObject));
    items_ptr[@intCast(idx)] = item;

    return 0;
}

// Internal helpers that call the exported versions
fn incref(op: *cpython.PyObject) void {
    Py_INCREF(op);
}

fn decref(op: *cpython.PyObject) void {
    Py_DECREF(op);
}

// ============================================================================
// ATTRIBUTE ACCESS AND METHOD CALLING (Stubs for now)
// ============================================================================

/// Get attribute from object by name
/// For C extension objects, this needs to call into the type's tp_getattro
fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_getattro) |getattro| {
        // Need to create a PyUnicode for the name
        const name_len: isize = @intCast(std.mem.len(name));
        const name_obj = PyUnicode_FromStringAndSize(name, name_len) orelse return null;
        defer decref(name_obj);
        return getattro(obj, name_obj);
    }

    return null;
}

/// Call object with args tuple
fn PyObject_CallObject(callable: *cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(callable);

    if (type_obj.tp_call) |call_func| {
        return call_func(callable, args orelse PyTuple_New(0).?, null);
    }

    return null;
}

// ============================================================================
// PUBLIC API - callMethod and callModuleFunction
// ============================================================================

/// Call a method on a PyObject
/// Example: callMethod(arr, "sum", .{})
pub fn callMethod(
    obj: *cpython.PyObject,
    method_name: []const u8,
    args: anytype,
) ?*cpython.PyObject {
    // Get method from object
    const method_name_z = allocator.dupeZ(u8, method_name) catch return null;
    defer allocator.free(method_name_z);

    const method = PyObject_GetAttrString(obj, method_name_z) orelse return null;
    defer decref(method);

    // Build args tuple
    const args_tuple = buildArgsTuple(args) orelse return null;
    defer decref(args_tuple);

    // Call method
    return PyObject_CallObject(method, args_tuple);
}

/// Call a function on a module
/// Example: callModuleFunction("numpy", "array", .{list})
pub fn callModuleFunction(
    module_name: []const u8,
    func_name: []const u8,
    args: anytype,
) ?*cpython.PyObject {
    const module = loadModule(module_name) orelse return null;

    // Get function from module
    const func_name_z = allocator.dupeZ(u8, func_name) catch return null;
    defer allocator.free(func_name_z);

    const func = PyObject_GetAttrString(module, func_name_z) orelse return null;
    defer decref(func);

    // Build args tuple
    const args_tuple = buildArgsTuple(args) orelse return null;
    defer decref(args_tuple);

    // Call function
    return PyObject_CallObject(func, args_tuple);
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Boolean singletons
pub var _Py_TrueStruct: cpython.PyObject = .{ .ob_refcnt = 1, .ob_type = undefined };
pub var _Py_FalseStruct: cpython.PyObject = .{ .ob_refcnt = 1, .ob_type = undefined };

/// Build a tuple from Zig values for Python function calls
fn buildArgsTuple(args: anytype) ?*cpython.PyObject {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .@"struct") {
        return PyTuple_New(0);
    }

    const fields = args_info.@"struct".fields;
    const tuple = PyTuple_New(@intCast(fields.len)) orelse return null;

    inline for (fields, 0..) |field, i| {
        const value = @field(args, field.name);
        const py_value = toPyObject(value) orelse {
            decref(tuple);
            return null;
        };
        _ = PyTuple_SetItem(tuple, @intCast(i), py_value);
    }

    return tuple;
}

/// Convert Zig value to PyObject
fn toPyObject(value: anytype) ?*cpython.PyObject {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => PyLong_FromLongLong(@intCast(value)),
        .float, .comptime_float => PyFloat_FromDouble(@floatCast(value)),
        .bool => if (value) &_Py_TrueStruct else &_Py_FalseStruct,
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // String slice
                return PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
            }
            // Assume it's already a PyObject*
            return @ptrCast(@constCast(value));
        },
        .array => |arr_info| {
            // Convert array to Python list (simplified: just return first element for now)
            // TODO: Create PyList and populate
            if (arr_info.len > 0) {
                return toPyObject(value[0]);
            }
            return null;
        },
        else => null,
    };
}
