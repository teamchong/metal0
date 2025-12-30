// C Library Mapping Registry
// Central registry of all available library mappings
// Used for ctypes-style FFI to call real C libraries

const std = @import("std");
const mapper = @import("mapper.zig");
const detection = @import("detection.zig");

// Re-export public APIs
pub const ImportContext = detection.ImportContext;
pub const MappingRegistry = mapper.MappingRegistry;
pub const FunctionMapping = mapper.FunctionMapping;

// Re-export cpython types for generated code
const cpython_api = @import("include/object.zig");
pub const PyObject = cpython_api.PyObject;

/// Global registry containing all available mappings
pub var global_registry: ?*mapper.MappingRegistry = null;

/// Initialize the global registry with all known mappings
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    // Empty for now - mappings will be added via ctypes/cffi at runtime
    const all_mappings = [_]*const mapper.CLibraryMapping{};

    const registry = try allocator.create(mapper.MappingRegistry);
    registry.* = mapper.MappingRegistry.init(allocator, &all_mappings);
    global_registry = registry;
}

/// Cleanup the global registry
pub fn deinitGlobalRegistry(allocator: std.mem.Allocator) void {
    if (global_registry) |registry| {
        allocator.destroy(registry);
        global_registry = null;
    }
}

/// Get the global registry (must be initialized first)
pub fn getGlobalRegistry() !*mapper.MappingRegistry {
    return global_registry orelse error.RegistryNotInitialized;
}

/// Check if a package is supported
pub fn isPackageSupported(package_name: []const u8) bool {
    if (global_registry) |registry| {
        return registry.findByPackage(package_name) != null;
    }
    return false;
}

/// Get all supported package names
pub fn getSupportedPackages(allocator: std.mem.Allocator) ![]const []const u8 {
    const registry = try getGlobalRegistry();

    var packages: std.ArrayList([]const u8) = .{};
    errdefer packages.deinit(allocator);

    for (registry.mappings) |mapping| {
        try packages.append(allocator, mapping.package_name);
    }

    return packages.toOwnedSlice(allocator);
}

// ============================================================================
// Re-export PyObject traits for unified object manipulation
// ============================================================================

/// PyObject traits - systematic solutions for recurring patterns
/// Usage: const traits = @import("c_interop").traits;
pub const traits = @import("objects/typetraits.zig");

/// Optimization helpers - pointer casts, type builders
pub const helpers = @import("optimization_helpers.zig");

// ============================================================================
// Plugin System for External Library Customization
// ============================================================================

/// External library plugins (numpy, pandas, etc.)
/// Usage: const plugins = @import("c_interop").plugins;
///        if (plugins.getPlugin("numpy")) |np| { ... }
pub const plugins = @import("plugins/plugins.zig");

// ============================================================================
// Re-export PyObject modules for complete C API coverage
// ============================================================================

pub const cell = @import("objects/cellobject.zig");
pub const gen = @import("objects/genobject.zig");
pub const frame = @import("objects/frameobject.zig");
pub const file = @import("include/fileobject.zig");
pub const datetime = @import("include/datetime.zig");
pub const cpython_import = @import("include/import.zig");
pub const unicodeobject = @import("include/unicodeobject.zig");

// Re-export commonly used functions
pub const PyUnicode_AsUTF8 = @import("include/unicodeobject.zig").PyUnicode_AsUTF8;

// ============================================================================
// Generic C Extension Module Calls
// ============================================================================

const cpython = @import("include/object.zig");
const import = @import("include/import.zig");

/// Import a C extension module by name (e.g., "numpy", "pandas")
/// Uses real dlopen/dlsym to load the actual .so/.dylib extension
pub fn importModule(module_name: [*:0]const u8) ?*PyObject {
    // Use the real CPython import mechanism which does dlopen
    return import.PyImport_ImportModule(module_name);
}

/// Import attribute from module using Python's from-import semantics
/// Handles C extension modules and proxy modules (subprocess-based).
///
/// For "from numpy import array", this:
/// 1. Loads the module (C extension or proxy)
/// 2. Gets the attribute using appropriate method (subprocess for proxies)
pub fn fromImport(module_name: [*:0]const u8, attr_name: [*:0]const u8) ?*PyObject {
    // Import the module (works for C extensions and proxy modules)
    const module = import.PyImport_ImportModule(module_name) orelse return null;

    // For proxy modules, use subprocess-based attribute access
    // For regular modules, use standard PyObject_GetAttrString
    const result = import.getProxyAttr(module, attr_name) orelse
        traits.externs.PyObject_GetAttrString(module, attr_name);
    traits.externs.Py_DECREF(module);
    return result;
}

