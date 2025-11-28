/// PyAOT Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const pyint = @import("pyint.zig");
const pyfloat = @import("pyfloat.zig");
const pybool = @import("pybool.zig");
const pylist = @import("pylist.zig");
const pystring = @import("pystring.zig");
const pytuple = @import("pytuple.zig");
const pyfile = @import("pyfile.zig");

/// Export string utilities for native codegen
pub const string_utils = @import("string_utils.zig");

/// Export AST executor for eval() support
pub const ast_executor = @import("ast_executor.zig");

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

/// Export format utilities from runtime_format.zig
const runtime_format = @import("runtime_format.zig");
pub const formatAny = runtime_format.formatAny;
pub const formatUnknown = runtime_format.formatUnknown;
pub const formatFloat = runtime_format.formatFloat;
pub const formatPyObject = runtime_format.formatPyObject;
pub const PyDict_AsString = runtime_format.PyDict_AsString;
pub const printValue = runtime_format.printValue;

/// Python exception types mapped to Zig errors
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
};

/// Python object representation
pub const PyObject = struct {
    ref_count: usize,
    type_id: TypeId,
    data: *anyopaque,
    /// Optional arena pointer - if set, this object was allocated from an arena
    /// When ref_count hits 0 on a root object with arena_ptr, free the entire arena
    arena_ptr: ?*anyopaque = null,

    pub const TypeId = enum {
        int,
        float,
        bool,
        string,
        list,
        tuple,
        dict,
        none,
        file, // File handle (open())
        numpy_array, // NumPy array support for C interop
        bool_array, // Boolean array (numpy comparison result)
        regex, // Compiled regex pattern
    };

    /// Value type for initializing lists/tuples from literals
    pub const Value = struct {
        int: i64,
    };
};

/// Reference counting
pub fn incref(obj: *PyObject) void {
    obj.ref_count += 1;
}

pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    if (obj.ref_count == 0) {
        std.debug.print("WARNING: Attempting to decref object with ref_count already 0\n", .{});
        return;
    }
    obj.ref_count -= 1;
    if (obj.ref_count == 0) {
        // Check if this is an arena-allocated root object
        if (obj.arena_ptr) |arena_ptr| {
            // This is a JSON arena root - free entire arena at once
            // All child objects are in the arena, no need to recurse
            const JsonArena = @import("json/arena.zig").JsonArena;
            const arena: *JsonArena = @ptrCast(@alignCast(arena_ptr));
            arena.decref();
            return; // Arena freed everything, we're done
        }

        // Free internal data based on type
        switch (obj.type_id) {
            .int => {
                const data: *PyInt = @ptrCast(@alignCast(obj.data));
                allocator.destroy(data);
            },
            .float => {
                const data: *PyFloat = @ptrCast(@alignCast(obj.data));
                allocator.destroy(data);
            },
            .bool => {
                const data: *PyBool = @ptrCast(@alignCast(obj.data));
                allocator.destroy(data);
            },
            .list => {
                const data: *PyList = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items.items) |item| {
                    decref(item, allocator);
                }
                data.items.deinit(data.allocator);
                allocator.destroy(data);
            },
            .tuple => {
                const data: *PyTuple = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items) |item| {
                    decref(item, allocator);
                }
                allocator.free(data.items);
                allocator.destroy(data);
            },
            .string => {
                const data: *PyString = @ptrCast(@alignCast(obj.data));
                if (data.source) |source| {
                    // COW: borrowed from source, just decref source
                    decref(source, allocator);
                } else {
                    // Owned: free the data
                    allocator.free(@constCast(data.data));
                }
                allocator.destroy(data);
            },
            .dict => {
                const data: *PyDict = @ptrCast(@alignCast(obj.data));
                // Free keys and decref values
                var it = data.map.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*); // Free the duplicated key
                    decref(entry.value_ptr.*, allocator); // Decref the value
                }
                data.map.deinit();
                allocator.destroy(data);
            },
            .file => {
                PyFile.deinit(obj, allocator);
                return; // deinit already destroys obj
            },
            else => {},
        }
        allocator.destroy(obj);
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    printPyObjectImpl(obj, false);
}

