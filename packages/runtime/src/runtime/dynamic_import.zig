const std = @import("std");
const runtime = @import("../runtime.zig");

/// Module registry for dynamically imported modules
/// In AOT compilation, modules are compiled statically but may need
/// runtime lookup for exec()/eval() or importlib.import_module()
const ModuleRegistry = struct {
    var modules: std.StringHashMapUnmanaged(*runtime.PyObject) = .{};
    var initialized: bool = false;

    fn ensureInit(allocator: std.mem.Allocator) void {
        if (initialized) return;
        modules = std.StringHashMapUnmanaged(*runtime.PyObject){};
        _ = allocator;
        initialized = true;
    }

    pub fn get(name: []const u8) ?*runtime.PyObject {
        return modules.get(name);
    }

    pub fn put(allocator: std.mem.Allocator, name: []const u8, module: *runtime.PyObject) !void {
        ensureInit(allocator);
        try modules.put(allocator, name, module);
    }
};

/// Register a module in the runtime registry
/// Called by compiled modules during initialization
pub fn registerModule(allocator: std.mem.Allocator, name: []const u8, module: *runtime.PyObject) !void {
    try ModuleRegistry.put(allocator, name, module);
}

/// Dynamically import a module by name
/// For AOT-compiled code, this looks up pre-compiled modules in the registry
pub fn dynamic_import(allocator: std.mem.Allocator, module_name: []const u8) !*runtime.PyObject {
    // First check the module registry for pre-compiled modules
    if (ModuleRegistry.get(module_name)) |module| {
        return module;
    }

    // Check for builtin module names
    // These are handled at compile time but we return a marker for compatibility
    const builtins = [_][]const u8{
        "sys",      "os",        "io",       "json",     "re",
        "math",     "random",    "time",     "datetime", "collections",
        "itertools", "functools", "operator", "string",   "pathlib",
    };

    for (builtins) |builtin| {
        if (std.mem.eql(u8, module_name, builtin)) {
            // Module exists but wasn't registered - compile-time import was used
            // Return error to signal caller should use static import
            return error.UseStaticImport;
        }
    }

    _ = allocator;
    return error.ModuleNotFound;
}

/// Check if a module is available (either registered or builtin)
pub fn moduleExists(module_name: []const u8) bool {
    if (ModuleRegistry.get(module_name) != null) return true;

    const builtins = [_][]const u8{
        "sys",      "os",        "io",       "json",     "re",
        "math",     "random",    "time",     "datetime", "collections",
        "itertools", "functools", "operator", "string",   "pathlib",
    };

    for (builtins) |builtin| {
        if (std.mem.eql(u8, module_name, builtin)) return true;
    }

    return false;
}