/// Call a function on a C extension module
/// Uses getAttr to get the function, then calls it via subprocess
pub fn callModuleFunction(
    module_name: [*:0]const u8,
    func_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    // For proxy modules, we need to call via subprocess
    return callFunctionViaSubprocess(module_name, func_name, args);
}

/// Validate that a string is a valid Python identifier (prevents injection)
/// Valid: letters, digits, underscores; cannot start with digit
fn isValidPythonIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    // First char must be letter or underscore
    const first = name[0];
    if (!std.ascii.isAlphabetic(first) and first != '_') return false;
    // Rest must be alphanumeric or underscore
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '.') return false;
    }
    return true;
}

/// Call a function via subprocess Python
fn callFunctionViaSubprocess(
    module_name: [*:0]const u8,
    func_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    const allocator = std.heap.c_allocator;
    const mod_str = std.mem.span(module_name);
    const func_str = std.mem.span(func_name);

    // SECURITY: Validate module and function names to prevent code injection
    if (!isValidPythonIdentifier(mod_str)) return null;
    if (!isValidPythonIdentifier(func_str)) return null;

    // Build Python code to call function
    var code_buf: [2048]u8 = undefined; // Increased for escaped strings

    // Format args for Python (now with proper escaping)
    var args_str_buf: [1024]u8 = undefined; // Increased for escaped content
    const args_str = formatArgsForPython(&args_str_buf, args);

    const py_code = std.fmt.bufPrint(&code_buf,
        \\import {s}
        \\result = {s}.{s}({s})
        \\print(repr(result))
    , .{ mod_str, mod_str, func_str, args_str }) catch return null;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", py_code },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |exit_code| if (exit_code != 0) return null,
        else => return null,
    }

    // Parse the output
    const output = std.mem.trimRight(u8, result.stdout, "\n\r");
    if (output.len == 0) return null;

    return import.parseSubprocessOutput(output);
}

/// Format Zig arguments as Python code
fn formatArgsForPython(buf: []u8, args: anytype) []const u8 {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
        const fields = args_info.@"struct".fields;
        if (fields.len == 0) {
            return "";
        }

        var pos: usize = 0;
        inline for (fields, 0..) |field, i| {
            const value = @field(args, field.name);
            const written = formatValueForPython(buf[pos..], value);
            pos += written;
            if (i < fields.len - 1) {
                if (pos < buf.len - 2) {
                    buf[pos] = ',';
                    buf[pos + 1] = ' ';
                    pos += 2;
                }
            }
        }
        return buf[0..pos];
    }

    return "";
}

/// Escape a string for safe Python embedding
/// Handles: backslash, single quote, newline, carriage return, tab
fn escapePythonString(buf: []u8, input: []const u8) usize {
    var pos: usize = 0;
    for (input) |c| {
        const escape_seq: ?[]const u8 = switch (c) {
            '\\' => "\\\\",
            '\'' => "\\'",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => null,
        };
        if (escape_seq) |seq| {
            if (pos + seq.len > buf.len) break;
            @memcpy(buf[pos..][0..seq.len], seq);
            pos += seq.len;
        } else {
            if (pos >= buf.len) break;
            buf[pos] = c;
            pos += 1;
        }
    }
    return pos;
}

/// Format a single value for Python with proper escaping and bounds checking
fn formatValueForPython(buf: []u8, value: anytype) usize {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .int, .comptime_int => {
            return (std.fmt.bufPrint(buf, "{d}", .{value}) catch return 0).len;
        },
        .float, .comptime_float => {
            return (std.fmt.bufPrint(buf, "{d}", .{value}) catch return 0).len;
        },
        .bool => {
            const s = if (value) "True" else "False";
            if (s.len > buf.len) return 0;
            @memcpy(buf[0..s.len], s);
            return s.len;
        },
        .array => |arr| {
            // Format as Python list with bounds checking
            if (buf.len < 2) return 0; // Need at least []
            buf[0] = '[';
            var pos: usize = 1;
            inline for (value, 0..) |elem, i| {
                if (pos >= buf.len - 1) break; // Reserve space for ]
                const written = formatValueForPython(buf[pos..], elem);
                pos += written;
                if (i < arr.len - 1) {
                    if (pos + 2 < buf.len - 1) { // Reserve for ", " and ]
                        buf[pos] = ',';
                        buf[pos + 1] = ' ';
                        pos += 2;
                    }
                }
            }
            if (pos < buf.len) {
                buf[pos] = ']';
                return pos + 1;
            }
            return 0;
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // String slice - wrap in quotes with proper escaping
                if (buf.len < 2) return 0; // Need at least ''
                buf[0] = '\'';
                // Escape the string content
                const escaped_len = escapePythonString(buf[1..buf.len -| 1], value);
                if (1 + escaped_len < buf.len) {
                    buf[1 + escaped_len] = '\'';
                    return escaped_len + 2;
                }
                return 0;
            }
            return 0;
        },
        else => return 0,
    }
}

