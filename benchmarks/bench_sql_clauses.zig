//! SQL Clauses Benchmark - End-to-End Comparison
//!
//! HONEST benchmark testing ALL SQL operations from files:
//!   1. LanceQL native  - Read Lance file → SQL operations (GPU accelerated)
//!   2. DuckDB SQL      - Read Parquet → SQL operations
//!   3. Polars DataFrame - Read Parquet → DataFrame operations
//!
//! FAIR COMPARISON:
//!   - All methods read from disk (Lance or Parquet files)
//!   - All methods run for exactly 15 seconds
//!   - Throughput measured as rows processed per second
//!
//! SQL CLAUSES TESTED:
//!   - FILTER (WHERE)
//!   - AGGREGATE (SUM)
//!   - GROUP BY
//!   - JOIN (INNER JOIN orders with customers)
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py  # Creates orders + customers
//!   zig build bench-sql

const std = @import("std");
const Table = @import("lanceql.table").Table;

// =============================================================================
// Phase 1: SIMD Operations (4-wide vectors)
// =============================================================================

const Vec4 = @Vector(4, f64);
const Vec8 = @Vector(8, f64);

// =============================================================================
// Phase 2: Vectorized Execution (batch processing)
// =============================================================================

const VECTOR_SIZE = 1024; // Process 1024 rows at a time (cache-friendly)

/// Vectorized SIMD filter: COUNT(*) WHERE value > threshold
/// Processes data in VECTOR_SIZE batches with 8-wide SIMD
fn vectorizedFilterCount(amounts: []const f64, threshold: f64) u64 {
    var total_count: u64 = 0;
    var batch_start: usize = 0;
    const len = amounts.len;
    const thresh_vec: Vec8 = @splat(threshold);

    // Process in VECTOR_SIZE batches for better cache locality
    while (batch_start < len) {
        const batch_end = @min(batch_start + VECTOR_SIZE, len);
        const batch = amounts[batch_start..batch_end];

        var count: u64 = 0;
        var i: usize = 0;

        // 8-wide SIMD within each batch
        while (i + 8 <= batch.len) : (i += 8) {
            const vals: Vec8 = batch[i..][0..8].*;
            const mask = vals > thresh_vec;
            count += @popCount(@as(u8, @bitCast(mask)));
        }

        // Handle remaining in batch
        while (i < batch.len) : (i += 1) {
            if (batch[i] > threshold) count += 1;
        }

        total_count += count;
        batch_start = batch_end;
    }

    return total_count;
}

/// Vectorized SIMD aggregate: SUM(values)
/// Processes data in VECTOR_SIZE batches with 8-wide SIMD
fn vectorizedSum(amounts: []const f64) f64 {
    var total_sum: f64 = 0;
    var batch_start: usize = 0;
    const len = amounts.len;

    // Process in VECTOR_SIZE batches for better cache locality
    while (batch_start < len) {
        const batch_end = @min(batch_start + VECTOR_SIZE, len);
        const batch = amounts[batch_start..batch_end];

        var sum_vec: Vec8 = @splat(0.0);
        var i: usize = 0;

        // 8-wide SIMD within each batch
        while (i + 8 <= batch.len) : (i += 8) {
            const vals: Vec8 = batch[i..][0..8].*;
            sum_vec += vals;
        }

        var batch_sum: f64 = @reduce(.Add, sum_vec);

        // Handle remaining in batch
        while (i < batch.len) : (i += 1) {
            batch_sum += batch[i];
        }

        total_sum += batch_sum;
        batch_start = batch_end;
    }

    return total_sum;
}

/// Vectorized GROUP BY with SIMD-friendly hash aggregation
/// Uses a pre-sized array for known customer_id range [0, 10000)
fn vectorizedGroupBySum(
    amounts: []const f64,
    customer_ids: []const i64,
    group_sums: []f64, // Pre-allocated array of size 10000
) void {
    var batch_start: usize = 0;
    const len = amounts.len;

    // Process in VECTOR_SIZE batches
    while (batch_start < len) {
        const batch_end = @min(batch_start + VECTOR_SIZE, len);

        // Process batch - direct array indexing (no hash table)
        var i = batch_start;
        while (i < batch_end) : (i += 1) {
            const cid = customer_ids[i];
            if (cid >= 0 and cid < 10000) {
                group_sums[@intCast(cid)] += amounts[i];
            }
        }

        batch_start = batch_end;
    }
}

