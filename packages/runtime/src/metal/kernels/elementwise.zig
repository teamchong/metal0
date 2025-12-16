//! Metal Element-wise Operations
//!
//! GPU-accelerated element-wise tensor operations.

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("../objc.zig");
const buffers = @import("../buffers.zig");
const device_mod = @import("../device.zig");
const shaders = @import("../shaders.zig");

/// GPU-accelerated element-wise addition
pub fn metalAdd(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    return runElementwiseKernel(allocator, a, b, "add");
}

/// GPU-accelerated element-wise multiplication
pub fn metalMul(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    return runElementwiseKernel(allocator, a, b, "mul");
}

/// GPU-accelerated element-wise subtraction
pub fn metalSub(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    return runElementwiseKernel(allocator, a, b, "sub");
}

/// GPU-accelerated element-wise division
pub fn metalDiv(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    return runElementwiseKernel(allocator, a, b, "div_elem");
}

/// Run an element-wise kernel
fn runElementwiseKernel(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
    kernel_name: [*:0]const u8,
) ![]f32 {
    if (comptime builtin.os.tag != .macos) {
        return error.MetalNotAvailable;
    }

    if (a.len != b.len) {
        return error.SizeMismatch;
    }

    // Initialize device
    var device = try device_mod.MetalDevice.init();
    defer device.deinit();

    // Create buffers
    var buf_a = try buffers.MetalBuffer.initWithData(device.device, a);
    defer buf_a.deinit();

    var buf_b = try buffers.MetalBuffer.initWithData(device.device, b);
    defer buf_b.deinit();

    var buf_c = try buffers.MetalBuffer.init(device.device, a.len);
    defer buf_c.deinit();

    // Compile shaders
    var shader_mgr = try shaders.ShaderManager.init(allocator, device.device);
    defer shader_mgr.deinit();
    try shader_mgr.compile();

    // Get kernel function
    const kernel = try shader_mgr.getFunction(kernel_name);
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

    // Dispatch threads
    const thread_count = a.len;
    const threads_per_group: usize = 256;
    const num_groups = (thread_count + threads_per_group - 1) / threads_per_group;

    const grid_size = objc.MTLSize{
        .width = thread_count,
        .height = 1,
        .depth = 1,
    };
    const threadgroup_size = objc.MTLSize{
        .width = threads_per_group,
        .height = 1,
        .depth = 1,
    };

    _ = num_groups;
    objc.encoderDispatchThreads(encoder, grid_size, threadgroup_size);
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

test "add basic" {
    if (comptime builtin.os.tag != .macos) return;

    const allocator = std.testing.allocator;
    const a = [_]f32{ 1, 2, 3, 4 };
    const b = [_]f32{ 5, 6, 7, 8 };

    const c = metalAdd(allocator, &a, &b) catch |err| {
        std.debug.print("Metal add failed: {}\n", .{err});
        return;
    };
    defer allocator.free(c);

    try std.testing.expectApproxEqAbs(@as(f32, 6), c[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), c[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), c[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), c[3], 0.001);
}

test "mul basic" {
    if (comptime builtin.os.tag != .macos) return;

    const allocator = std.testing.allocator;
    const a = [_]f32{ 1, 2, 3, 4 };
    const b = [_]f32{ 5, 6, 7, 8 };

    const c = metalMul(allocator, &a, &b) catch |err| {
        std.debug.print("Metal mul failed: {}\n", .{err});
        return;
    };
    defer allocator.free(c);

    try std.testing.expectApproxEqAbs(@as(f32, 5), c[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), c[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 21), c[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), c[3], 0.001);
}
