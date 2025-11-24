#include <metal_stdlib>
using namespace metal;

/// Matrix multiplication kernel: C = A * B
/// A: [M x K]
/// B: [K x N]
/// C: [M x N]
kernel void matrix_multiply(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    constant uint& M [[buffer(3)]],
    constant uint& N [[buffer(4)]],
    constant uint& K [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint row = gid.y;
    uint col = gid.x;

    if (row >= M || col >= N) return;

    float sum = 0.0;
    for (uint k = 0; k < K; k++) {
        sum += A[row * K + k] * B[k * N + col];
    }

    C[row * N + col] = sum;
}

/// Optimized tiled matrix multiply for larger matrices
/// Uses threadgroup memory (shared memory) for better cache locality
kernel void matrix_multiply_tiled(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    constant uint& M [[buffer(3)]],
    constant uint& N [[buffer(4)]],
    constant uint& K [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 tid [[thread_position_in_threadgroup]],
    uint2 tpg [[threads_per_threadgroup]]
) {
    constexpr uint TILE_SIZE = 16;

    threadgroup float A_tile[TILE_SIZE][TILE_SIZE];
    threadgroup float B_tile[TILE_SIZE][TILE_SIZE];

    uint row = gid.y;
    uint col = gid.x;

    float sum = 0.0;

    // Loop over tiles
    for (uint t = 0; t < (K + TILE_SIZE - 1) / TILE_SIZE; t++) {
        // Load tile of A into threadgroup memory
        uint a_col = t * TILE_SIZE + tid.x;
        if (row < M && a_col < K) {
            A_tile[tid.y][tid.x] = A[row * K + a_col];
        } else {
            A_tile[tid.y][tid.x] = 0.0;
        }

        // Load tile of B into threadgroup memory
        uint b_row = t * TILE_SIZE + tid.y;
        if (b_row < K && col < N) {
            B_tile[tid.y][tid.x] = B[b_row * N + col];
        } else {
            B_tile[tid.y][tid.x] = 0.0;
        }

        // Synchronize threads
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Compute partial sum for this tile
        for (uint k = 0; k < TILE_SIZE; k++) {
            sum += A_tile[tid.y][k] * B_tile[k][tid.x];
        }

        // Synchronize before loading next tile
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // Write result
    if (row < M && col < N) {
        C[row * N + col] = sum;
    }
}