/// Internal: print PyObject with quote_strings flag for container elements
fn printPyObjectImpl(obj: *PyObject, quote_strings: bool) void {
    switch (obj.type_id) {
        .int => {
            const data: *PyInt = @ptrCast(@alignCast(obj.data));
            std.debug.print("{}", .{data.value});
        },
        .float => {
            const data: *PyFloat = @ptrCast(@alignCast(obj.data));
            std.debug.print("{d}", .{data.value});
        },
        .bool => {
            const data: *PyBool = @ptrCast(@alignCast(obj.data));
            std.debug.print("{s}", .{if (data.value) "True" else "False"});
        },
        .string => {
            const data: *PyString = @ptrCast(@alignCast(obj.data));
            if (quote_strings) {
                std.debug.print("'{s}'", .{data.data});
            } else {
                std.debug.print("{s}", .{data.data});
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
            // For other types (numpy_array, regex), print the pointer
            std.debug.print("{*}", .{obj});
        },
    }
}

/// Helper function to print a dict in Python format: {'key': value, ...}
fn printDict(obj: *PyObject) void {
    std.debug.assert(obj.type_id == .dict);
    const data: *PyDict = @ptrCast(@alignCast(obj.data));

    std.debug.print("{{", .{});
    var iter = data.map.iterator();
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
    std.debug.print("}}", .{});
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(obj.type_id == .list);
    const data: *PyList = @ptrCast(@alignCast(obj.data));

    std.debug.print("[", .{});
    for (data.items.items, 0..) |item, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        // Print each element based on its type
        switch (item.type_id) {
            .int => {
                const int_data: *PyInt = @ptrCast(@alignCast(item.data));
                std.debug.print("{}", .{int_data.value});
            },
            .string => {
                const str_data: *PyString = @ptrCast(@alignCast(item.data));
                std.debug.print("'{s}'", .{str_data.data});
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

/// Python file type - re-exported from pyfile.zig
pub const PyFile = pyfile.PyFile;

/// Helper functions for operations that can raise exceptions
/// True division (Python's / operator) - always returns float
pub fn divideFloat(a: anytype, b: anytype) PythonError!f64 {
    const a_float: f64 = switch (@typeInfo(@TypeOf(a))) {
        .float, .comptime_float => @as(f64, a),
        .int, .comptime_int => @floatFromInt(a),
        else => @compileError("divideFloat: unsupported type " ++ @typeName(@TypeOf(a))),
    };
    const b_float: f64 = switch (@typeInfo(@TypeOf(b))) {
        .float, .comptime_float => @as(f64, b),
        .int, .comptime_int => @floatFromInt(b),
        else => @compileError("divideFloat: unsupported type " ++ @typeName(@TypeOf(b))),
    };

    if (b_float == 0.0) {
        return PythonError.ZeroDivisionError;
    }
    return a_float / b_float;
}

/// Integer division (floor division //) with zero check
pub fn divideInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @divTrunc(a, b);
}

/// Modulo with zero check
pub fn moduloInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @mod(a, b);
}

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

/// Convert primitive i64 to PyString
pub fn intToString(allocator: std.mem.Allocator, value: i64) !*PyObject {
    const str = try std.fmt.allocPrint(allocator, "{}", .{value});
    return try PyString.create(allocator, str);
}

// Import and re-export built-in functions
const builtins = @import("runtime/builtins.zig");
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

/// Generic 'in' operator - checks membership based on container type
pub fn contains(needle: *PyObject, haystack: *PyObject) bool {
    switch (haystack.type_id) {
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
            if (needle.type_id != .string) {
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

// Import NumPy array support
pub const numpy_array = @import("numpy_array.zig");
pub const NumpyArray = numpy_array.NumpyArray;

// HTTP, async, JSON, regex, sys, and dynamic execution modules
pub const http = @import("http.zig");
pub const async_runtime = @import("async.zig");
pub const asyncio = @import("asyncio.zig");
pub const io = @import("io.zig");
pub const json = @import("json.zig");
pub const re = @import("re.zig");
pub const sys = @import("sys.zig");
pub const time = @import("time.zig");
pub const math = @import("math.zig");
pub const unittest = @import("unittest.zig");
pub const pathlib = @import("pathlib.zig");
pub const datetime = @import("datetime.zig");
pub const flask = @import("flask.zig");
pub const requests = @import("requests.zig");
pub const eval_module = @import("eval.zig");
pub const exec_module = @import("exec.zig");
pub const gzip = @import("gzip/gzip.zig");
pub const hashlib = @import("hashlib.zig");

// Green thread runtime (real M:N scheduler)
pub const GreenThread = @import("green_thread.zig").GreenThread;
pub const Scheduler = @import("scheduler.zig").Scheduler;
pub var scheduler: Scheduler = undefined;
pub var scheduler_initialized = false;

// Export convenience functions
pub const httpGet = http.getAsPyString;
pub const httpGetResponse = http.getAsResponse;
pub const sleep = async_runtime.sleepAsync;
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
