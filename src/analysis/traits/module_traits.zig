//! Module Traits - Cross-module function and constant registry
//!
//! Tracks metadata for functions/constants across module boundaries.
//! Enables proper codegen for local module calls like `test_mymodule.add(2, 3)`.
//!
//! | Query                     | Used For                                      |
//! |---------------------------|-----------------------------------------------|
//! | lookupFunction            | Get FunctionTraits for module.func            |
//! | lookupConstant            | Get ConstantMeta for module.CONSTANT          |
//! | isLocalModule             | Check if module is local .py vs stdlib        |
//! | analyzeModule             | Analyze AST → ModuleInfo                      |
//! | registerModule            | Add module to global registry                 |
//!
//! USAGE:
//! ```zig
//! const module_traits = @import("analysis.module_traits");
//!
//! // During compilation: analyze and register module
//! const info = try module_traits.analyzeModule(ast, "mymodule", allocator);
//! try registry.registerModule("mymodule", info);
//!
//! // During codegen: lookup function metadata
//! if (registry.lookupFunction("mymodule", "add")) |traits| {
//!     const needs_alloc = traits.needs_allocator;
//!     const can_error = traits.can_error;
//! }
//! ```

const std = @import("std");
const function_traits = @import("analysis.function_traits");
const hashmap_helper = @import("utils.hashmap_helper");

/// Simple type tag for module-level type tracking
/// Lightweight alternative to full NativeType for module traits
pub const SimpleType = enum {
    unknown,
    int,
    float,
    string,
    bytes,
    boolean,
    none,
    list,
    dict,
    set,
    tuple,
    callable,
    class_instance,
};

// Re-export submodule functions
pub const analyzeModule = @import("module_traits/analyzeModule.zig").analyzeModule;
pub const isLocalModule = @import("module_traits/isLocalModule.zig").isLocalModule;

/// Metadata for a module-level constant
pub const ConstantMeta = struct {
    name: []const u8,
    value_type: SimpleType,
    /// Compile-time value if known (for const propagation)
    comptime_value: ?ComptimeValue = null,
};

/// Compile-time constant values that can be propagated
pub const ComptimeValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    none: void,
};

/// Metadata for a class exported by a module
pub const ClassMeta = struct {
    name: []const u8,
    /// Methods in this class
    methods: hashmap_helper.StringHashMap(function_traits.FunctionTraits),
    /// Class-level variables/constants
    class_vars: hashmap_helper.StringHashMap(ConstantMeta),
};

/// Complete metadata for a module
pub const ModuleInfo = struct {
    /// Module name (e.g., "test_mymodule")
    name: []const u8,
    /// File path for local modules
    path: []const u8,
    /// True if local .py file, false if stdlib
    is_local: bool,

    /// Function traits - reuses existing FunctionTraits struct
    functions: hashmap_helper.StringHashMap(function_traits.FunctionTraits),

    /// Module-level constants (e.g., VERSION = "1.0.0")
    constants: hashmap_helper.StringHashMap(ConstantMeta),

    /// Exported classes
    classes: hashmap_helper.StringHashMap(ClassMeta),

    /// Initialize empty ModuleInfo
    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8, is_local: bool) ModuleInfo {
        return .{
            .name = name,
            .path = path,
            .is_local = is_local,
            .functions = hashmap_helper.StringHashMap(function_traits.FunctionTraits).init(allocator),
            .constants = hashmap_helper.StringHashMap(ConstantMeta).init(allocator),
            .classes = hashmap_helper.StringHashMap(ClassMeta).init(allocator),
        };
    }

    /// Lookup a function in this module
    pub fn getFunction(self: *const ModuleInfo, func_name: []const u8) ?function_traits.FunctionTraits {
        return self.functions.get(func_name);
    }

    /// Lookup a constant in this module
    pub fn getConstant(self: *const ModuleInfo, const_name: []const u8) ?ConstantMeta {
        return self.constants.get(const_name);
    }

    /// Lookup a class in this module
    pub fn getClass(self: *const ModuleInfo, class_name: []const u8) ?ClassMeta {
        return self.classes.get(class_name);
    }
};

/// Global module registry - singleton that holds all analyzed modules
pub const ModuleRegistry = struct {
    modules: hashmap_helper.StringHashMap(ModuleInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModuleRegistry {
        return .{
            .modules = hashmap_helper.StringHashMap(ModuleInfo).init(allocator),
            .allocator = allocator,
        };
    }

    /// Register a module in the registry
    pub fn registerModule(self: *ModuleRegistry, name: []const u8, info: ModuleInfo) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.modules.put(name_copy, info);
    }

    /// Get module info by name
    pub fn getModule(self: *const ModuleRegistry, module_name: []const u8) ?ModuleInfo {
        return self.modules.get(module_name);
    }

    /// Lookup a function across all modules
    pub fn lookupFunction(self: *const ModuleRegistry, module_name: []const u8, func_name: []const u8) ?function_traits.FunctionTraits {
        if (self.modules.get(module_name)) |info| {
            return info.functions.get(func_name);
        }
        return null;
    }

    /// Lookup a constant across all modules
    pub fn lookupConstant(self: *const ModuleRegistry, module_name: []const u8, const_name: []const u8) ?ConstantMeta {
        if (self.modules.get(module_name)) |info| {
            return info.constants.get(const_name);
        }
        return null;
    }

    /// Check if a module is registered
    pub fn hasModule(self: *const ModuleRegistry, module_name: []const u8) bool {
        return self.modules.contains(module_name);
    }
};