/// Build a Python tuple from Zig arguments
fn buildArgsTuple(args: anytype) ?*cpython.PyObject {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        // Empty tuple for no arguments
        return traits.externs.PyTuple_New(0);
    }

    const fields = args_info.@"struct".fields;
    const tuple = traits.externs.PyTuple_New(@intCast(fields.len)) orelse return null;

    inline for (fields, 0..) |field, i| {
        const value = @field(args, field.name);
        const py_value = toPyObject(value) orelse {
            traits.externs.Py_DECREF(tuple);
            return null;
        };
        // PyTuple_SetItem steals reference, no need to decref py_value
        if (traits.externs.PyTuple_SetItem(tuple, @intCast(i), py_value) != 0) {
            traits.externs.Py_DECREF(tuple);
            return null;
        }
    }

    return tuple;
}

/// Convert Zig value to PyObject
fn toPyObject(value: anytype) ?*cpython.PyObject {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => traits.externs.PyLong_FromLongLong(@intCast(value)),
        .float, .comptime_float => traits.externs.PyFloat_FromDouble(@floatCast(value)),
        .bool => if (value) traits.externs.Py_True() else traits.externs.Py_False(),
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) {
                // String slice
                break :blk traits.externs.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
            } else if (ptr.size == .one) {
                // Assume it's already a PyObject*
                traits.externs.Py_INCREF(@ptrCast(value));
                break :blk @ptrCast(value);
            }
            break :blk null;
        },
        .array => |arr| blk: {
            // Convert Zig arrays to Python lists (for numpy.array etc.)
            const list = traits.externs.PyList_New(@intCast(arr.len)) orelse break :blk null;
            inline for (value, 0..) |elem, i| {
                const py_elem = toPyObject(elem) orelse {
                    traits.externs.Py_DECREF(list);
                    break :blk null;
                };
                // PyList_SetItem steals reference
                if (traits.externs.PyList_SetItem(list, @intCast(i), py_elem) != 0) {
                    traits.externs.Py_DECREF(list);
                    break :blk null;
                }
            }
            break :blk list;
        },
        .optional => if (value) |v| toPyObject(v) else traits.externs.Py_None(),
        else => null,
    };
}

/// Call a method on a PyObject
/// Currently a stub - C extensions require native reimplementation
pub fn callMethod(
    obj: *cpython.PyObject,
    method_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    _ = obj;
    _ = method_name;
    _ = args;
    return null;
}

/// Get an attribute from a PyObject
/// Uses real PyObject_GetAttrString for C extension objects
pub fn getAttr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
) ?*cpython.PyObject {
    // Check if this is a subprocess proxy module first
    if (import.isProxyModule(obj)) {
        return import.getProxyAttr(obj, attr_name);
    }
    // Use the real PyObject_GetAttrString from CPython C API
    return traits.externs.PyObject_GetAttrString(obj, attr_name);
}

/// Check if a PyObject has an attribute
/// Uses subprocess for proxy modules, PyObject_HasAttrString otherwise
pub fn hasattr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
) bool {
    // Check if this is a subprocess proxy module first
    if (import.isProxyModule(obj)) {
        return import.hasattrProxy(obj, attr_name);
    }
    // Use the real PyObject_HasAttrString from CPython C API
    return traits.externs.PyObject_HasAttrString(obj, attr_name) != 0;
}

/// Set an attribute on a PyObject
/// Currently a stub - C extensions require native reimplementation
pub fn setAttr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
    value: *cpython.PyObject,
) bool {
    _ = obj;
    _ = attr_name;
    _ = value;
    return false;
}

/// Get an attribute from a C extension module by name
/// Currently a stub - C extensions require native reimplementation
pub fn getModuleAttr(
    module_name: [*:0]const u8,
    attr_name: [*:0]const u8,
) ?*cpython.PyObject {
    _ = module_name;
    _ = attr_name;
    return null;
}
