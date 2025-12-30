//
// Metal GPU Shaders for LanceQL Vector Search
//
// Compile: xcrun -sdk macosx metal -O3 -c vector_search.metal -o vector_search.air
// Link:    xcrun -sdk macosx metallib vector_search.air -o vector_search.metallib
//

#include <metal_stdlib>
using namespace metal;

/// Batch cosine similarity: compute similarity of query against all vectors
/// Each thread processes one vector
kernel void cosine_similarity_batch(
    device const float* query [[buffer(0)]],      // Query vector [dim]
    device const float* vectors [[buffer(1)]],    // All vectors [num_vectors * dim]
    device float* scores [[buffer(2)]],           // Output scores [num_vectors]
    constant uint& dim [[buffer(3)]],             // Vector dimension
    uint gid [[thread_position_in_grid]]          // Vector index
) {
    // Compute dot product and norms
    float dot_product = 0.0f;
    float query_norm = 0.0f;
    float vec_norm = 0.0f;

    const device float* vec = vectors + gid * dim;

    // Vectorized accumulation (4 floats at a time)
    uint i = 0;
    for (; i + 4 <= dim; i += 4) {
        float4 q = float4(query[i], query[i+1], query[i+2], query[i+3]);
        float4 v = float4(vec[i], vec[i+1], vec[i+2], vec[i+3]);

        dot_product += dot(q, v);
        query_norm += dot(q, q);
        vec_norm += dot(v, v);
    }

    // Scalar remainder
    for (; i < dim; i++) {
        float q = query[i];
        float v = vec[i];
        dot_product += q * v;
        query_norm += q * q;
        vec_norm += v * v;
    }

    // Cosine similarity
    float denom = sqrt(query_norm) * sqrt(vec_norm);
    scores[gid] = (denom > 0.0f) ? (dot_product / denom) : 0.0f;
}

/// Batch dot product
kernel void dot_product_batch(
    device const float* query [[buffer(0)]],
    device const float* vectors [[buffer(1)]],
    device float* scores [[buffer(2)]],
    constant uint& dim [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    float dot = 0.0f;
    const device float* vec = vectors + gid * dim;

    for (uint i = 0; i < dim; i++) {
        dot += query[i] * vec[i];
    }

    scores[gid] = dot;
}

/// Batch L2 distance squared
kernel void l2_distance_batch(
    device const float* query [[buffer(0)]],
    device const float* vectors [[buffer(1)]],
    device float* scores [[buffer(2)]],
    constant uint& dim [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    float dist = 0.0f;
    const device float* vec = vectors + gid * dim;

    for (uint i = 0; i < dim; i++) {
        float diff = query[i] - vec[i];
        dist += diff * diff;
    }

    scores[gid] = dist;
}

/// Top-K selection using parallel reduction
/// Each threadgroup finds local top-K, then merged on CPU
kernel void top_k_partial(
    device const float* scores [[buffer(0)]],     // Input scores [num_vectors]
    device float* top_scores [[buffer(1)]],       // Output top scores [num_groups * k]
    device uint* top_indices [[buffer(2)]],       // Output top indices [num_groups * k]
    constant uint& k [[buffer(3)]],               // K value
    constant uint& num_vectors [[buffer(4)]],     // Total vectors
    uint gid [[thread_position_in_grid]],
    uint tid [[thread_position_in_threadgroup]],
    uint tgid [[threadgroup_position_in_grid]],
    uint tg_size [[threads_per_threadgroup]]
) {
    // Each thread maintains its own top-K candidates
    // Simplified: just find max in this thread's chunk
    uint chunk_start = gid;
    uint chunk_stride = tg_size * 256; // Total threads

    float best_score = -INFINITY;
    uint best_idx = 0;

    for (uint i = chunk_start; i < num_vectors; i += chunk_stride) {
        float s = scores[i];
        if (s > best_score) {
            best_score = s;
            best_idx = i;
        }
    }

    // Store this thread's best (full top-K merge done on CPU)
    top_scores[gid] = best_score;
    top_indices[gid] = best_idx;
}

// =============================================================================
// Batch Arithmetic Operations for @logic_table compiled methods
// =============================================================================

/// Batch multiply array by scalar: out[i] = a[i] * scalar
kernel void batch_mul_scalar(
    device const float* a [[buffer(0)]],
    device float* out [[buffer(1)]],
    constant float& scalar [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] * scalar;
}

/// Batch multiply two arrays: out[i] = a[i] * b[i]
kernel void batch_mul_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] * b[gid];
}

/// Batch multiply two arrays with scalar: out[i] = a[i] * b[i] * scalar
kernel void batch_mul_arrays_scalar(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    constant float& scalar [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] * b[gid] * scalar;
}

/// Batch add two arrays: out[i] = a[i] + b[i]
kernel void batch_add_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] + b[gid];
}

