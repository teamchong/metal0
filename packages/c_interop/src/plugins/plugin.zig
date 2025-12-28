//! External Library Plugin System
//!
//! Plugins allow custom handling for specific external Python libraries.
//! Each plugin can provide:
//! - Custom type converters (e.g., numpy.ndarray -> native type)
//! - Function interceptors (e.g., numpy.array() -> optimized codegen)
//! - Method interceptors (e.g., arr.sum() -> direct native call)
//!
//! Usage in codegen:
//!   if (plugins.getPlugin("numpy")) |np_plugin| {
//!       if (np_plugin.handleFunction("array", args)) |result| {
//!           return result;
//!       }
//!   }
//!
const std = @import("std");

/// Result of a plugin function/method interception
pub const InterceptResult = union(enum) {
    /// Plugin generated code - use this instead of default codegen
    generated: []const u8,
    /// Plugin wants to modify args, then proceed with default codegen
    modified_args: []const u8,
    /// Plugin doesn't handle this - use default codegen
    not_handled: void,
};

/// Type information from plugin
pub const TypeInfo = struct {
    /// Zig type to use for this Python type
    zig_type: []const u8,
    /// Whether this type needs special serialization
    needs_conversion: bool = false,
    /// Custom conversion function if needed
    to_pyvalue_fn: ?[]const u8 = null,
    from_pyvalue_fn: ?[]const u8 = null,
};

/// Plugin interface for external library customization
pub const Plugin = struct {
    /// Module name this plugin handles (e.g., "numpy", "pandas")
    module_name: []const u8,

    /// Optional: Handle a function call on this module
    /// Returns generated Zig code or null if not handled
    handle_function: ?*const fn (
        func_name: []const u8,
        args: []const []const u8,
    ) ?[]const u8 = null,

    /// Optional: Handle a method call on an object from this module
    /// Returns generated Zig code or null if not handled
    handle_method: ?*const fn (
        obj_type: []const u8,
        method_name: []const u8,
        args: []const []const u8,
    ) ?[]const u8 = null,

    /// Optional: Get type info for a type from this module
    get_type_info: ?*const fn (type_name: []const u8) ?TypeInfo = null,

    /// Optional: Whether this plugin wants to intercept all calls
    intercept_all: bool = false,

    /// Optional: Description for debugging
    description: []const u8 = "",
};

/// Plugin registry - compile-time list of all plugins
pub const PluginRegistry = struct {
    plugins: []const Plugin,

    pub fn init(plugins: []const Plugin) PluginRegistry {
        return .{ .plugins = plugins };
    }

    /// Find plugin for a module
    pub fn getPlugin(self: PluginRegistry, module_name: []const u8) ?Plugin {
        for (self.plugins) |plugin| {
            if (std.mem.eql(u8, plugin.module_name, module_name)) {
                return plugin;
            }
        }
        return null;
    }

    /// Check if module has a plugin
    pub fn hasPlugin(self: PluginRegistry, module_name: []const u8) bool {
        return self.getPlugin(module_name) != null;
    }
};

/// Global plugin registry - populated by individual plugin modules
pub var global_registry: PluginRegistry = PluginRegistry.init(&.{});

/// Initialize plugins (call from main before codegen)
pub fn initPlugins() void {
    // Plugins register themselves when imported
    // This is a placeholder - actual plugins will be added in separate files
}
