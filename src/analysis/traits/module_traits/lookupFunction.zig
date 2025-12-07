//! lookupFunction - Get FunctionTraits for a module.function call
//! USE: During codegen when generating call to module.func()
//! CALL: registry.lookupFunction("mymodule", "add")
//! RETURNS: FunctionTraits with needs_allocator, can_error, etc.

const function_traits = @import("../function_traits.zig");
const module_traits = @import("../module_traits.zig");

/// Lookup function traits in the module registry
/// Returns null if module or function not found
pub fn lookupFunction(
    registry: *const module_traits.ModuleRegistry,
    module_name: []const u8,
    func_name: []const u8,
) ?function_traits.FunctionTraits {
    return registry.lookupFunction(module_name, func_name);
}

/// Lookup function in a specific ModuleInfo
pub fn lookupInModule(
    info: *const module_traits.ModuleInfo,
    func_name: []const u8,
) ?function_traits.FunctionTraits {
    return info.getFunction(func_name);
}

/// Lookup a method in a class within a module
pub fn lookupMethod(
    registry: *const module_traits.ModuleRegistry,
    module_name: []const u8,
    class_name: []const u8,
    method_name: []const u8,
) ?function_traits.FunctionTraits {
    if (registry.getModule(module_name)) |info| {
        if (info.getClass(class_name)) |class_meta| {
            return class_meta.methods.get(method_name);
        }
    }
    return null;
}