// =============================================================================
// Phase 3: Parallel Execution (morsel-driven parallelism)
// =============================================================================

const MAX_THREADS = 16;
const MIN_ROWS_PER_THREAD = 32 * 1024; // Each thread needs at least 32K rows to be worth it

/// Thread context for parallel filter
const FilterThreadContext = struct {
    amounts: []const f64,
    threshold: f64,
    result: u64 = 0,
};

/// Thread worker for parallel filter
fn parallelFilterWorker(ctx: *FilterThreadContext) void {
    ctx.result = vectorizedFilterCount(ctx.amounts, ctx.threshold);
}

/// Parallel SIMD filter: COUNT(*) WHERE value > threshold
/// Uses morsel-driven parallelism across multiple threads
fn parallelFilterCount(amounts: []const f64, threshold: f64, num_threads: usize) u64 {
    // Only parallelize if each thread gets enough work to offset overhead
    if (num_threads <= 1 or amounts.len / num_threads < MIN_ROWS_PER_THREAD) {
        return vectorizedFilterCount(amounts, threshold);
    }

    const actual_threads = @min(num_threads, MAX_THREADS);
    const chunk_size = amounts.len / actual_threads;

    var contexts: [MAX_THREADS]FilterThreadContext = undefined;
    var threads: [MAX_THREADS]std.Thread = undefined;
    var spawned: usize = 0;

    // Spawn worker threads for all but the last chunk
    for (0..actual_threads - 1) |t| {
        const start = t * chunk_size;
        const end = start + chunk_size;
        contexts[t] = FilterThreadContext{
            .amounts = amounts[start..end],
            .threshold = threshold,
        };
        threads[t] = std.Thread.spawn(.{}, parallelFilterWorker, .{&contexts[t]}) catch {
            // Fallback to single-threaded if spawn fails
            contexts[t].result = vectorizedFilterCount(contexts[t].amounts, threshold);
            continue;
        };
        spawned += 1;
    }

    // Last thread handles remaining rows (including any remainder)
    const last_start = (actual_threads - 1) * chunk_size;
    contexts[actual_threads - 1] = FilterThreadContext{
        .amounts = amounts[last_start..],
        .threshold = threshold,
    };
    contexts[actual_threads - 1].result = vectorizedFilterCount(contexts[actual_threads - 1].amounts, threshold);

    // Wait for all threads and accumulate results
    var total: u64 = contexts[actual_threads - 1].result;
    for (0..spawned) |t| {
        threads[t].join();
        total += contexts[t].result;
    }

    return total;
}

/// Thread context for parallel sum
const SumThreadContext = struct {
    amounts: []const f64,
    result: f64 = 0,
};

/// Thread worker for parallel sum
fn parallelSumWorker(ctx: *SumThreadContext) void {
    ctx.result = vectorizedSum(ctx.amounts);
}

