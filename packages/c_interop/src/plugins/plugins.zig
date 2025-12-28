//! Plugin Index
//!
//! Central registry of all available external library plugins.
//! Add new plugins here to enable custom handling for external libraries.

const plugin = @import("plugin.zig");
const numpy_plugin = @import("numpy_plugin.zig");

/// All registered plugins
pub const all_plugins = [_]plugin.Plugin{
    numpy_plugin.numpy_plugin,
    // Add more plugins here:
    // pandas_plugin.pandas_plugin,
    // torch_plugin.torch_plugin,
};

/// Global plugin registry
pub const registry = plugin.PluginRegistry.init(&all_plugins);

/// Re-export core plugin types
pub const Plugin = plugin.Plugin;
pub const TypeInfo = plugin.TypeInfo;
pub const InterceptResult = plugin.InterceptResult;
pub const PluginRegistry = plugin.PluginRegistry;

/// Convenience function to get a plugin by module name
pub fn getPlugin(module_name: []const u8) ?plugin.Plugin {
    return registry.getPlugin(module_name);
}

/// Check if a module has a plugin
pub fn hasPlugin(module_name: []const u8) bool {
    return registry.hasPlugin(module_name);
}

test "plugin registry" {
    const np = getPlugin("numpy");
    if (np) |_| {
        // numpy plugin found
    }

    const has_np = hasPlugin("numpy");
    _ = has_np;
}
