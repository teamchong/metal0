//! Vector Operations Benchmark - End-to-End Comparison
//!
//! HONEST benchmark testing vector operations from files:
//!   1. LanceQL native  - Read Lance file → vector ops
//!   2. DuckDB SQL           - Read Parquet → SQL computation
//!   3. Polars DataFrame     - Read Parquet → vectorized ops
//!
//! FAIR COMPARISON:
//!   - All methods read from disk (Lance or Parquet files)
//!   - All methods run for exactly 15 seconds
//!   - Throughput measured as rows processed per second
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py  # Creates test data
//!   zig build bench-vector

const std = @import("std");
const Table = @import("lanceql.table").Table;

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";

// SIMD configuration
const VECTOR_SIZE = 1024; // Process 1024 rows at a time (cache-friendly)
const SIMD_WIDTH = 4; // 4 x f64 = 256 bits (AVX)
const Vec4 = @Vector(SIMD_WIDTH, f64);

// Parallel execution threshold
const MIN_ROWS_PER_THREAD = 10000; // Only parallelize if enough work per thread

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

fn readLanceFile(allocator: std.mem.Allocator) ![]const u8 {
    var data_dir = std.fs.cwd().openDir(LANCE_PATH ++ "/data", .{ .iterate = true }) catch return error.FileNotFound;
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

// =============================================================================
// SIMD + Parallel L2 Norm Implementation
// =============================================================================

/// SIMD L2 norm: SQRT(SUM(x^2)) using 4-wide SIMD vectors
fn simdL2NormSquared(data: []const f64) f64 {
    const len = data.len;
    var sum_vec: Vec4 = @splat(0.0);

    // Process in VECTOR_SIZE batches for cache locality
    var batch_start: usize = 0;
    while (batch_start < len) : (batch_start += VECTOR_SIZE) {
        const batch_end = @min(batch_start + VECTOR_SIZE, len);
        const batch = data[batch_start..batch_end];

        // SIMD loop - process 4 elements at a time
        var i: usize = 0;
        while (i + SIMD_WIDTH <= batch.len) : (i += SIMD_WIDTH) {
            const vec: Vec4 = batch[i..][0..SIMD_WIDTH].*;
            sum_vec += vec * vec;
        }

        // Handle remaining elements
        while (i < batch.len) : (i += 1) {
            sum_vec[0] += batch[i] * batch[i];
        }
    }

    // Horizontal sum of SIMD vector
    return @reduce(.Add, sum_vec);
}

/// Thread context for parallel L2 norm
const L2ThreadContext = struct {
    data: []const f64,
    result: f64 = 0,
};

/// Thread worker for parallel L2 norm
fn parallelL2Worker(ctx: *L2ThreadContext) void {
    ctx.result = simdL2NormSquared(ctx.data);
}

/// Parallel SIMD L2 norm with threshold-based dispatch
fn parallelL2Norm(data: []const f64, num_threads: usize) f64 {
    // Only parallelize if each thread gets enough work
    if (data.len < MIN_ROWS_PER_THREAD * 2 or num_threads <= 1) {
        return @sqrt(simdL2NormSquared(data));
    }

    // Calculate actual threads to use (don't over-parallelize)
    const actual_threads = @min(num_threads, data.len / MIN_ROWS_PER_THREAD);
    if (actual_threads <= 1) {
        return @sqrt(simdL2NormSquared(data));
    }

    const chunk_size = data.len / actual_threads;

    var contexts: [16]L2ThreadContext = undefined;
    var threads: [16]std.Thread = undefined;

    // Spawn worker threads
    for (0..actual_threads - 1) |t| {
        const start = t * chunk_size;
        const end = start + chunk_size;
        contexts[t] = .{ .data = data[start..end] };
        threads[t] = std.Thread.spawn(.{}, parallelL2Worker, .{&contexts[t]}) catch {
            // Fallback to serial if thread spawn fails
            contexts[t].result = simdL2NormSquared(contexts[t].data);
            continue;
        };
    }

    // Process last chunk in main thread (includes remainder)
    const last_start = (actual_threads - 1) * chunk_size;
    contexts[actual_threads - 1] = .{ .data = data[last_start..] };
    contexts[actual_threads - 1].result = simdL2NormSquared(contexts[actual_threads - 1].data);

    // Wait for all threads and sum results
    var total_sum: f64 = contexts[actual_threads - 1].result;
    for (0..actual_threads - 1) |t| {
        threads[t].join();
        total_sum += contexts[t].result;
    }

    return @sqrt(total_sum);
}

/// Simple scalar L2 norm (for comparison)
fn scalarL2Norm(data: []const f64) f64 {
    var sum: f64 = 0;
    for (data) |x| {
        sum += x * x;
    }
    return @sqrt(sum);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("Vector Operations Benchmark: End-to-End (Read + L2 Norm)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\nPipeline: Read file → compute L2 norm of column\n", .{});
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

    // Detect number of CPU threads
    const num_threads = std.Thread.getCpuCount() catch 4;

    std.debug.print("\nEngines:\n", .{});
    std.debug.print("  LanceQL native: yes ({d} threads)\n", .{num_threads});
    std.debug.print("  DuckDB:               {s}\n", .{if (has_duckdb) "yes" else "no"});
    std.debug.print("  Polars:               {s}\n", .{if (has_polars) "yes" else "no"});
    std.debug.print("\n", .{});

    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<44} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("================================================================================\n", .{});

    var lanceql_rows_per_sec: f64 = 0;

    // =========================================================================
    // LanceQL parallel+SIMD - Read Lance file, compute L2 norm with SIMD
    // Uses threshold: parallel only if rows >= MIN_ROWS_PER_THREAD * 2
    // =========================================================================
    {
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Warmup
        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);

            // Use parallel SIMD with threshold-based dispatch
            const norm = parallelL2Norm(amounts, num_threads);
            std.mem.doNotOptimizeAway(&norm);
        }

        // Benchmark
        const benchmark_end_time = std.time.nanoTimestamp() + BENCHMARK_SECONDS * 1_000_000_000;
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);

            // Use parallel SIMD with threshold-based dispatch
            const norm = parallelL2Norm(amounts, num_threads);
            std.mem.doNotOptimizeAway(&norm);

            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_rows_per_sec = @as(f64, @floatFromInt(total_rows)) / elapsed_s;

        std.debug.print("{s:<44} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL parallel+SIMD (L2 norm)",
            lanceql_rows_per_sec / 1000.0,
            iterations,
            "1.0x",
        });
    }

    // =========================================================================
    // DuckDB - Read Parquet file, compute L2 norm via SQL
    // =========================================================================
    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("SELECT SQRT(SUM(amount * amount)) FROM read_parquet('{s}')").fetchdf()
            \\    con.close()
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    result = con.execute("SELECT COUNT(*), SQRT(SUM(amount * amount)) FROM read_parquet('{s}')").fetchone()
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
            std.debug.print("{s:<44} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        // Parse output
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
            const speedup = lanceql_rows_per_sec / rows_per_sec;
            std.debug.print("{s:<44} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (L2 norm)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        } else {
            std.debug.print("{s:<44} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
        }
    }

    // =========================================================================
    // Polars - Read Parquet file, compute L2 norm via DataFrame
    // =========================================================================
    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}")
            \\    norm = (df["amount"] ** 2).sum() ** 0.5
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}")
            \\    norm = (df["amount"] ** 2).sum() ** 0.5
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
            std.debug.print("{s:<44} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
            return;
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        // Parse output
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
            const speedup = lanceql_rows_per_sec / rows_per_sec;
            std.debug.print("{s:<44} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (L2 norm)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        } else {
            std.debug.print("{s:<44} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
        }
    }

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("Summary\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("All methods: Read file → compute L2 norm → return result\n", .{});
    std.debug.print("L2 norm: SQRT(SUM(x^2)) - Euclidean length of vector\n", .{});
    std.debug.print("\n", .{});
}