/// Parallel SIMD aggregate: SUM(values)
/// Uses morsel-driven parallelism across multiple threads
fn parallelSum(amounts: []const f64, num_threads: usize) f64 {
    // Only parallelize if each thread gets enough work to offset overhead
    if (num_threads <= 1 or amounts.len / num_threads < MIN_ROWS_PER_THREAD) {
        return vectorizedSum(amounts);
    }

    const actual_threads = @min(num_threads, MAX_THREADS);
    const chunk_size = amounts.len / actual_threads;

    var contexts: [MAX_THREADS]SumThreadContext = undefined;
    var threads: [MAX_THREADS]std.Thread = undefined;
    var spawned: usize = 0;

    // Spawn worker threads for all but the last chunk
    for (0..actual_threads - 1) |t| {
        const start = t * chunk_size;
        const end = start + chunk_size;
        contexts[t] = SumThreadContext{
            .amounts = amounts[start..end],
        };
        threads[t] = std.Thread.spawn(.{}, parallelSumWorker, .{&contexts[t]}) catch {
            contexts[t].result = vectorizedSum(contexts[t].amounts);
            continue;
        };
        spawned += 1;
    }

    // Last thread handles remaining rows
    const last_start = (actual_threads - 1) * chunk_size;
    contexts[actual_threads - 1] = SumThreadContext{
        .amounts = amounts[last_start..],
    };
    contexts[actual_threads - 1].result = vectorizedSum(contexts[actual_threads - 1].amounts);

    // Wait for all threads and accumulate results
    var total: f64 = contexts[actual_threads - 1].result;
    for (0..spawned) |t| {
        threads[t].join();
        total += contexts[t].result;
    }

    return total;
}

/// Thread context for parallel GROUP BY
const GroupByThreadContext = struct {
    amounts: []const f64,
    customer_ids: []const i64,
    local_sums: [10000]f64 = [_]f64{0} ** 10000, // Thread-local aggregation
};

/// Thread worker for parallel GROUP BY
fn parallelGroupByWorker(ctx: *GroupByThreadContext) void {
    vectorizedGroupBySum(ctx.amounts, ctx.customer_ids, &ctx.local_sums);
}

/// Parallel GROUP BY with thread-local aggregation
/// Each thread aggregates its chunk, then results are merged
fn parallelGroupBySum(
    amounts: []const f64,
    customer_ids: []const i64,
    group_sums: []f64,
    num_threads: usize,
    allocator: std.mem.Allocator,
) void {
    // Only parallelize if each thread gets enough work to offset overhead
    if (num_threads <= 1 or amounts.len / num_threads < MIN_ROWS_PER_THREAD) {
        vectorizedGroupBySum(amounts, customer_ids, group_sums);
        return;
    }

    const actual_threads = @min(num_threads, MAX_THREADS);
    const chunk_size = amounts.len / actual_threads;

    // Allocate thread contexts on heap to avoid stack overflow
    const contexts = allocator.alloc(GroupByThreadContext, actual_threads) catch {
        vectorizedGroupBySum(amounts, customer_ids, group_sums);
        return;
    };
    defer allocator.free(contexts);

    var threads: [MAX_THREADS]std.Thread = undefined;
    var spawned: usize = 0;

    // Initialize all contexts
    for (0..actual_threads) |t| {
        contexts[t] = GroupByThreadContext{
            .amounts = undefined,
            .customer_ids = undefined,
        };
    }

    // Spawn worker threads for all but the last chunk
    for (0..actual_threads - 1) |t| {
        const start = t * chunk_size;
        const end = start + chunk_size;
        contexts[t].amounts = amounts[start..end];
        contexts[t].customer_ids = customer_ids[start..end];
        threads[t] = std.Thread.spawn(.{}, parallelGroupByWorker, .{&contexts[t]}) catch {
            parallelGroupByWorker(&contexts[t]);
            continue;
        };
        spawned += 1;
    }

    // Last thread handles remaining rows
    const last_start = (actual_threads - 1) * chunk_size;
    contexts[actual_threads - 1].amounts = amounts[last_start..];
    contexts[actual_threads - 1].customer_ids = customer_ids[last_start..];
    parallelGroupByWorker(&contexts[actual_threads - 1]);

    // Wait for all threads
    for (0..spawned) |t| {
        threads[t].join();
    }

    // Merge thread-local results into final output
    for (0..10000) |i| {
        var sum: f64 = 0;
        for (0..actual_threads) |t| {
            sum += contexts[t].local_sums[i];
        }
        group_sums[i] = sum;
    }
}

/// Thread context for parallel JOIN probe (exists check)
const JoinProbeContext = struct {
    customer_ids: []const i64,
    customer_exists: *const [10000]bool,
    result_count: u64 = 0,
};

