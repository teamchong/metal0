//! Metal and Accelerate framework integration for macOS.
//!
//! Provides GPU-accelerated vector operations on macOS using:
//! - Accelerate framework (vDSP) for SIMD vector math
//! - Metal framework for GPU compute (batch vector search)
//! - GPU hash table for GROUP BY and Hash JOIN
//!
//! On non-macOS platforms, falls back to pure Zig SIMD implementations.

const std = @import("std");

// Re-export hash table module
pub const hash_table = @import("hash_table.zig");
pub const GPUHashTable = hash_table.GPUHashTable;
pub const HashTableError = hash_table.HashTableError;
const builtin = @import("builtin");

/// Compile-time platform detection
/// Metal and Accelerate are auto-enabled on macOS
pub const is_macos = builtin.os.tag == .macos;
pub const is_apple_silicon = is_macos and builtin.cpu.arch == .aarch64;
pub const use_metal = is_macos; // Metal works on both Intel and ARM
pub const use_accelerate = is_macos;

// =============================================================================
// Metal GPU Backend (Objective-C extern functions)
// =============================================================================

const metal_c = if (is_macos) struct {
    extern fn lanceql_metal_init() c_int;
    extern fn lanceql_metal_load_library(path: [*:0]const u8) c_int;
    extern fn lanceql_metal_cosine_batch(
        query: [*]const f32,
        vectors: [*]const f32,
        scores: [*]f32,
        dim: c_uint,
        num_vectors: c_uint,
    ) c_int;
    extern fn lanceql_metal_dot_batch(
        query: [*]const f32,
        vectors: [*]const f32,
        scores: [*]f32,
        dim: c_uint,
        num_vectors: c_uint,
    ) c_int;
    extern fn lanceql_metal_cleanup() void;
    extern fn lanceql_metal_available() c_int;
    extern fn lanceql_metal_device_name() [*:0]const u8;
    // Batch arithmetic operations (for @logic_table compiled methods)
    extern fn lanceql_metal_batch_mul_scalar(a: [*]const f32, out: [*]f32, scalar: f32, len: c_uint) c_int;
    extern fn lanceql_metal_batch_mul_arrays(a: [*]const f32, b: [*]const f32, out: [*]f32, len: c_uint) c_int;
    extern fn lanceql_metal_batch_mul_arrays_scalar(a: [*]const f32, b: [*]const f32, out: [*]f32, scalar: f32, len: c_uint) c_int;
    extern fn lanceql_metal_batch_add_arrays(a: [*]const f32, b: [*]const f32, out: [*]f32, len: c_uint) c_int;
    extern fn lanceql_metal_batch_sub_arrays(a: [*]const f32, b: [*]const f32, out: [*]f32, len: c_uint) c_int;
    extern fn lanceql_metal_batch_div_arrays(a: [*]const f32, b: [*]const f32, out: [*]f32, len: c_uint) c_int;
} else struct {};

/// Metal GPU state
var gpu_initialized: bool = false;
var gpu_library_loaded: bool = false;

/// Initialize Metal GPU (compiles shaders at runtime - no Xcode needed!)
pub fn initGPU() bool {
    if (comptime !is_macos) return false;
    if (gpu_initialized) return true;

    const result = metal_c.lanceql_metal_init();
    gpu_initialized = (result == 0);
    gpu_library_loaded = gpu_initialized; // Shaders compiled at init time
    return gpu_initialized;
}

/// Check if GPU is available and ready
pub fn isGPUReady() bool {
    if (comptime !is_macos) return false;
    if (!gpu_initialized) {
        _ = initGPU();
    }
    return gpu_initialized;
}

/// Get GPU device name
pub fn getGPUDeviceName() []const u8 {
    if (comptime !is_macos) return "N/A";
    if (!gpu_initialized) return "Not initialized";

    const name_ptr = metal_c.lanceql_metal_device_name();
    return std.mem.span(name_ptr);
}

