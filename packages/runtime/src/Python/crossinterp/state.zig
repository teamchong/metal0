/// Module State Management
/// Global state for crossinterp module

const std = @import("std");
const Allocator = std.mem.Allocator;
const registry_mod = @import("registry.zig");

const ChannelRegistry = registry_mod.ChannelRegistry;
const InterpreterRegistry = registry_mod.InterpreterRegistry;

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var channel_registry: ?ChannelRegistry = null;
var interp_registry: ?InterpreterRegistry = null;

/// Initialize the crossinterp module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get channel registry
pub fn getChannelRegistry(allocator: Allocator) *ChannelRegistry {
    if (channel_registry == null) {
        channel_registry = ChannelRegistry.init(allocator);
    }
    return &channel_registry.?;
}

/// Get interpreter registry
pub fn getInterpRegistry(allocator: Allocator) *InterpreterRegistry {
    if (interp_registry == null) {
        interp_registry = InterpreterRegistry.init(allocator);
    }
    return &interp_registry.?;
}

/// Reset module state
pub fn reset() void {
    if (channel_registry) |*reg| {
        reg.deinit();
    }
    if (interp_registry) |*reg| {
        reg.deinit();
    }
    channel_registry = null;
    interp_registry = null;
    initialized = false;
}