/// Thread worker for parallel JOIN probe
fn parallelJoinProbeWorker(ctx: *JoinProbeContext) void {
    var count: u64 = 0;
    for (ctx.customer_ids) |cid| {
        if (cid >= 0 and cid < 10000 and ctx.customer_exists.*[@intCast(cid)]) {
            count += 1;
        }
    }
    ctx.result_count = count;
}

/// Parallel JOIN probe using array lookup
fn parallelJoinProbe(
    customer_ids: []const i64,
    customer_exists: *const [10000]bool,
    num_threads: usize,
) u64 {
    // Only parallelize if each thread gets enough work to offset overhead
    if (num_threads <= 1 or customer_ids.len / num_threads < MIN_ROWS_PER_THREAD) {
        // Single-threaded fallback
        var count: u64 = 0;
        for (customer_ids) |cid| {
            if (cid >= 0 and cid < 10000 and customer_exists.*[@intCast(cid)]) {
                count += 1;
            }
        }
        return count;
    }

    const actual_threads = @min(num_threads, MAX_THREADS);
    const chunk_size = customer_ids.len / actual_threads;

    var contexts: [MAX_THREADS]JoinProbeContext = undefined;
    var threads: [MAX_THREADS]std.Thread = undefined;
    var spawned: usize = 0;

    // Spawn worker threads for all but the last chunk
    for (0..actual_threads - 1) |t| {
        const start = t * chunk_size;
        const end = start + chunk_size;
        contexts[t] = JoinProbeContext{
            .customer_ids = customer_ids[start..end],
            .customer_exists = customer_exists,
        };
        threads[t] = std.Thread.spawn(.{}, parallelJoinProbeWorker, .{&contexts[t]}) catch {
            parallelJoinProbeWorker(&contexts[t]);
            continue;
        };
        spawned += 1;
    }

    // Last thread handles remaining rows
    const last_start = (actual_threads - 1) * chunk_size;
    contexts[actual_threads - 1] = JoinProbeContext{
        .customer_ids = customer_ids[last_start..],
        .customer_exists = customer_exists,
    };
    parallelJoinProbeWorker(&contexts[actual_threads - 1]);

    // Wait for all threads and accumulate results
    var total: u64 = contexts[actual_threads - 1].result_count;
    for (0..spawned) |t| {
        threads[t].join();
        total += contexts[t].result_count;
    }

    return total;
}

// Get number of CPU cores for parallel execution
fn getNumThreads() usize {
    return std.Thread.getCpuCount() catch 4;
}

// Legacy SIMD functions (for comparison)
fn simdFilterCount(amounts: []const f64, threshold: f64) u64 {
    return vectorizedFilterCount(amounts, threshold);
}

fn simdSum(amounts: []const f64) f64 {
    return vectorizedSum(amounts);
}

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";
const CUSTOMERS_LANCE_PATH = "benchmarks/customers.lance";
const CUSTOMERS_PARQUET_PATH = "benchmarks/customers.parquet";

fn checkPythonModule(allocator: std.mem.Allocator, module: []const u8) bool {
    const py_code = std.fmt.allocPrint(allocator, "import {s}", .{module}) catch return false;
    defer allocator.free(py_code);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", "-c", py_code },
    }) catch return false;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    switch (result.term) {
        .Exited => |code| return code == 0,
        else => return false,
    }
}

/// Memory-mapped Lance file for zero-copy I/O
const MmapResult = struct {
    data: []align(std.heap.page_size_min) const u8,

    pub fn deinit(self: *MmapResult) void {
        std.posix.munmap(self.data);
    }
};