/// Batch subtract: out[i] = a[i] - b[i]
kernel void batch_sub_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] - b[gid];
}

/// Batch divide: out[i] = a[i] / b[i]
kernel void batch_div_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = a[gid] / b[gid];
}

/// Batch fused multiply-add: out[i] = a[i] * b[i] + c[i]
kernel void batch_fma(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device const float* c [[buffer(2)]],
    device float* out [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = fma(a[gid], b[gid], c[gid]);
}

/// Batch abs: out[i] = abs(a[i])
kernel void batch_abs(
    device const float* a [[buffer(0)]],
    device float* out [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = abs(a[gid]);
}

/// Batch min of two arrays: out[i] = min(a[i], b[i])
kernel void batch_min_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = min(a[gid], b[gid]);
}

/// Batch max of two arrays: out[i] = max(a[i], b[i])
kernel void batch_max_arrays(
    device const float* a [[buffer(0)]],
    device const float* b [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    out[gid] = max(a[gid], b[gid]);
}

// =============================================================================
// GPU Hash Table Operations (for GROUP BY and Hash JOIN)
// =============================================================================

/// Hash function: FNV-1a variant for 64-bit keys
inline uint64_t hash_key(uint64_t key) {
    // FNV-1a parameters
    const uint64_t FNV_PRIME = 0x100000001b3ULL;
    const uint64_t FNV_OFFSET = 0xcbf29ce484222325ULL;

    uint64_t hash = FNV_OFFSET;
    hash ^= key;
    hash *= FNV_PRIME;
    hash ^= (key >> 32);
    hash *= FNV_PRIME;
    return hash;
}

/// GPU Hash Table: Open addressing with linear probing
/// Each slot is: [key: u64, value: u64, occupied: u32, padding: u32]
/// Slot layout:  0-7: key, 8-15: value, 16-19: occupied flag
constant uint SLOT_SIZE = 24;  // bytes per slot
constant uint KEY_OFFSET = 0;
constant uint VALUE_OFFSET = 8;
constant uint OCCUPIED_OFFSET = 16;

/// Build phase: Insert keys into hash table
/// Each thread inserts one key-value pair
kernel void hash_table_build(
    device const uint64_t* keys [[buffer(0)]],      // Input keys [num_keys]
    device const uint64_t* values [[buffer(1)]],    // Input values [num_keys]
    device atomic_uint* table [[buffer(2)]],        // Hash table [capacity * SLOT_SIZE / 4]
    constant uint& capacity [[buffer(3)]],          // Table capacity (power of 2)
    constant uint& num_keys [[buffer(4)]],          // Number of keys to insert
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= num_keys) return;

    uint64_t key = keys[gid];
    uint64_t value = values[gid];
    uint64_t hash = hash_key(key);

    // Linear probing
    uint mask = capacity - 1;  // capacity must be power of 2
    uint slot = uint(hash) & mask;
    uint max_probes = min(capacity, 1024u);  // Limit probes to avoid infinite loop

    for (uint probe = 0; probe < max_probes; probe++) {
        uint slot_base = slot * (SLOT_SIZE / 4);  // Convert to uint offset

        // Try to claim this slot (atomic compare-exchange on occupied flag)
        uint occupied_idx = slot_base + (OCCUPIED_OFFSET / 4);
        uint expected = 0;

        // Atomic compare-exchange: if slot is empty (0), set to 1
        if (atomic_compare_exchange_weak_explicit(
                &table[occupied_idx],
                &expected,
                1u,
                memory_order_relaxed,
                memory_order_relaxed)) {
            // Successfully claimed slot - write key and value
            // Note: These are non-atomic since we own the slot now
            device uint64_t* slot_key = (device uint64_t*)&table[slot_base];
            device uint64_t* slot_val = (device uint64_t*)&table[slot_base + 2];
            *slot_key = key;
            *slot_val = value;
            return;
        }

        // Slot occupied - check if same key (for aggregation)
        device uint64_t* existing_key = (device uint64_t*)&table[slot_base];
        if (*existing_key == key) {
            // Same key - atomically add value (for SUM aggregation)
            device atomic_uint* val_lo = &table[slot_base + 2];
            device atomic_uint* val_hi = &table[slot_base + 3];
            // Simple atomic add for lower 32 bits (good enough for counts)
            atomic_fetch_add_explicit(val_lo, uint(value), memory_order_relaxed);
            return;
        }

        // Different key - continue probing
        slot = (slot + 1) & mask;
    }
    // Table full - key not inserted (should increase capacity)
}

/// Probe phase: Look up keys in hash table
/// Each thread probes one key and writes result
kernel void hash_table_probe(
    device const uint64_t* probe_keys [[buffer(0)]],    // Keys to look up [num_probes]
    device const uint* table [[buffer(1)]],             // Hash table (read-only)
    device uint64_t* results [[buffer(2)]],             // Output values [num_probes]
    device int* found [[buffer(3)]],                    // 1 if found, 0 if not [num_probes]
    constant uint& capacity [[buffer(4)]],              // Table capacity
    constant uint& num_probes [[buffer(5)]],            // Number of probes
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= num_probes) return;

    uint64_t key = probe_keys[gid];
    uint64_t hash = hash_key(key);

    uint mask = capacity - 1;
    uint slot = uint(hash) & mask;
    uint max_probes = min(capacity, 1024u);

    for (uint probe = 0; probe < max_probes; probe++) {
        uint slot_base = slot * (SLOT_SIZE / 4);

        // Check if slot is occupied
        uint occupied = table[slot_base + (OCCUPIED_OFFSET / 4)];
        if (occupied == 0) {
            // Empty slot - key not found
            results[gid] = 0;
            found[gid] = 0;
            return;
        }

        // Check key match
        device const uint64_t* slot_key = (device const uint64_t*)&table[slot_base];
        if (*slot_key == key) {
            // Found!
            device const uint64_t* slot_val = (device const uint64_t*)&table[slot_base + 2];
            results[gid] = *slot_val;
            found[gid] = 1;
            return;
        }

        // Different key - continue probing
        slot = (slot + 1) & mask;
    }

    // Not found after max probes
    results[gid] = 0;
    found[gid] = 0;
}

