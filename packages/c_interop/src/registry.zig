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
const exc = @import("exception_types.zig");

fn setErrorIfNone(exc_type: *cpython.PyTypeObject, msg: [*:0]const u8) void {
    if (traits.externs.PyErr_Occurred() == null) {
        traits.externs.PyErr_SetString(@ptrCast(exc_type), msg);
    }
}

/// Import a C extension module by name (e.g., "numpy", "pandas")
/// Uses real dlopen/dlsym to load the actual .so/.dylib extension
pub fn importModule(module_name: [*:0]const u8) ?*PyObject {
    // Use the real CPython import mechanism which does dlopen
    return import.PyImport_ImportModule(module_name);
}

/// Import attribute from module using Python's from-import semantics
/// Uses dlopen for C extension modules - NO subprocess.
///
/// For "from numpy import array", this:
/// 1. Loads the module via dlopen
/// 2. Gets the attribute using PyObject_GetAttrString
pub fn fromImport(module_name: [*:0]const u8, attr_name: [*:0]const u8) ?*PyObject {
    // Import the module via dlopen
    const module = import.PyImport_ImportModule(module_name) orelse {
        setErrorIfNone(exc.PyExc_ImportError, "C extension import failed (no subprocess fallback)");
        return null;
    };
    defer traits.externs.Py_DECREF(module);

    // Get attribute using standard PyObject_GetAttrString
    const attr = traits.externs.PyObject_GetAttrString(module, attr_name) orelse {
        setErrorIfNone(exc.PyExc_AttributeError, "attribute not found");
        return null;
    };
    return attr;
}

/// Call a function on a C extension module
/// Uses real C API: import module, get function, build args, call
/// NO subprocess fallback - if dlopen fails, returns null
pub fn callModuleFunction(
    module_name: [*:0]const u8,
    func_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    // Import the module using real dlopen/dlsym - NO subprocess fallback
    const module = import.PyImport_ImportModule(module_name) orelse {
        setErrorIfNone(exc.PyExc_ImportError, "C extension import failed (no subprocess fallback)");
        return null;
    };
    defer traits.externs.Py_DECREF(module);

    // Get the function attribute
    const func = traits.externs.PyObject_GetAttrString(module, func_name) orelse {
        setErrorIfNone(exc.PyExc_AttributeError, "function attribute not found");
        return null;
    };
    defer traits.externs.Py_DECREF(func);

    // Build args tuple from Zig values
    // Note: buildArgsTuple returns empty tuple for no args ({}), null only on error
    const args_tuple = buildArgsTuple(args) orelse {
        setErrorIfNone(exc.PyExc_TypeError, "failed to build argument tuple");
        return null;
    };
    defer traits.externs.Py_DECREF(args_tuple);

    // Call the function
    const result = traits.externs.PyObject_Call(func, args_tuple, null);
    if (result == null) {
        setErrorIfNone(exc.PyExc_RuntimeError, "C extension call failed");
    }
    return result;
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
                // String slice []const u8
                break :blk traits.externs.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
            } else if (ptr.size == .one) {
                // Check if it's a pointer to a u8 array (string literal like *const [N:0]u8)
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    // String literal: *const [N:0]u8 or *const [N]u8 -> use PyUnicode_FromString
                    break :blk traits.externs.PyUnicode_FromString(@ptrCast(value));
                } else if (ptr.child == cpython.PyObject) {
                    // Already a PyObject*
                    traits.externs.Py_INCREF(value);
                    break :blk value;
                }
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
        .@"union" => {
            // Handle runtime.PyValue union - convert each variant to PyObject
            // Use inline else to handle all variants
            return switch (value) {
                .ptr => |p| blk: {
                    // Check for null pointer before cast to prevent segfaults
                    if (@intFromPtr(p) == 0) break :blk traits.externs.Py_None();
                    break :blk @as(*cpython.PyObject, @ptrCast(@alignCast(p)));
                },
                .string => |s| traits.externs.PyUnicode_FromStringAndSize(s.ptr, @intCast(s.len)),
                .int => |i| traits.externs.PyLong_FromLongLong(i),
                .float => |f| traits.externs.PyFloat_FromDouble(f),
                // Convert bool to int (1/0) since Py_True/Py_False stubs have layout issues
                .bool => |b| traits.externs.PyLong_FromLongLong(if (b) 1 else 0),
                .none => traits.externs.Py_None(),
                inline else => null,
            };
        },
        else => null,
    };
}

/// Call a method on a PyObject
/// Uses PyObject_GetAttrString to get the method, then PyObject_Call to invoke it
pub fn callMethod(
    obj: *cpython.PyObject,
    method_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    // Get the method attribute from the object
    const method = traits.externs.PyObject_GetAttrString(obj, method_name) orelse {
        setErrorIfNone(exc.PyExc_AttributeError, "method attribute not found");
        return null;
    };
    defer traits.externs.Py_DECREF(method);

    // Build args tuple from Zig values
    // Note: buildArgsTuple returns empty tuple for no args ({}), null only on error
    const args_tuple = buildArgsTuple(args) orelse {
        setErrorIfNone(exc.PyExc_TypeError, "failed to build argument tuple");
        return null;
    };
    defer traits.externs.Py_DECREF(args_tuple);

    // Call the method with the args tuple
    const result = traits.externs.PyObject_Call(method, args_tuple, null);
    if (result == null) {
        setErrorIfNone(exc.PyExc_RuntimeError, "method call failed");
    }
    return result;
}

/// Call a PyObject callable with Zig arguments
/// Used for calling from-imported C extension functions like load_library
/// The callable is a ?*PyObject retrieved via fromImport
pub fn callFromImport(callable: ?*cpython.PyObject, args: anytype) ?*cpython.PyObject {
    const c = callable orelse return null;

    // Validate the object pointer before accessing it
    // Check that ob_type is a valid pointer (not in suspicious ranges)
    const type_ptr = @intFromPtr(c.ob_type);
    if (type_ptr < 0x1000 or type_ptr == 0x42000000) {
        // Invalid type pointer - object is corrupted
        return null;
    }

    // Build args tuple from Zig values
    const args_tuple = buildArgsTuple(args) orelse {
        setErrorIfNone(exc.PyExc_TypeError, "failed to build argument tuple");
        return null;
    };
    defer traits.externs.Py_DECREF(args_tuple);

    // Call the callable using PyObject_Call
    const result = traits.externs.PyObject_Call(c, args_tuple, null);
    if (result == null) {
        setErrorIfNone(exc.PyExc_RuntimeError, "callable invocation failed");
    }
    return result;
}

/// Get an attribute from a PyObject
/// Uses real PyObject_GetAttrString from CPython C API
pub fn getAttr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
) ?*cpython.PyObject {
    return traits.externs.PyObject_GetAttrString(obj, attr_name);
}

/// Check if a PyObject has an attribute
/// Uses real PyObject_HasAttrString from CPython C API
pub fn hasattr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
) bool {
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
