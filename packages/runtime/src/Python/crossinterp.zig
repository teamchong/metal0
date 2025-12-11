/// crossinterp - Cross-Interpreter Support
/// Mirrors cpython/Python/crossinterp.c
///
/// Support for communication between sub-interpreters (PEP 554).
/// Handles data sharing, channel-based communication, and interpreter isolation.
///
/// This module has been split into submodules:
/// - data.zig: CrossInterpData, ExceptionInfo, MemoryViewData
/// - channel.zig: Channel implementation
/// - registry.zig: ChannelRegistry and InterpreterRegistry
/// - state.zig: Module state management

const data_mod = @import("crossinterp/data.zig");
const channel_mod = @import("crossinterp/channel.zig");
const registry_mod = @import("crossinterp/registry.zig");
const state_mod = @import("crossinterp/state.zig");

// Re-export data types
pub const InterpID = data_mod.InterpID;
pub const INVALID_INTERP_ID = data_mod.INVALID_INTERP_ID;
pub const MAIN_INTERP_ID = data_mod.MAIN_INTERP_ID;
pub const CrossInterpDataType = data_mod.CrossInterpDataType;
pub const CrossInterpData = data_mod.CrossInterpData;
pub const ExceptionInfo = data_mod.ExceptionInfo;
pub const MemoryViewData = data_mod.MemoryViewData;

// Re-export channel
pub const Channel = channel_mod.Channel;

// Re-export registry types
pub const InterpreterState = registry_mod.InterpreterState;
pub const ChannelRegistry = registry_mod.ChannelRegistry;
pub const InterpreterRegistry = registry_mod.InterpreterRegistry;

// Re-export state functions
pub const init = state_mod.init;
pub const getChannelRegistry = state_mod.getChannelRegistry;
pub const getInterpRegistry = state_mod.getInterpRegistry;
pub const reset = state_mod.reset;

// Re-export tests
test {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(data_mod);
    @import("std").testing.refAllDecls(channel_mod);
    @import("std").testing.refAllDecls(registry_mod);
}
