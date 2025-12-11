/// JSON decoding functionality

const std = @import("std");
const runtime = @import("../../runtime.zig");
const types = @import("types.zig");
const parse_direct = @import("../json_impl/parse_direct.zig");
const parse_arena = @import("../json_impl/parse_arena.zig");

/// Deserialize JSON string to PyObject (arena-allocated for speed!)
/// Python: json.loads(json_str) -> obj
/// Uses arena allocation: single malloc for entire parse, single free on cleanup
pub fn loads(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (!runtime.PyUnicode_Check(json_str)) {
        return error.TypeError;
    }

    const json_bytes = runtime.PyString.getValue(json_str);

    // Use arena-based parser for maximum performance
    // Arena is attached to root object and freed when root is decref'd to 0
    const result = try parse_arena.parseWithArena(json_bytes, allocator);

    return result;
}

/// Deserialize JSON string to PyObject (legacy - uses per-object allocation)
/// Use this when you need objects to outlive the parse scope independently
pub fn loadsLegacy(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (!runtime.PyUnicode_Check(json_str)) {
        return error.TypeError;
    }

    const json_bytes = runtime.PyString.getValue(json_str);

    // Parse with lazy mode - strings borrow from source (zero-copy!)
    // Source is kept alive because borrowed strings hold refcount to it
    const result = try parse_direct.parseWithSource(json_bytes, allocator, json_str);

    return result;
}

/// load(fp) - deserialize JSON from file to PyObject
pub fn load(fp: anytype, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Read entire file into buffer
    const contents = try fp.readAllAlloc(allocator, 1024 * 1024 * 100); // 100MB max
    defer allocator.free(contents);

    // Parse JSON
    return try parse_arena.parseWithArena(contents, allocator);
}

/// loads with options - json.loads(s, parse_constant=..., parse_float=..., etc.)
pub fn loadsWithOptions(json_str: *runtime.PyObject, allocator: std.mem.Allocator, options: types.LoadsOptions) !*runtime.PyObject {
    if (!runtime.PyUnicode_Check(json_str)) {
        return error.TypeError;
    }

    const json_bytes = runtime.PyString.getValue(json_str);
    const result = try parse_arena.parseWithArena(json_bytes, allocator);

    // Apply parse_constant hook if provided
    if (options.parse_constant) |callback| {
        const type_id = runtime.getTypeId(result);
        if (type_id == .float) {
            const float_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(result));
            const val = float_obj.ob_fval;
            if (std.math.isNan(val)) {
                runtime.decref(result, allocator);
                return callback("NaN", allocator);
            } else if (std.math.isInf(val)) {
                runtime.decref(result, allocator);
                if (val > 0) {
                    return callback("Infinity", allocator);
                } else {
                    return callback("-Infinity", allocator);
                }
            }
        }
    }

    return result;
}

/// JSONDecoder - class for customizing JSON decoding
pub const JSONDecoder = struct {
    allocator: std.mem.Allocator,
    object_hook: ?*const fn (*runtime.PyObject, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    object_pairs_hook: ?*const fn ([]struct { []const u8, *runtime.PyObject }, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_float: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_int: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_constant: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    strict: bool = true,

    pub fn init(allocator: std.mem.Allocator) JSONDecoder {
        return .{ .allocator = allocator };
    }

    pub fn decode(self: JSONDecoder, json_str: []const u8) !*runtime.PyObject {
        // Basic decode - hooks not fully implemented yet
        return parse_arena.parseWithArena(json_str, self.allocator);
    }

    /// Set parse_constant callback for handling -Infinity, Infinity, NaN
    /// In Python: JSONDecoder(parse_constant=my_func)
    pub fn setParseConstant(self: *JSONDecoder, callback: *const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject) void {
        self.parse_constant = callback;
    }

    /// Decode with parse_constant support
    /// This method applies parse_constant callback to special constants like NaN, Infinity
    pub fn decodeWithHooks(self: JSONDecoder, json_str: []const u8) !*runtime.PyObject {
        // First do basic parse
        const result = try parse_arena.parseWithArena(json_str, self.allocator);

        // If we have a parse_constant hook and the result is a special constant
        if (self.parse_constant) |callback| {
            const type_id = runtime.getTypeId(result);
            if (type_id == .float) {
                const float_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(result));
                const val = float_obj.ob_fval;
                if (std.math.isNan(val)) {
                    runtime.decref(result, self.allocator);
                    return callback("NaN", self.allocator);
                } else if (std.math.isInf(val)) {
                    runtime.decref(result, self.allocator);
                    if (val > 0) {
                        return callback("Infinity", self.allocator);
                    } else {
                        return callback("-Infinity", self.allocator);
                    }
                }
            }
        }

        return result;
    }
};
