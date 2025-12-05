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

    var packages = std.ArrayList([]const u8).init(allocator);
    defer packages.deinit();

    for (registry.mappings) |mapping| {
        try packages.append(mapping.package_name);
    }

    return packages.toOwnedSlice();
}

// ============================================================================
// Re-export PyObject traits for unified object manipulation
// ============================================================================

/// PyObject traits - systematic solutions for recurring patterns
/// Usage: const traits = @import("c_interop").traits;
pub const traits = @import("pyobject_traits.zig");

/// Optimization helpers - pointer casts, type builders
pub const helpers = @import("optimization_helpers.zig");

// ============================================================================
// Re-export PyObject modules for complete C API coverage
// ============================================================================

pub const cell = @import("pyobject_cell.zig");
pub const gen = @import("pyobject_gen.zig");
pub const frame = @import("pyobject_frame.zig");
pub const file = @import("cpython_file.zig");
pub const datetime = @import("cpython_datetime.zig");
pub const cpython_import = @import("cpython_import.zig");

// ============================================================================
// Generic C Extension Module Calls
// ============================================================================

const cpython = @import("cpython_object.zig");

/// Call a function on a C extension module (e.g., numpy.array, pandas.DataFrame)
///
/// Usage in generated code:
///   c_interop.callModuleFunction("numpy", "array", .{args...})
///
/// Returns: ?*cpython.PyObject (null on error)
pub fn callModuleFunction(
    module_name: [*:0]const u8,
    func_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    // Import the module
    const module = cpython_import.PyImport_ImportModule(module_name) orelse return null;
    defer traits.externs.Py_DECREF(module);

    // Get the function attribute
    const func = traits.externs.PyObject_GetAttrString(module, func_name) orelse return null;
    defer traits.externs.Py_DECREF(func);

    // Build args tuple
    const args_tuple = buildArgsTuple(args) orelse return null;
    defer traits.externs.Py_DECREF(args_tuple);

    // Call the function
    return traits.externs.PyObject_CallObject(func, args_tuple);
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
            if (ptr.size == .Slice and ptr.child == u8) {
                // String slice
                break :blk traits.externs.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
            } else if (ptr.size == .One) {
                // Assume it's already a PyObject*
                traits.externs.Py_INCREF(@ptrCast(value));
                break :blk @ptrCast(value);
            }
            break :blk null;
        },
        .optional => if (value) |v| toPyObject(v) else traits.externs.Py_None(),
        else => null,
    };
}

/// Call a method on a PyObject (e.g., arr.sum(), df.head())
///
/// Usage:
///   c_interop.callMethod(obj, "sum", .{})
///
/// Returns: ?*cpython.PyObject (null on error)
pub fn callMethod(
    obj: *cpython.PyObject,
    method_name: [*:0]const u8,
    args: anytype,
) ?*cpython.PyObject {
    // Get the method
    const method = traits.externs.PyObject_GetAttrString(obj, method_name) orelse return null;
    defer traits.externs.Py_DECREF(method);

    // Build args tuple
    const args_tuple = buildArgsTuple(args) orelse return null;
    defer traits.externs.Py_DECREF(args_tuple);

    // Call the method
    return traits.externs.PyObject_CallObject(method, args_tuple);
}

/// Get an attribute from a PyObject
pub fn getAttr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
) ?*cpython.PyObject {
    return traits.externs.PyObject_GetAttrString(obj, attr_name);
}

/// Set an attribute on a PyObject
pub fn setAttr(
    obj: *cpython.PyObject,
    attr_name: [*:0]const u8,
    value: *cpython.PyObject,
) bool {
    return traits.externs.PyObject_SetAttrString(obj, attr_name, value) == 0;
}

/// Get an attribute from a C extension module by name
/// Used for accessing module-level attributes like np.__version__
///
/// Usage in generated code:
///   c_interop.getModuleAttr("numpy", "__version__")
///
/// Returns: ?*cpython.PyObject (null on error)
pub fn getModuleAttr(
    module_name: [*:0]const u8,
    attr_name: [*:0]const u8,
) ?*cpython.PyObject {
    // Import the module
    const module = cpython_import.PyImport_ImportModule(module_name) orelse return null;
    defer traits.externs.Py_DECREF(module);

    // Get the attribute (returns new reference)
    const attr = traits.externs.PyObject_GetAttrString(module, attr_name) orelse return null;

    return attr;
}
