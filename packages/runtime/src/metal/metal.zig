//! Metal GPU Acceleration Module
//!
//! Provides GPU-accelerated operations for tensor/array computations on macOS.
//! Uses comptime checks to eliminate dead code on non-macOS platforms.
//!
//! Pattern from zell: conditional compilation with zero overhead on other platforms.

const std = @import("std");
const builtin = @import("builtin");

/// Comptime check for Metal availability
/// This is the single source of truth for Metal support
pub const use_metal = builtin.os.tag == .macos;

/// Metal device handle (opaque on non-macOS)
pub const Device = if (use_metal)
    @import("device.zig").MetalDevice
else
    CpuFallbackDevice;

/// CPU fallback device stub for non-macOS platforms
pub const CpuFallbackDevice = struct {
    pub fn init() !@This() {
        return .{};
    }

    pub fn deinit(_: *@This()) void {}

    pub fn getName(_: *const @This()) []const u8 {
        return "CPU (Metal not available)";
    }

    pub fn isAvailable() bool {
        return false;
    }
};

/// GPU buffer for tensor data
pub const Buffer = if (use_metal)
    @import("buffers.zig").MetalBuffer
else
    CpuBuffer;

/// CPU buffer fallback
pub const CpuBuffer = struct {
    data: []f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize) !@This() {
        return .{
            .data = try allocator.alloc(f32, size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.data);
    }

    pub fn getContents(self: *@This()) []f32 {
        return self.data;
    }
};

/// Shader/kernel manager
pub const Shaders = if (use_metal)
    @import("shaders.zig").ShaderManager
else
    CpuShaderStub;

/// CPU shader stub
pub const CpuShaderStub = struct {
    pub fn init(_: std.mem.Allocator) !@This() {
        return .{};
    }

    pub fn deinit(_: *@This()) void {}

    pub fn compile(_: *@This()) !void {}
};

// ============================================================================
// High-level tensor operations
// These dispatch to Metal or CPU based on comptime platform check
// ============================================================================

/// Matrix multiplication: C = A @ B
/// Dispatches to Metal GPU or CPU BLAS based on platform
pub fn matmul(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
    m: usize,
    n: usize,
    k: usize,
) ![]f32 {
    if (comptime use_metal) {
        return @import("kernels/matmul.zig").metalMatmul(allocator, a, b, m, n, k);
    } else {
        return cpuMatmul(allocator, a, b, m, n, k);
    }
}

/// CPU fallback for matrix multiplication
fn cpuMatmul(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
    m: usize,
    n: usize,
    k: usize,
) ![]f32 {
    const c = try allocator.alloc(f32, m * n);
    @memset(c, 0);

    // Simple triple-loop matmul (could use BLAS for better perf)
    for (0..m) |i| {
        for (0..n) |j| {
            var acc: f32 = 0;
            for (0..k) |kk| {
                acc += a[i * k + kk] * b[kk * n + j];
            }
            c[i * n + j] = acc;
        }
    }

    return c;
}

/// Element-wise addition: C = A + B
pub fn add(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    if (comptime use_metal) {
        return @import("kernels/elementwise.zig").metalAdd(allocator, a, b);
    } else {
        return cpuAdd(allocator, a, b);
    }
}

fn cpuAdd(allocator: std.mem.Allocator, a: []const f32, b: []const f32) ![]f32 {
    const c = try allocator.alloc(f32, a.len);
    for (0..a.len) |i| {
        c[i] = a[i] + b[i];
    }
    return c;
}

/// Element-wise multiplication: C = A * B
pub fn mul(
    allocator: std.mem.Allocator,
    a: []const f32,
    b: []const f32,
) ![]f32 {
    if (comptime use_metal) {
        return @import("kernels/elementwise.zig").metalMul(allocator, a, b);
    } else {
        return cpuMul(allocator, a, b);
    }
}

fn cpuMul(allocator: std.mem.Allocator, a: []const f32, b: []const f32) ![]f32 {
    const c = try allocator.alloc(f32, a.len);
    for (0..a.len) |i| {
        c[i] = a[i] * b[i];
    }
    return c;
}

/// Sum reduction
pub fn sum(a: []const f32) f32 {
    var result: f32 = 0;
    for (a) |val| {
        result += val;
    }
    return result;
}

// ============================================================================
// List Comprehension Vectorization
// These are used by the compiler for automatic GPU acceleration of patterns like:
//   [x * 2 for x in range(1_000_000)]
// ============================================================================

/// List comprehension kernel module
pub const listcomp = @import("kernels/listcomp.zig");

/// Vectorized list comprehension operation type
pub const VectorOp = listcomp.VectorOp;

/// GPU-accelerated list comprehension: [op(x, constant) for x in range(start, end)]
/// Automatically uses Metal GPU on macOS for large arrays (>10K elements)
pub const vectorizedListComp = listcomp.vectorizedListComp;

/// Returns ArrayList for runtime compatibility
pub const vectorizedListCompToArrayList = listcomp.vectorizedListCompToArrayList;

// ============================================================================
// Tests
// ============================================================================

test "matmul basic" {
    const allocator = std.testing.allocator;

    // 2x3 @ 3x2 = 2x2
    const a = [_]f32{ 1, 2, 3, 4, 5, 6 };
    const b = [_]f32{ 7, 8, 9, 10, 11, 12 };

    const c = try matmul(allocator, &a, &b, 2, 2, 3);
    defer allocator.free(c);

    // Expected: [[58, 64], [139, 154]]
    try std.testing.expectApproxEqAbs(@as(f32, 58), c[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 64), c[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 139), c[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 154), c[3], 0.001);
}

test "add basic" {
    const allocator = std.testing.allocator;

    const a = [_]f32{ 1, 2, 3 };
    const b = [_]f32{ 4, 5, 6 };

    const c = try add(allocator, &a, &b);
    defer allocator.free(c);

    try std.testing.expectApproxEqAbs(@as(f32, 5), c[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), c[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 9), c[2], 0.001);
}