/// Cleanup GPU resources
pub fn cleanupGPU() void {
    if (comptime !is_macos) return;
    if (gpu_initialized) {
        metal_c.lanceql_metal_cleanup();
        gpu_initialized = false;
        gpu_library_loaded = false;
    }
}

/// GPU-accelerated batch cosine similarity
/// Falls back to CPU if GPU not available
pub fn gpuCosineSimilarityBatch(
    query: []const f32,
    vectors: []const f32,
    dim: usize,
    scores: []f32,
) void {
    const num_vectors = vectors.len / dim;

    if (comptime is_macos) {
        if (gpu_library_loaded) {
            const result = metal_c.lanceql_metal_cosine_batch(
                query.ptr,
                vectors.ptr,
                scores.ptr,
                @intCast(dim),
                @intCast(num_vectors),
            );
            if (result == 0) return; // GPU success
        }
    }

    // Fallback to CPU
    batchCosineSimilarity(query, vectors, dim, scores);
}

/// GPU-accelerated batch dot product
pub fn gpuDotProductBatch(
    query: []const f32,
    vectors: []const f32,
    dim: usize,
    scores: []f32,
) void {
    const num_vectors = vectors.len / dim;

    if (comptime is_macos) {
        if (gpu_library_loaded) {
            const result = metal_c.lanceql_metal_dot_batch(
                query.ptr,
                vectors.ptr,
                scores.ptr,
                @intCast(dim),
                @intCast(num_vectors),
            );
            if (result == 0) return;
        }
    }

    // Fallback: CPU batch
    for (0..num_vectors) |i| {
        scores[i] = dotProduct(query, vectors[i * dim ..][0..dim]);
    }
}

// =============================================================================
// Accelerate Framework (vDSP) - macOS only
// =============================================================================

const c = if (is_macos) @cImport({
    @cInclude("Accelerate/Accelerate.h");
}) else struct {};

/// Dot product of two f32 vectors using vDSP (macOS) or SIMD (fallback)
pub fn dotProduct(a: []const f32, b: []const f32) f32 {
    std.debug.assert(a.len == b.len);

    if (comptime is_macos and use_accelerate) {
        // Use Accelerate framework vDSP
        var result: f32 = 0;
        c.vDSP_dotpr(a.ptr, 1, b.ptr, 1, &result, @intCast(a.len));
        return result;
    } else {
        // Pure Zig SIMD fallback
        return simdDotProduct(a, b);
    }
}

/// Cosine similarity between two vectors
/// Returns value in [-1, 1] where 1 = identical direction
pub fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    std.debug.assert(a.len == b.len);

    if (comptime is_macos and use_accelerate) {
        // Use Accelerate vDSP for all operations
        var dot: f32 = 0;
        var norm_a: f32 = 0;
        var norm_b: f32 = 0;
        const len: c.vDSP_Length = @intCast(a.len);

        c.vDSP_dotpr(a.ptr, 1, b.ptr, 1, &dot, len);
        c.vDSP_dotpr(a.ptr, 1, a.ptr, 1, &norm_a, len);
        c.vDSP_dotpr(b.ptr, 1, b.ptr, 1, &norm_b, len);

        const denom = @sqrt(norm_a) * @sqrt(norm_b);
        return if (denom > 0) dot / denom else 0;
    } else {
        return simdCosineSimilarity(a, b);
    }
}

/// L2 (Euclidean) distance squared between two vectors
pub fn l2DistanceSquared(a: []const f32, b: []const f32) f32 {
    std.debug.assert(a.len == b.len);

    // Pure SIMD is faster than Accelerate for L2 distance
    // (avoids allocation overhead for diff buffer)
    return simdL2DistanceSquared(a, b);
}

/// Threshold for auto-switching to GPU (vectors count)
/// Only Apple Silicon benefits from GPU (zero-copy unified memory)
/// Intel Macs have discrete GPU memory - copy overhead makes CPU faster
const GPU_THRESHOLD: usize = 100_000;