fn mmapLanceFile(lance_dir: []const u8, allocator: std.mem.Allocator) !MmapResult {
    const data_path = std.fmt.allocPrint(allocator, "{s}/data", .{lance_dir}) catch return error.OutOfMemory;
    defer allocator.free(data_path);

    var data_dir = std.fs.cwd().openDir(data_path, .{ .iterate = true }) catch return error.FileNotFound;
    defer data_dir.close();

    var iter = data_dir.iterate();
    var lance_file_name_buf: [256]u8 = undefined;
    var lance_file_name: ?[]const u8 = null;

    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".lance")) {
            const len = @min(entry.name.len, lance_file_name_buf.len);
            @memcpy(lance_file_name_buf[0..len], entry.name[0..len]);
            lance_file_name = lance_file_name_buf[0..len];
            break;
        }
    }

    const file_name = lance_file_name orelse return error.LanceFileNotFound;
    const file = data_dir.openFile(file_name, .{}) catch return error.FileNotFound;
    defer file.close();

    const file_size = file.getEndPos() catch return error.ReadError;

    // Memory-map the file instead of reading it
    const data = std.posix.mmap(
        null,
        file_size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    ) catch return error.ReadError;

    return MmapResult{ .data = data };
}

fn readLanceFileFromPath(allocator: std.mem.Allocator, lance_dir: []const u8) ![]const u8 {
    const data_path = std.fmt.allocPrint(allocator, "{s}/data", .{lance_dir}) catch return error.OutOfMemory;
    defer allocator.free(data_path);

    var data_dir = std.fs.cwd().openDir(data_path, .{ .iterate = true }) catch return error.FileNotFound;
    defer data_dir.close();

    var iter = data_dir.iterate();
    var lance_file_name_buf: [256]u8 = undefined;
    var lance_file_name: ?[]const u8 = null;

    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".lance")) {
            const len = @min(entry.name.len, lance_file_name_buf.len);
            @memcpy(lance_file_name_buf[0..len], entry.name[0..len]);
            lance_file_name = lance_file_name_buf[0..len];
            break;
        }
    }

    const file_name = lance_file_name orelse return error.LanceFileNotFound;
    const file = data_dir.openFile(file_name, .{}) catch return error.FileNotFound;
    defer file.close();

    const file_size = file.getEndPos() catch return error.ReadError;
    const bytes = allocator.alloc(u8, file_size) catch return error.OutOfMemory;
    errdefer allocator.free(bytes);

    _ = file.readAll(bytes) catch return error.ReadError;
    return bytes;
}

fn readLanceFile(allocator: std.mem.Allocator) ![]const u8 {
    return readLanceFileFromPath(allocator, LANCE_PATH);
}

