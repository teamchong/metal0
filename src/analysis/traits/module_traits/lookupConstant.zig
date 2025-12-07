//! lookupConstant - Get ConstantMeta for a module.CONSTANT reference
//! USE: During codegen when referencing module.VERSION, module.MAX_SIZE, etc.
//! CALL: registry.lookupConstant("mymodule", "VERSION")
//! RETURNS: ConstantMeta with value_type and optional comptime_value

const module_traits = @import("../module_traits.zig");

/// Lookup constant metadata in the module registry
/// Returns null if module or constant not found
pub fn lookupConstant(
    registry: *const module_traits.ModuleRegistry,
    module_name: []const u8,
    const_name: []const u8,
) ?module_traits.ConstantMeta {
    return registry.lookupConstant(module_name, const_name);
}

/// Lookup constant in a specific ModuleInfo
pub fn lookupInModule(
    info: *const module_traits.ModuleInfo,
    const_name: []const u8,
) ?module_traits.ConstantMeta {
    return info.getConstant(const_name);
}

/// Lookup a class variable in a module
pub fn lookupClassVar(
    registry: *const module_traits.ModuleRegistry,
    module_name: []const u8,
    class_name: []const u8,
    var_name: []const u8,
) ?module_traits.ConstantMeta {
    if (registry.getModule(module_name)) |info| {
        if (info.getClass(class_name)) |class_meta| {
            return class_meta.class_vars.get(var_name);
        }
    }
    return null;
}

/// Check if a constant has a known compile-time value
pub fn hasComptimeValue(meta: module_traits.ConstantMeta) bool {
    return meta.comptime_value != null;
}

/// Get the compile-time integer value if available
pub fn getComptimeInt(meta: module_traits.ConstantMeta) ?i64 {
    if (meta.comptime_value) |val| {
        return switch (val) {
            .int => |i| i,
            else => null,
        };
    }
    return null;
}

/// Get the compile-time string value if available
pub fn getComptimeString(meta: module_traits.ConstantMeta) ?[]const u8 {
    if (meta.comptime_value) |val| {
        return switch (val) {
            .string => |s| s,
            else => null,
        };
    }
    return null;
}