/// Batch cosine similarity: auto-selects GPU or CPU based on workload size
/// Apple Silicon: Uses Metal GPU (zero-copy) for large batches
/// Intel Mac/Other: Uses Accelerate vDSP or SIMD
pub fn batchCosineSimilarity(
    query: []const f32,
    vectors: []const f32,
    dim: usize,
    scores: []f32,
) void {
    const num_vectors = vectors.len / dim;
    std.debug.assert(query.len == dim);
    std.debug.assert(scores.len >= num_vectors);

    // Auto-switch to GPU only on Apple Silicon (unified memory = zero-copy)
    if (comptime is_apple_silicon) {
        if (num_vectors >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_cosine_batch(
                query.ptr,
                vectors.ptr,
                scores.ptr,
                @intCast(dim),
                @intCast(num_vectors),
            );
            if (result == 0) return; // GPU success
        }
    }

    // CPU path (Accelerate vDSP on macOS, SIMD elsewhere)
    for (0..num_vectors) |i| {
        const vec = vectors[i * dim ..][0..dim];
        scores[i] = cosineSimilarity(query, vec);
    }
}

// =============================================================================
// Pure Zig SIMD Fallback
// =============================================================================

const Vec8f = @Vector(8, f32);

/// SIMD dot product (pure Zig)
fn simdDotProduct(a: []const f32, b: []const f32) f32 {
    var sum: Vec8f = @splat(0.0);
    var i: usize = 0;

    // Process 8 floats at a time
    while (i + 8 <= a.len) : (i += 8) {
        const va: Vec8f = a[i..][0..8].*;
        const vb: Vec8f = b[i..][0..8].*;
        sum += va * vb;
    }

    // Horizontal sum
    var result = @reduce(.Add, sum);

    // Scalar tail
    while (i < a.len) : (i += 1) {
        result += a[i] * b[i];
    }

    return result;
}

/// SIMD cosine similarity (pure Zig)
fn simdCosineSimilarity(a: []const f32, b: []const f32) f32 {
    var dot_sum: Vec8f = @splat(0.0);
    var a_sum: Vec8f = @splat(0.0);
    var b_sum: Vec8f = @splat(0.0);
    var i: usize = 0;

    while (i + 8 <= a.len) : (i += 8) {
        const va: Vec8f = a[i..][0..8].*;
        const vb: Vec8f = b[i..][0..8].*;
        dot_sum += va * vb;
        a_sum += va * va;
        b_sum += vb * vb;
    }

    var dot = @reduce(.Add, dot_sum);
    var norm_a = @reduce(.Add, a_sum);
    var norm_b = @reduce(.Add, b_sum);

    // Scalar tail
    while (i < a.len) : (i += 1) {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }

    const denom = @sqrt(norm_a) * @sqrt(norm_b);
    return if (denom > 0) dot / denom else 0;
}

/// SIMD L2 distance squared (pure Zig)
fn simdL2DistanceSquared(a: []const f32, b: []const f32) f32 {
    var sum: Vec8f = @splat(0.0);
    var i: usize = 0;

    while (i + 8 <= a.len) : (i += 8) {
        const va: Vec8f = a[i..][0..8].*;
        const vb: Vec8f = b[i..][0..8].*;
        const diff = va - vb;
        sum += diff * diff;
    }

    var result = @reduce(.Add, sum);

    while (i < a.len) : (i += 1) {
        const diff = a[i] - b[i];
        result += diff * diff;
    }

    return result;
}

// =============================================================================
// Batch Arithmetic Operations (for @logic_table compiled methods)
// =============================================================================

/// GPU batch multiply by scalar: out[i] = a[i] * scalar
/// Falls back to CPU SIMD if GPU not available or for small batches
pub fn gpuBatchMulScalar(a: []const f32, scalar: f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_mul_scalar(
                a.ptr,
                out.ptr,
                scalar,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] * scalar;
    }
}

