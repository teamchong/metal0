//! Batch Vector Similarity Operations
//!
//! GPU-accelerated batch vector operations for similarity search.
//! Uses Metal on macOS, SIMD fallback on other platforms.
//!
//! Tiered dispatch:
//!   - < 10K vectors: CPU SIMD (lower overhead)
//!   - >= 10K vectors: GPU Metal (higher throughput)

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("../objc.zig");
const buffers = @import("../buffers.zig");
const device_mod = @import("../device.zig");
const shaders = @import("../shaders.zig");

/// Threshold for GPU dispatch (transfer overhead break-even point)
pub const GPU_THRESHOLD: usize = 10_000;

/// Batch dot product: compute dot product of query with each vector
/// Returns array of dot products
pub fn batchDotProduct(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    // Tiered dispatch based on batch size
    if (num_vectors >= GPU_THRESHOLD and comptime builtin.os.tag == .macos) {
        return metalBatchDotProduct(allocator, query, vectors, num_vectors, dim);
    } else {
        return simdBatchDotProduct(allocator, query, vectors, num_vectors, dim);
    }
}

/// Batch cosine similarity
pub fn batchCosineSim(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    if (num_vectors >= GPU_THRESHOLD and comptime builtin.os.tag == .macos) {
        return metalBatchCosineSim(allocator, query, vectors, num_vectors, dim);
    } else {
        return simdBatchCosineSim(allocator, query, vectors, num_vectors, dim);
    }
}

/// Batch L2 distance
pub fn batchL2Distance(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    if (num_vectors >= GPU_THRESHOLD and comptime builtin.os.tag == .macos) {
        return metalBatchL2Distance(allocator, query, vectors, num_vectors, dim);
    } else {
        return simdBatchL2Distance(allocator, query, vectors, num_vectors, dim);
    }
}

// ============================================================================
// SIMD CPU Implementation (for small batches or non-macOS)
// ============================================================================

fn simdBatchDotProduct(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    const output = try allocator.alloc(f32, num_vectors);

    for (0..num_vectors) |i| {
        const base = i * dim;
        const vec = vectors[base..][0..dim];
        output[i] = simdDotProduct(query[0..dim], vec);
    }

    return output;
}

fn simdBatchCosineSim(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    const output = try allocator.alloc(f32, num_vectors);

    // Pre-compute query norm
    const norm_q = @sqrt(simdDotProduct(query[0..dim], query[0..dim]));

    for (0..num_vectors) |i| {
        const base = i * dim;
        const vec = vectors[base..][0..dim];
        const dot = simdDotProduct(query[0..dim], vec);
        const norm_v = @sqrt(simdDotProduct(vec, vec));
        const denom = norm_q * norm_v;
        output[i] = if (denom > 0) dot / denom else 0;
    }

    return output;
}

fn simdBatchL2Distance(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    const output = try allocator.alloc(f32, num_vectors);

    for (0..num_vectors) |i| {
        const base = i * dim;
        const vec = vectors[base..][0..dim];
        output[i] = simdL2Distance(query[0..dim], vec);
    }

    return output;
}

/// SIMD dot product using 4-element vectors
fn simdDotProduct(a: []const f32, b: []const f32) f32 {
    const Vec4 = @Vector(4, f32);
    var sum_vec: Vec4 = @splat(0);
    var i: usize = 0;
    const simd_end = a.len & ~@as(usize, 3);

    while (i < simd_end) : (i += 4) {
        const a_vec: Vec4 = a[i..][0..4].*;
        const b_vec: Vec4 = b[i..][0..4].*;
        sum_vec += a_vec * b_vec;
    }

    var sum = @reduce(.Add, sum_vec);
    while (i < a.len) : (i += 1) {
        sum += a[i] * b[i];
    }

    return sum;
}

/// SIMD L2 distance
fn simdL2Distance(a: []const f32, b: []const f32) f32 {
    const Vec4 = @Vector(4, f32);
    var sum_vec: Vec4 = @splat(0);
    var i: usize = 0;
    const simd_end = a.len & ~@as(usize, 3);

    while (i < simd_end) : (i += 4) {
        const a_vec: Vec4 = a[i..][0..4].*;
        const b_vec: Vec4 = b[i..][0..4].*;
        const diff = a_vec - b_vec;
        sum_vec += diff * diff;
    }

    var sum = @reduce(.Add, sum_vec);
    while (i < a.len) : (i += 1) {
        const diff = a[i] - b[i];
        sum += diff * diff;
    }

    return @sqrt(sum);
}

// ============================================================================
// Metal GPU Implementation (for large batches on macOS)
// ============================================================================

fn metalBatchDotProduct(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    if (comptime builtin.os.tag != .macos) {
        return error.MetalNotAvailable;
    }

    var device = try device_mod.MetalDevice.init();
    defer device.deinit();

    // Create buffers
    var buf_query = try buffers.MetalBuffer.initWithData(device.device, query);
    defer buf_query.deinit();

    var buf_vectors = try buffers.MetalBuffer.initWithData(device.device, vectors);
    defer buf_vectors.deinit();

    var buf_output = try buffers.MetalBuffer.init(device.device, num_vectors);
    defer buf_output.deinit();

    // Compile and run kernel
    var shader_mgr = try shaders.ShaderManager.init(allocator, device.device);
    defer shader_mgr.deinit();
    try shader_mgr.compile();

    const kernel = try shader_mgr.getFunction("batch_dot_product");
    defer objc.release(kernel);

    try runBatchKernel(device, kernel, buf_query.buffer, buf_vectors.buffer, buf_output.buffer, dim, num_vectors);

    return buf_output.getData(allocator);
}