/// Extract all key-value pairs from hash table
/// Used after GROUP BY to collect results
kernel void hash_table_extract(
    device const uint* table [[buffer(0)]],         // Hash table
    device uint64_t* out_keys [[buffer(1)]],        // Output keys
    device uint64_t* out_values [[buffer(2)]],      // Output values
    device atomic_uint* out_count [[buffer(3)]],    // Atomic counter for output index
    constant uint& capacity [[buffer(4)]],          // Table capacity
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= capacity) return;

    uint slot_base = gid * (SLOT_SIZE / 4);
    uint occupied = table[slot_base + (OCCUPIED_OFFSET / 4)];

    if (occupied != 0) {
        // Slot has data - extract it
        device const uint64_t* slot_key = (device const uint64_t*)&table[slot_base];
        device const uint64_t* slot_val = (device const uint64_t*)&table[slot_base + 2];

        // Atomically get output index
        uint out_idx = atomic_fetch_add_explicit(out_count, 1u, memory_order_relaxed);

        out_keys[out_idx] = *slot_key;
        out_values[out_idx] = *slot_val;
    }
}

// =============================================================================
// Radix Partition (for radix hash join and radix sort)
// =============================================================================

/// Compute histogram of radix values in each partition
/// Phase 1 of radix partitioning
kernel void radix_histogram(
    device const uint64_t* keys [[buffer(0)]],      // Input keys
    device atomic_uint* histograms [[buffer(1)]],   // Output: [num_partitions * num_threadgroups]
    constant uint& radix_bits [[buffer(2)]],        // Number of radix bits (e.g., 8)
    constant uint& radix_shift [[buffer(3)]],       // Bit position to extract from
    constant uint& num_keys [[buffer(4)]],          // Total keys
    uint gid [[thread_position_in_grid]],
    uint tgid [[threadgroup_position_in_grid]],
    uint threads_per_group [[threads_per_threadgroup]]
) {
    if (gid >= num_keys) return;

    uint64_t key = keys[gid];
    uint num_partitions = 1u << radix_bits;
    uint partition = uint((key >> radix_shift) & (num_partitions - 1));

    // Increment histogram for this threadgroup
    uint hist_idx = tgid * num_partitions + partition;
    atomic_fetch_add_explicit(&histograms[hist_idx], 1u, memory_order_relaxed);
}

/// Scatter keys to partitioned output based on computed offsets
/// Phase 2 of radix partitioning (after prefix sum on histograms)
kernel void radix_scatter(
    device const uint64_t* input_keys [[buffer(0)]],
    device const uint64_t* input_values [[buffer(1)]],
    device uint64_t* output_keys [[buffer(2)]],
    device uint64_t* output_values [[buffer(3)]],
    device atomic_uint* offsets [[buffer(4)]],      // Write offsets per partition
    constant uint& radix_bits [[buffer(5)]],
    constant uint& radix_shift [[buffer(6)]],
    constant uint& num_keys [[buffer(7)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= num_keys) return;

    uint64_t key = input_keys[gid];
    uint64_t value = input_values[gid];
    uint num_partitions = 1u << radix_bits;
    uint partition = uint((key >> radix_shift) & (num_partitions - 1));

    // Atomically get write position
    uint pos = atomic_fetch_add_explicit(&offsets[partition], 1u, memory_order_relaxed);

    output_keys[pos] = key;
    output_values[pos] = value;
}