/// GPU batch multiply two arrays: out[i] = a[i] * b[i]
pub fn gpuBatchMulArrays(a: []const f32, b: []const f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(b.len == len);
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_mul_arrays(
                a.ptr,
                b.ptr,
                out.ptr,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] * b[i];
    }
}

/// GPU batch multiply two arrays with scalar: out[i] = a[i] * b[i] * scalar
pub fn gpuBatchMulArraysScalar(a: []const f32, b: []const f32, scalar: f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(b.len == len);
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_mul_arrays_scalar(
                a.ptr,
                b.ptr,
                out.ptr,
                scalar,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] * b[i] * scalar;
    }
}

/// GPU batch add: out[i] = a[i] + b[i]
pub fn gpuBatchAddArrays(a: []const f32, b: []const f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(b.len == len);
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_add_arrays(
                a.ptr,
                b.ptr,
                out.ptr,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] + b[i];
    }
}

/// GPU batch subtract: out[i] = a[i] - b[i]
pub fn gpuBatchSubArrays(a: []const f32, b: []const f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(b.len == len);
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_sub_arrays(
                a.ptr,
                b.ptr,
                out.ptr,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] - b[i];
    }
}

/// GPU batch divide: out[i] = a[i] / b[i]
pub fn gpuBatchDivArrays(a: []const f32, b: []const f32, out: []f32) void {
    const len = a.len;
    std.debug.assert(b.len == len);
    std.debug.assert(out.len >= len);

    if (comptime is_apple_silicon) {
        if (len >= GPU_THRESHOLD and isGPUReady()) {
            const result = metal_c.lanceql_metal_batch_div_arrays(
                a.ptr,
                b.ptr,
                out.ptr,
                @intCast(len),
            );
            if (result == 0) return;
        }
    }

    // CPU SIMD fallback
    for (0..len) |i| {
        out[i] = a[i] / b[i];
    }
}

// =============================================================================
// Metal GPU Support (Future)
// =============================================================================

/// Check if Metal is available at runtime
pub fn isMetalAvailable() bool {
    if (comptime !is_macos) return false;
    if (comptime !use_metal) return false;

    // Use the C Metal API to check for device availability
    return metal_c.lanceql_metal_available() != 0;
}

/// Get platform info string
pub fn getPlatformInfo() []const u8 {
    if (comptime is_apple_silicon) {
        if (gpu_initialized) {
            return "Apple Silicon (Metal GPU + Accelerate)";
        } else {
            return "Apple Silicon (Accelerate vDSP)";
        }
    } else if (comptime is_macos) {
        return "Intel Mac (Accelerate vDSP)";
    } else if (comptime builtin.os.tag == .linux) {
        return "Linux (SIMD)";
    } else if (comptime builtin.os.tag == .windows) {
        return "Windows (SIMD)";
    } else {
        return "Unknown (SIMD)";
    }
}

// =============================================================================
// Tests
// =============================================================================

test "dot product" {
    const a = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    const b = [_]f32{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };

    const result = dotProduct(&a, &b);
    // 1+2+3+4+5+6+7+8 = 36
    try std.testing.expectApproxEqAbs(@as(f32, 36.0), result, 0.001);
}

test "cosine similarity identical vectors" {
    const a = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const b = [_]f32{ 1.0, 2.0, 3.0, 4.0 };

    const result = cosineSimilarity(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result, 0.001);
}

test "cosine similarity orthogonal vectors" {
    const a = [_]f32{ 1.0, 0.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0, 0.0 };

    const result = cosineSimilarity(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result, 0.001);
}

test "L2 distance squared" {
    const a = [_]f32{ 0.0, 0.0, 0.0 };
    const b = [_]f32{ 3.0, 4.0, 0.0 };

    const result = l2DistanceSquared(&a, &b);
    // 3^2 + 4^2 = 25
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), result, 0.001);
}

test "platform info" {
    const info = getPlatformInfo();
    try std.testing.expect(info.len > 0);
    std.debug.print("Platform: {s}\n", .{info});
}