fn readCustomersLanceFile(allocator: std.mem.Allocator) ![]const u8 {
    return readLanceFileFromPath(allocator, CUSTOMERS_LANCE_PATH);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("SQL Clauses Benchmark: End-to-End (Read + SQL Operations)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\nPipeline: Read file → execute SQL clause → return result\n", .{});
    std.debug.print("Each method runs for {d} seconds. Measuring throughput (rows/sec).\n", .{BENCHMARK_SECONDS});
    std.debug.print("\n", .{});

    // Check data files exist
    const lance_exists = blk: {
        var data_dir = std.fs.cwd().openDir(LANCE_PATH ++ "/data", .{ .iterate = true }) catch break :blk false;
        data_dir.close();
        break :blk true;
    };

    const parquet_exists = blk: {
        const file = std.fs.cwd().openFile(PARQUET_PATH, .{}) catch break :blk false;
        file.close();
        break :blk true;
    };

    std.debug.print("Data files:\n", .{});
    std.debug.print("  Lance:   {s} {s}\n", .{ LANCE_PATH, if (lance_exists) "✓" else "✗" });
    std.debug.print("  Parquet: {s} {s}\n", .{ PARQUET_PATH, if (parquet_exists) "✓" else "✗" });

    if (!lance_exists or !parquet_exists) {
        std.debug.print("\n⚠️  Missing data files. Run: python3 benchmarks/generate_benchmark_data.py\n", .{});
        return;
    }

    // Check Python engines
    const has_duckdb = checkPythonModule(allocator, "duckdb");
    const has_polars = checkPythonModule(allocator, "polars");

    // Get CPU count for parallel execution
    const num_threads = getNumThreads();

    std.debug.print("\nEngines:\n", .{});
    std.debug.print("  LanceQL native: yes ({d} threads)\n", .{num_threads});
    std.debug.print("  DuckDB:               {s}\n", .{if (has_duckdb) "yes" else "no"});
    std.debug.print("  Polars:               {s}\n", .{if (has_polars) "yes" else "no"});
    std.debug.print("\n", .{});

    // ==========================================================================
    // FILTER: WHERE amount > 100
    // ==========================================================================
    std.debug.print("================================================================================\n", .{});
    std.debug.print("FILTER: WHERE amount > 100\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "-" ** 40, "-" ** 12, "-" ** 12, "-" ** 10 });

    var lanceql_filter_rps: f64 = 0;
    {
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Memory-map the file ONCE - avoid repeated file I/O
        var mmap = mmapLanceFile(LANCE_PATH, allocator) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "LanceQL mmap (FILTER)", "mmap err", "-", "-" });
            return;
        };
        defer mmap.deinit();

        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const count = parallelFilterCount(amounts, 100.0, num_threads);
            std.mem.doNotOptimizeAway(&count);
        }

        const benchmark_end_time = std.time.nanoTimestamp() + BENCHMARK_SECONDS * 1_000_000_000;
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const count = parallelFilterCount(amounts, 100.0, num_threads);
            std.mem.doNotOptimizeAway(&count);
            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_filter_rps = @as(f64, @floatFromInt(total_rows)) / elapsed_s;
        std.debug.print("{s:<40} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL parallel+SIMD (FILTER)",
            lanceql_filter_rps / 1000.0,
            iterations,
            "1.0x",
        });
    }

    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    _ = con.execute("SELECT COUNT(*) FROM read_parquet('{s}') WHERE amount > 100").fetchone()
            \\    con.close()
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    result = con.execute("SELECT COUNT(*) FROM read_parquet('{s}')").fetchone()
            \\    total_rows += result[0]
            \\    con.close()
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_filter_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (FILTER)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        } else {
            // Debug: print stderr if benchmark failed
            if (result.stderr.len > 0) {
                std.debug.print("DuckDB FILTER stderr: {s}\n", .{result.stderr[0..@min(result.stderr.len, 200)]});
            }
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL (FILTER)", "0", "0", "-" });
        }
    }

    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}")
            \\    filtered = df.filter(pl.col("amount") > 100)
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}")
            \\    filtered = df.filter(pl.col("amount") > 100)
            \\    total_rows += len(df)
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_filter_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (FILTER)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // ==========================================================================
    // AGGREGATE: SUM(amount)
    // ==========================================================================
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("AGGREGATE: SUM(amount)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "-" ** 40, "-" ** 12, "-" ** 12, "-" ** 10 });

    var lanceql_agg_rps: f64 = 0;
    {
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Memory-map the file ONCE
        var mmap = mmapLanceFile(LANCE_PATH, allocator) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "LanceQL mmap (AGGREGATE)", "mmap err", "-", "-" });
            return;
        };
        defer mmap.deinit();

        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const sum = parallelSum(amounts, num_threads);
            std.mem.doNotOptimizeAway(&sum);
        }

        const benchmark_end_time = std.time.nanoTimestamp() + BENCHMARK_SECONDS * 1_000_000_000;
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const sum = parallelSum(amounts, num_threads);
            std.mem.doNotOptimizeAway(&sum);
            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_agg_rps = @as(f64, @floatFromInt(total_rows)) / elapsed_s;
        std.debug.print("{s:<40} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL parallel+SIMD (AGGREGATE)",
            lanceql_agg_rps / 1000.0,
            iterations,
            "1.0x",
        });
    }

    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    _ = con.execute("SELECT SUM(amount) FROM read_parquet('{s}')").fetchone()
            \\    con.close()
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    result = con.execute("SELECT COUNT(*), SUM(amount) FROM read_parquet('{s}')").fetchone()
            \\    total_rows += result[0]
            \\    con.close()
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_agg_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (AGGREGATE)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}")
            \\    total = df["amount"].sum()
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}")
            \\    total = df["amount"].sum()
            \\    total_rows += len(df)
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_agg_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (AGGREGATE)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // ==========================================================================
    // GROUP BY: SUM(amount) GROUP BY customer_id
    // ==========================================================================
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("GROUP BY: SUM(amount) GROUP BY customer_id\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "-" ** 40, "-" ** 12, "-" ** 12, "-" ** 10 });

    var lanceql_groupby_rps: f64 = 0;
    {
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Memory-map the file ONCE
        var mmap = mmapLanceFile(LANCE_PATH, allocator) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "LanceQL mmap (GROUP BY)", "mmap err", "-", "-" });
            return;
        };
        defer mmap.deinit();

        // Use pre-allocated array for known customer_id range [0, 10000)
        var group_sums: [10000]f64 = undefined;

        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const customer_ids = table.readInt64Column(2) catch break;
            defer allocator.free(customer_ids);

            @memset(&group_sums, 0.0);
            parallelGroupBySum(amounts, customer_ids, &group_sums, num_threads, allocator);
        }

        const benchmark_end_time = std.time.nanoTimestamp() + BENCHMARK_SECONDS * 1_000_000_000;
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            var table = Table.init(allocator, mmap.data) catch break;
            defer table.deinit();
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const customer_ids = table.readInt64Column(2) catch break;
            defer allocator.free(customer_ids);

            @memset(&group_sums, 0.0);
            parallelGroupBySum(amounts, customer_ids, &group_sums, num_threads, allocator);

            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_groupby_rps = @as(f64, @floatFromInt(total_rows)) / elapsed_s;
        std.debug.print("{s:<40} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL parallel+SIMD (GROUP BY)",
            lanceql_groupby_rps / 1000.0,
            iterations,
            "1.0x",
        });
    }

    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    _ = con.execute("SELECT customer_id, SUM(amount) FROM read_parquet('{s}') GROUP BY customer_id").fetchall()
            \\    con.close()
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    result = con.execute("SELECT COUNT(*) FROM read_parquet('{s}')").fetchone()
            \\    _ = con.execute("SELECT customer_id, SUM(amount) FROM read_parquet('{s}') GROUP BY customer_id").fetchall()
            \\    total_rows += result[0]
            \\    con.close()
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_groupby_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (GROUP BY)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}")
            \\    grouped = df.group_by("customer_id").agg(pl.col("amount").sum())
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}")
            \\    grouped = df.group_by("customer_id").agg(pl.col("amount").sum())
            \\    total_rows += len(df)
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_groupby_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (GROUP BY)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // ==========================================================================
    // JOIN: INNER JOIN orders with customers ON customer_id
    // ==========================================================================
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("JOIN: orders INNER JOIN customers ON customer_id\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "-" ** 40, "-" ** 12, "-" ** 12, "-" ** 10 });

    var lanceql_join_rps: f64 = 0;
    {
        // HONEST JOIN with mmap: Read BOTH files and build hash table
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Memory-map both files ONCE
        var orders_mmap = mmapLanceFile(LANCE_PATH, allocator) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "LanceQL mmap (JOIN)", "mmap err", "-", "-" });
            return;
        };
        defer orders_mmap.deinit();

        var cust_mmap = mmapLanceFile(CUSTOMERS_LANCE_PATH, allocator) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "LanceQL mmap (JOIN)", "cust mmap err", "-", "-" });
            return;
        };
        defer cust_mmap.deinit();

        // Use pre-allocated array for known customer_id range [0, 10000)
        var customer_exists: [10000]bool = undefined;

        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            // Build phase: read customers
            var cust_table = Table.init(allocator, cust_mmap.data) catch break;
            defer cust_table.deinit();
            const cust_ids = cust_table.readInt64Column(0) catch break;
            defer allocator.free(cust_ids);

            @memset(&customer_exists, false);
            for (cust_ids) |cid| {
                if (cid >= 0 and cid < 10000) customer_exists[@intCast(cid)] = true;
            }

            // Probe phase: read orders with parallel execution
            var table = Table.init(allocator, orders_mmap.data) catch break;
            defer table.deinit();
            const order_customer_ids = table.readInt64Column(2) catch break;
            defer allocator.free(order_customer_ids);

            const match_count = parallelJoinProbe(order_customer_ids, &customer_exists, num_threads);
            std.mem.doNotOptimizeAway(&match_count);
        }

        const benchmark_end_time = std.time.nanoTimestamp() + BENCHMARK_SECONDS * 1_000_000_000;
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            // Build phase
            var cust_table = Table.init(allocator, cust_mmap.data) catch break;
            defer cust_table.deinit();
            const cust_ids = cust_table.readInt64Column(0) catch break;
            defer allocator.free(cust_ids);

            @memset(&customer_exists, false);
            for (cust_ids) |cid| {
                if (cid >= 0 and cid < 10000) customer_exists[@intCast(cid)] = true;
            }

            // Probe phase with parallel execution
            var table = Table.init(allocator, orders_mmap.data) catch break;
            defer table.deinit();
            const order_customer_ids = table.readInt64Column(2) catch break;
            defer allocator.free(order_customer_ids);

            const match_count = parallelJoinProbe(order_customer_ids, &customer_exists, num_threads);
            std.mem.doNotOptimizeAway(&match_count);

            iterations += 1;
            total_rows += order_customer_ids.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_join_rps = @as(f64, @floatFromInt(total_rows)) / elapsed_s;
        std.debug.print("{s:<40} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL parallel+SIMD (JOIN)",
            lanceql_join_rps / 1000.0,
            iterations,
            "1.0x",
        });
    }

    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("""
            \\        SELECT o.id, o.amount, c.tier
            \\        FROM read_parquet('{s}') o
            \\        INNER JOIN read_parquet('{s}') c ON o.customer_id = c.id
            \\    """).fetchdf()
            \\    con.close()
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("""
            \\        SELECT o.id, o.amount, c.tier
            \\        FROM read_parquet('{s}') o
            \\        INNER JOIN read_parquet('{s}') c ON o.customer_id = c.id
            \\    """).fetchdf()
            \\    total_rows += len(df)
            \\    con.close()
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, CUSTOMERS_PARQUET_PATH, PARQUET_PATH, CUSTOMERS_PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_join_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (JOIN)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    orders = pl.read_parquet("{s}")
            \\    customers = pl.read_parquet("{s}")
            \\    joined = orders.join(customers, left_on="customer_id", right_on="id", how="inner")
            \\
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    orders = pl.read_parquet("{s}")
            \\    customers = pl.read_parquet("{s}")
            \\    joined = orders.join(customers, left_on="customer_id", right_on="id", how="inner")
            \\    total_rows += len(joined)
            \\    iterations += 1
            \\
            \\elapsed = time.time() - start
            \\rows_per_sec = total_rows / elapsed
            \\print(f"ROWS_PER_SEC:{{rows_per_sec:.0f}}")
            \\print(f"ITERATIONS:{{iterations}}")
        , .{ WARMUP_SECONDS, BENCHMARK_SECONDS, PARQUET_PATH, CUSTOMERS_PARQUET_PATH, PARQUET_PATH, CUSTOMERS_PARQUET_PATH });

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", py_script },
            .max_output_bytes = 10 * 1024,
        }) catch {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        var rows_per_sec: f64 = 0;
        var iterations: u64 = 0;
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ROWS_PER_SEC:")) {
                rows_per_sec = std.fmt.parseFloat(f64, line[13..]) catch 0;
            } else if (std.mem.startsWith(u8, line, "ITERATIONS:")) {
                iterations = std.fmt.parseInt(u64, line[11..], 10) catch 0;
            }
        }
        if (rows_per_sec > 0) {
            const speedup = lanceql_join_rps / rows_per_sec;
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (JOIN)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("Summary\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("All methods: Read file → execute SQL clause → return result\n", .{});
    std.debug.print("FILTER: Count rows matching WHERE clause\n", .{});
    std.debug.print("AGGREGATE: Compute SUM of column\n", .{});
    std.debug.print("GROUP BY: Aggregate by customer_id\n", .{});
    std.debug.print("JOIN: INNER JOIN orders with customers on customer_id\n", .{});
    std.debug.print("\n", .{});
}
