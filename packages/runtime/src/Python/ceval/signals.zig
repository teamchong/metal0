/// Signal handling for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Signal pending flag
var signal_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Stop the world flag
var stop_the_world_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Trip signal flag
pub fn tripSignal() void {
    signal_pending.store(true, .release);
}

/// Check and clear signal
pub fn checkAndClearSignal() bool {
    return signal_pending.swap(false, .acq_rel);
}

/// Request stop-the-world
pub fn stopTheWorld() void {
    stop_the_world_requested.store(true, .release);
}

/// Resume from stop-the-world
pub fn startTheWorld() void {
    stop_the_world_requested.store(false, .release);
}

/// Check if stop-the-world is requested
pub fn isWorldStopped() bool {
    return stop_the_world_requested.load(.acquire);
}
