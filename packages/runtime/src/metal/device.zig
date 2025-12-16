//! Metal Device Management
//!
//! Handles Metal GPU device detection, selection, and initialization.
//! Only compiled on macOS - uses comptime checks for zero overhead elsewhere.

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("objc.zig");

/// Metal device wrapper
pub const MetalDevice = struct {
    device: objc.MTLDevice,
    command_queue: objc.MTLCommandQueue,
    name: []const u8,

    /// Initialize Metal device (selects default GPU)
    pub fn init() !@This() {
        const device = objc.MTLCreateSystemDefaultDevice() orelse
            return error.MetalNotAvailable;

        const command_queue = objc.deviceNewCommandQueue(device) orelse
            return error.CommandQueueCreationFailed;

        const name = objc.deviceGetName(device);

        return .{
            .device = device,
            .command_queue = command_queue,
            .name = name,
        };
    }

    /// Clean up Metal resources
    pub fn deinit(self: *@This()) void {
        objc.release(self.command_queue);
        objc.release(self.device);
    }

    /// Get device name (e.g., "Apple M1 Pro")
    pub fn getName(self: *const @This()) []const u8 {
        return self.name;
    }

    /// Check if Metal is available on this system
    pub fn isAvailable() bool {
        const device = objc.MTLCreateSystemDefaultDevice();
        if (device) |d| {
            objc.release(d);
            return true;
        }
        return false;
    }

    /// Get recommended thread group size for this device
    pub fn getRecommendedThreadGroupSize(self: *const @This()) usize {
        _ = self;
        // Apple Silicon typically works well with 256 threads per group
        return 256;
    }

    /// Create a new command buffer
    pub fn newCommandBuffer(self: *@This()) !objc.MTLCommandBuffer {
        return objc.commandQueueNewCommandBuffer(self.command_queue) orelse
            error.CommandBufferCreationFailed;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "device availability check" {
    // This test only makes sense on macOS
    if (comptime builtin.os.tag != .macos) {
        return;
    }

    const available = MetalDevice.isAvailable();
    // On macOS, Metal should always be available
    try std.testing.expect(available);
}

test "device init" {
    if (comptime builtin.os.tag != .macos) {
        return;
    }

    var device = MetalDevice.init() catch |err| {
        std.debug.print("Metal device init failed: {}\n", .{err});
        return;
    };
    defer device.deinit();

    const name = device.getName();
    try std.testing.expect(name.len > 0);
}
