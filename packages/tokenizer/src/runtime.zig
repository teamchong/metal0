/// PyAOT Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const pyint = @import("pyint.zig");
const pyfloat = @import("pyfloat.zig");
const pybool = @import("pybool.zig");
const pylist = @import("pylist.zig");
const pystring = @import("pystring.zig");
const pytuple = @import("pytuple.zig");

/// Export string utilities for native codegen
pub const string_utils = @import("string_utils.zig");

/// Export comptime type inference helpers
const comptime_helpers = @import("comptime_helpers.zig");
pub const InferListType = comptime_helpers.InferListType;
pub const createListComptime = comptime_helpers.createListComptime;
pub const InferDictValueType = comptime_helpers.InferDictValueType;

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

    pub const TypeId = enum {
        int,
        float,
        bool,
        string,
        list,
        tuple,
        dict,
        none,
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
                allocator.free(data.data);
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
            else => {},
        }
        allocator.destroy(obj);
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    switch (obj.type_id) {
        .int => {
            const data: *PyInt = @ptrCast(@alignCast(obj.data));
            std.debug.print("{}", .{data.value});
        },
        .string => {
            const data: *PyString = @ptrCast(@alignCast(obj.data));
            std.debug.print("{s}", .{data.data});
        },
        else => {
            // For other types, print the pointer (fallback)
            std.debug.print("{*}", .{obj});
        },
    }
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

/// Format any value for Python-style printing (booleans as True/False)
/// This function is a no-op at runtime - it's just for compile-time type checking
/// For bool: returns "True" or "False"
/// For other types: identity function (returns the value unchanged)
pub inline fn formatAny(value: anytype) (if (@TypeOf(value) == bool) []const u8 else @TypeOf(value)) {
    if (@TypeOf(value) == bool) {
        return if (value) "True" else "False";
    } else {
        return value;
    }
}

/// Format float value for printing (Python-style: always show .0 for whole numbers)
/// Examples: 25.0 -> "25.0", 3.14159 -> "3.14159"
pub fn formatFloat(value: f64, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8){};
    if (@mod(value, 1.0) == 0.0) {
        // Whole number: force .0 to match Python behavior
        try buf.writer(allocator).print("{d:.1}", .{value});
    } else {
        // Has decimals: show all significant digits
        try buf.writer(allocator).print("{d}", .{value});
    }
    return try buf.toOwnedSlice(allocator);
}

/// Format PyObject as string for printing
/// Used when printing dict values with unknown/mixed types
/// Returns a formatted string that can be printed with {s}
pub fn formatPyObject(obj: *PyObject, allocator: std.mem.Allocator) ![]const u8 {
    return switch (obj.type_id) {
        .string => blk: {
            const str_data: *PyString = @ptrCast(@alignCast(obj.data));
            break :blk str_data.data;
        },
        .int => blk: {
            const int_data: *PyInt = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.writer(allocator).print("{d}", .{int_data.value});
            break :blk try buf.toOwnedSlice(allocator);
        },
        .float => blk: {
            const float_data: *PyFloat = @ptrCast(@alignCast(obj.data));
            break :blk try formatFloat(float_data.value, allocator);
        },
        .bool => blk: {
            const bool_data: *PyBool = @ptrCast(@alignCast(obj.data));
            break :blk if (bool_data.value) "True" else "False";
        },
        .dict => blk: {
            const dict_data: *PyDict = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.appendSlice(allocator, "{");

            var it = dict_data.map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) {
                    try buf.appendSlice(allocator, ", ");
                }
                // Format as Python dict: {'key': value}
                try buf.writer(allocator).print("'{s}': ", .{entry.key_ptr.*});

                // Format value based on type
                const val_obj = entry.value_ptr.*;
                switch (val_obj.type_id) {
                    .string => {
                        const val_str: *PyString = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("'{s}'", .{val_str.data});
                    },
                    .int => {
                        const val_int: *PyInt = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("{d}", .{val_int.value});
                    },
                    else => {
                        try buf.appendSlice(allocator, "<object>");
                    },
                }
                first = false;
            }

            try buf.appendSlice(allocator, "}");
            break :blk try buf.toOwnedSlice(allocator);
        },
        else => "<object>",
    };
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

// HTTP, async, and JSON modules
pub const http = @import("http.zig");
pub const async_runtime = @import("async.zig");
pub const json = @import("json.zig");

// Export convenience functions
pub const httpGet = http.getAsPyString;
pub const httpGetResponse = http.getAsResponse;
pub const sleep = async_runtime.sleepAsync;
pub const now = async_runtime.now;
pub const jsonLoads = json.loads;
pub const jsonDumps = json.dumps;

/// Format dict as Python dict string: {key: value, ...}
/// Supports both StringHashMap and ArrayList(KV) for dict comprehensions
/// ArrayList preserves insertion order (Python 3.7+ behavior)
pub fn PyDict_AsString(dict: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8){};
    try buf.appendSlice(allocator, "{");

    const T = @TypeOf(dict);
    const type_info = @typeInfo(T);

    // Check if it's an ArrayList by checking for 'items' field
    const is_arraylist = comptime blk: {
        if (type_info == .@"struct") {
            if (@hasDecl(T, "Slice")) {
                // It's likely an ArrayList
                break :blk true;
            }
        }
        break :blk false;
    };

    if (is_arraylist) {
        // ArrayList(KV) - iterate in order
        for (dict.items, 0..) |item, i| {
            if (i > 0) {
                try buf.appendSlice(allocator, ", ");
            }
            try buf.writer(allocator).print("{s}: {d}", .{ item.key, item.value });
        }
    } else {
        // StringHashMap - iterate in hash order
        var it = dict.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) {
                try buf.appendSlice(allocator, ", ");
            }

            // Format key and value
            try buf.writer(allocator).print("{s}: {d}", .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });

            first = false;
        }
    }

    try buf.appendSlice(allocator, "}");
    return try buf.toOwnedSlice(allocator);
}

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
