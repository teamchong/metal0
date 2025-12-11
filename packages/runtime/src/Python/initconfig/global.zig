/// Global Configuration State
/// Mirrors cpython/Python/initconfig.c - global configuration
///
/// This module manages the global Python configuration instance.
/// Used by the interpreter to access configuration at runtime.

const PyConfig = @import("config.zig").PyConfig;

var g_config: ?PyConfig = null;

/// Get global configuration
pub fn getConfig() ?*PyConfig {
    if (g_config) |*config| {
        return config;
    }
    return null;
}

/// Set global configuration
pub fn setConfig(config: *const PyConfig) void {
    g_config = config.*;
}

/// Clear global configuration
pub fn clearConfig() void {
    g_config = null;
}
