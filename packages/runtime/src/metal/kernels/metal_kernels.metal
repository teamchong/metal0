// Metal GPU Kernels for metal0
//
// High-performance GPU kernels for tensor operations.
// Compiled to .metallib at runtime with caching.

#include <metal_stdlib>
using namespace metal;

// ============================================================================
// Matrix Multiplication
// ============================================================================

/// Matrix multiplication: C = A @ B
/// A is M x K, B is K x N, C is M x N
kernel void matmul(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    constant uint& M [[buffer(3)]],
    constant uint& N [[buffer(4)]],
    constant uint& K [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Each thread computes one element of C
    uint row = gid.y;
    uint col = gid.x;

    if (row >= M || col >= N) return;

    float sum = 0.0f;
    for (uint k = 0; k < K; k++) {
        sum += A[row * K + k] * B[k * N + col];
    }
    C[row * N + col] = sum;
}

/// Tiled matrix multiplication for better cache utilization
/// Uses shared memory (threadgroup) for tile-based computation
#define TILE_SIZE 16

kernel void matmul_tiled(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    constant uint& M [[buffer(3)]],
    constant uint& N [[buffer(4)]],
    constant uint& K [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    // Shared memory tiles
    threadgroup float tileA[TILE_SIZE][TILE_SIZE];
    threadgroup float tileB[TILE_SIZE][TILE_SIZE];

    uint row = tgid.y * TILE_SIZE + lid.y;
    uint col = tgid.x * TILE_SIZE + lid.x;

    float sum = 0.0f;

    // Process tiles
    uint numTiles = (K + TILE_SIZE - 1) / TILE_SIZE;
    for (uint t = 0; t < numTiles; t++) {
        // Load tile into shared memory
        uint tiledRow = tgid.y * TILE_SIZE + lid.y;
        uint tiledCol = t * TILE_SIZE + lid.x;

        if (tiledRow < M && tiledCol < K) {
            tileA[lid.y][lid.x] = A[tiledRow * K + tiledCol];
        } else {
            tileA[lid.y][lid.x] = 0.0f;
        }

        tiledRow = t * TILE_SIZE + lid.y;
        tiledCol = tgid.x * TILE_SIZE + lid.x;

        if (tiledRow < K && tiledCol < N) {
            tileB[lid.y][lid.x] = B[tiledRow * N + tiledCol];
        } else {
            tileB[lid.y][lid.x] = 0.0f;
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Compute partial sum
        for (uint k = 0; k < TILE_SIZE; k++) {
            sum += tileA[lid.y][k] * tileB[k][lid.x];
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // Write result
    if (row < M && col < N) {
        C[row * N + col] = sum;
    }
}

// ============================================================================
// Element-wise Operations
// ============================================================================

/// Element-wise addition: C = A + B
kernel void add(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] + B[gid];
}

/// Element-wise subtraction: C = A - B
kernel void sub(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] - B[gid];
}

/// Element-wise multiplication: C = A * B
kernel void mul(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] * B[gid];
}

/// Element-wise division: C = A / B
kernel void div_elem(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] / B[gid];
}

/// Scalar addition: C = A + scalar
kernel void add_scalar(
    device const float* A [[buffer(0)]],
    device float* C [[buffer(1)]],
    constant float& scalar [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] + scalar;
}

/// Scalar multiplication: C = A * scalar
kernel void mul_scalar(
    device const float* A [[buffer(0)]],
    device float* C [[buffer(1)]],
    constant float& scalar [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = A[gid] * scalar;
}

// ============================================================================
// Activation Functions
// ============================================================================

/// ReLU activation: C = max(0, A)
kernel void relu(
    device const float* A [[buffer(0)]],
    device float* C [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = max(0.0f, A[gid]);
}

/// Sigmoid activation: C = 1 / (1 + exp(-A))
kernel void sigmoid(
    device const float* A [[buffer(0)]],
    device float* C [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = 1.0f / (1.0f + exp(-A[gid]));
}

/// Tanh activation
kernel void tanh_act(
    device const float* A [[buffer(0)]],
    device float* C [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    C[gid] = tanh(A[gid]);
}

// ============================================================================
// Reduction Operations
// ============================================================================

/// Sum reduction (partial - needs multiple passes for large arrays)
kernel void reduce_sum(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& size [[buffer(2)]],
    uint gid [[thread_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint tgid [[threadgroup_position_in_grid]]
) {
    threadgroup float shared[256];

    // Load and sum multiple elements per thread
    float sum = 0.0f;
    uint idx = gid;
    while (idx < size) {
        sum += input[idx];
        idx += 256 * 256; // Total threads
    }
    shared[lid] = sum;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Parallel reduction in shared memory
    for (uint s = 128; s > 0; s >>= 1) {
        if (lid < s) {
            shared[lid] += shared[lid + s];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // Write result
    if (lid == 0) {
        output[tgid] = shared[0];
    }
}

/// Max reduction (partial)
kernel void reduce_max(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& size [[buffer(2)]],
    uint gid [[thread_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint tgid [[threadgroup_position_in_grid]]
) {
    threadgroup float shared[256];

    float maxVal = -INFINITY;
    uint idx = gid;
    while (idx < size) {
        maxVal = max(maxVal, input[idx]);
        idx += 256 * 256;
    }
    shared[lid] = maxVal;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint s = 128; s > 0; s >>= 1) {
        if (lid < s) {
            shared[lid] = max(shared[lid], shared[lid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (lid == 0) {
        output[tgid] = shared[0];
    }
}