fn metalBatchCosineSim(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    if (comptime builtin.os.tag != .macos) {
        return error.MetalNotAvailable;
    }

    var device = try device_mod.MetalDevice.init();
    defer device.deinit();

    var buf_query = try buffers.MetalBuffer.initWithData(device.device, query);
    defer buf_query.deinit();

    var buf_vectors = try buffers.MetalBuffer.initWithData(device.device, vectors);
    defer buf_vectors.deinit();

    var buf_output = try buffers.MetalBuffer.init(device.device, num_vectors);
    defer buf_output.deinit();

    var shader_mgr = try shaders.ShaderManager.init(allocator, device.device);
    defer shader_mgr.deinit();
    try shader_mgr.compile();

    const kernel = try shader_mgr.getFunction("batch_cosine_sim");
    defer objc.release(kernel);

    try runBatchKernel(device, kernel, buf_query.buffer, buf_vectors.buffer, buf_output.buffer, dim, num_vectors);

    return buf_output.getData(allocator);
}

fn metalBatchL2Distance(
    allocator: std.mem.Allocator,
    query: []const f32,
    vectors: []const f32,
    num_vectors: usize,
    dim: usize,
) ![]f32 {
    if (comptime builtin.os.tag != .macos) {
        return error.MetalNotAvailable;
    }

    var device = try device_mod.MetalDevice.init();
    defer device.deinit();

    var buf_query = try buffers.MetalBuffer.initWithData(device.device, query);
    defer buf_query.deinit();

    var buf_vectors = try buffers.MetalBuffer.initWithData(device.device, vectors);
    defer buf_vectors.deinit();

    var buf_output = try buffers.MetalBuffer.init(device.device, num_vectors);
    defer buf_output.deinit();

    var shader_mgr = try shaders.ShaderManager.init(allocator, device.device);
    defer shader_mgr.deinit();
    try shader_mgr.compile();

    const kernel = try shader_mgr.getFunction("batch_l2_distance");
    defer objc.release(kernel);

    try runBatchKernel(device, kernel, buf_query.buffer, buf_vectors.buffer, buf_output.buffer, dim, num_vectors);

    return buf_output.getData(allocator);
}

/// Run a batch vector kernel
fn runBatchKernel(
    device: device_mod.MetalDevice,
    kernel: objc.MTLFunction,
    buf_query: objc.MTLBuffer,
    buf_vectors: objc.MTLBuffer,
    buf_output: objc.MTLBuffer,
    dim: usize,
    num_vectors: usize,
) !void {
    var err: ?*anyopaque = null;
    const pipeline = objc.deviceNewComputePipelineState(device.device, kernel, &err) orelse {
        return error.PipelineCreationFailed;
    };
    defer objc.release(pipeline);

    const cmd_buffer = try device.newCommandBuffer();
    const encoder = objc.commandBufferNewComputeEncoder(cmd_buffer) orelse {
        return error.EncoderCreationFailed;
    };

    objc.encoderSetComputePipelineState(encoder, pipeline);
    objc.encoderSetBuffer(encoder, buf_query, 0, 0);
    objc.encoderSetBuffer(encoder, buf_vectors, 0, 1);
    objc.encoderSetBuffer(encoder, buf_output, 0, 2);

    var dim_val: u32 = @intCast(dim);
    var num_val: u32 = @intCast(num_vectors);
    objc.encoderSetBytes(encoder, &dim_val, @sizeOf(u32), 3);
    objc.encoderSetBytes(encoder, &num_val, @sizeOf(u32), 4);

    // Dispatch one thread per vector
    const thread_count = num_vectors;
    const threadgroup_size: usize = 256;
    const grid_size = objc.MTLSize{
        .width = (thread_count + threadgroup_size - 1) / threadgroup_size * threadgroup_size,
        .height = 1,
        .depth = 1,
    };
    const tg_size = objc.MTLSize{
        .width = threadgroup_size,
        .height = 1,
        .depth = 1,
    };

    objc.encoderDispatchThreadgroups(encoder, grid_size, tg_size);
    objc.encoderEndEncoding(encoder);

    objc.commandBufferCommit(cmd_buffer);
    objc.commandBufferWaitUntilCompleted(cmd_buffer);
}

// ============================================================================
// Tests
// ============================================================================

test "simd dot product" {
    const a = [_]f32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const b = [_]f32{ 1, 1, 1, 1, 1, 1, 1, 1 };
    const result = simdDotProduct(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f32, 36), result, 0.001);
}

test "simd batch dot product" {
    const allocator = std.testing.allocator;

    const query = [_]f32{ 1, 0, 0, 0 };
    const vectors = [_]f32{
        1, 0, 0, 0, // dot = 1
        0, 1, 0, 0, // dot = 0
        0.5, 0.5, 0, 0, // dot = 0.5
    };

    const result = try simdBatchDotProduct(allocator, &query, &vectors, 3, 4);
    defer allocator.free(result);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result[2], 0.001);
}
