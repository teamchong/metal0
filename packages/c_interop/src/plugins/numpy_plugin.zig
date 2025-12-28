//! Numpy Plugin for metal0 c_interop
//!
//! Provides optimized handling for common numpy operations:
//! - numpy.array() - array creation
//! - numpy.zeros/ones/empty - allocation patterns
//! - ndarray.sum/mean/max/min - reduction operations
//! - ndarray.reshape/transpose - shape operations
//!
//! This plugin enables numpy code to compile and run efficiently
//! by bridging numpy's C API with metal0's native types.

const std = @import("std");
const plugin = @import("plugin.zig");

/// Numpy type information
const NumpyTypes = struct {
    /// ndarray is stored as a PyValue.ptr pointing to PyArrayObject
    pub const ndarray = plugin.TypeInfo{
        .zig_type = "runtime.PyValue",
        .needs_conversion = false,
        .to_pyvalue_fn = null, // PyValue.from() handles this
        .from_pyvalue_fn = null,
    };

    /// dtype is represented as a string
    pub const dtype = plugin.TypeInfo{
        .zig_type = "[]const u8",
        .needs_conversion = false,
    };
};

/// Get type info for numpy types
fn getTypeInfo(type_name: []const u8) ?plugin.TypeInfo {
    if (std.mem.eql(u8, type_name, "ndarray")) return NumpyTypes.ndarray;
    if (std.mem.eql(u8, type_name, "dtype")) return NumpyTypes.dtype;
    return null;
}

/// Handle numpy function calls
/// Currently returns null for all - uses default c_interop.callModuleFunction
/// Future: optimize specific functions like zeros/ones/arange
fn handleFunction(
    func_name: []const u8,
    args: []const []const u8,
) ?[]const u8 {
    _ = func_name;
    _ = args;

    // For now, let all functions go through default c_interop path
    // This can be extended to optimize specific functions:
    //
    // if (std.mem.eql(u8, func_name, "zeros")) {
    //     // Emit optimized zeros allocation
    //     return "runtime.numpy_compat.zeros(...)";
    // }

    return null;
}

/// Handle numpy ndarray method calls
/// Currently returns null for all - uses default c_interop.callMethod
/// Future: optimize specific methods like sum/mean
fn handleMethod(
    obj_type: []const u8,
    method_name: []const u8,
    args: []const []const u8,
) ?[]const u8 {
    _ = obj_type;
    _ = method_name;
    _ = args;

    // For now, let all methods go through default c_interop path
    // This can be extended to optimize specific methods:
    //
    // if (std.mem.eql(u8, method_name, "sum")) {
    //     // Emit optimized sum that avoids Python call overhead
    //     return "runtime.numpy_compat.arraySum(arr)";
    // }

    return null;
}

/// The numpy plugin instance
pub const numpy_plugin = plugin.Plugin{
    .module_name = "numpy",
    .handle_function = handleFunction,
    .handle_method = handleMethod,
    .get_type_info = getTypeInfo,
    .intercept_all = false,
    .description = "Numpy support plugin - bridges numpy C API with metal0",
};
