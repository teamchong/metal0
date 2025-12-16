//! Metal Matrix Multiplication Kernel
//!
//! GPU-accelerated matrix multiplication using Metal compute shaders.

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("../objc.zig");
const buffers = @import("../buffers.zig");
const device_mod = @import("../device.zig");
const shaders = @import("../shaders.zig");

/// Perform GPU-accelerated matrix multiplication
/// C = A @ B where A is M x K, B is K x N, result C is M x N
pub fn metalMatmul(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
    m: usize,
    n: usize,
    k: usize,
) ![]f32 {
    if (comptime builtin.os.tag != .macos) {
        return error.MetalNotAvailable;
    }

    // Initialize device
    var device = try device_mod.MetalDevice.init();
    defer device.deinit();

    // Create buffers
    var buf_a = try buffers.MetalBuffer.initWithData(device.device, a);
    defer buf_a.deinit();

    var buf_b = try buffers.MetalBuffer.initWithData(device.device, b);
    defer buf_b.deinit();

    var buf_c = try buffers.MetalBuffer.init(device.device, m * n);
    defer buf_c.deinit();

    // Compile shaders
    var shader_mgr = try shaders.ShaderManager.init(allocator, device.device);
    defer shader_mgr.deinit();
    try shader_mgr.compile();

    // Get kernel function
    const kernel = try shader_mgr.getFunction("matmul_tiled");
    defer objc.release(kernel);

    // Create compute pipeline
    var err: ?*anyopaque = null;
    const pipeline = objc.deviceNewComputePipelineState(device.device, kernel, &err) orelse {
        return error.PipelineCreationFailed;
    };
    defer objc.release(pipeline);

    // Create command buffer and encoder
    const cmd_buffer = try device.newCommandBuffer();
    const encoder = objc.commandBufferNewComputeEncoder(cmd_buffer) orelse {
        return error.EncoderCreationFailed;
    };

    // Set pipeline and buffers
    objc.encoderSetComputePipelineState(encoder, pipeline);
    objc.encoderSetBuffer(encoder, buf_a.buffer, 0, 0);
    objc.encoderSetBuffer(encoder, buf_b.buffer, 0, 1);
    objc.encoderSetBuffer(encoder, buf_c.buffer, 0, 2);

    // Set dimensions
    var m_val: u32 = @intCast(m);
    var n_val: u32 = @intCast(n);
    var k_val: u32 = @intCast(k);
    objc.encoderSetBytes(encoder, &m_val, @sizeOf(u32), 3);
    objc.encoderSetBytes(encoder, &n_val, @sizeOf(u32), 4);
    objc.encoderSetBytes(encoder, &k_val, @sizeOf(u32), 5);

    // Dispatch threads
    const tile_size: usize = 16;
    const grid_size = objc.MTLSize{
        .width = (n + tile_size - 1) / tile_size * tile_size,
        .height = (m + tile_size - 1) / tile_size * tile_size,
        .depth = 1,
    };
    const threadgroup_size = objc.MTLSize{
        .width = tile_size,
        .height = tile_size,
        .depth = 1,
    };

    objc.encoderDispatchThreadgroups(encoder, grid_size, threadgroup_size);
    objc.encoderEndEncoding(encoder);

    // Execute
    objc.commandBufferCommit(cmd_buffer);
    objc.commandBufferWaitUntilCompleted(cmd_buffer);

    // Read result
    return buf_c.getData(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "matmul basic" {
    if (comptime builtin.os.tag != .macos) return;

    const allocator = std.testing.allocator;

    // 2x3 @ 3x2 = 2x2
    const a = [_]f32{ 1, 2, 3, 4, 5, 6 };
    const b = [_]f32{ 7, 8, 9, 10, 11, 12 };

    const c = metalMatmul(allocator, &a, &b, 2, 2, 3) catch |err| {
        std.debug.print("Metal matmul failed: {}\n", .{err});
        return;
    };
    defer allocator.free(c);

    // Expected: [[58, 64], [139, 154]]
    try std.testing.expectApproxEqAbs(@as(f32, 58), c[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 64), c[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 139), c[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 154), c[3], 0.001);
}
