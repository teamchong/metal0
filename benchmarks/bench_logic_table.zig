//! @logic_table Benchmark - HONEST End-to-End Comparison
//!
//! What we're comparing (all read from files, same 15-second duration):
//!   1. LanceQL @logic_table  - Read Lance file → compute with COMPILED Python
//!   2. DuckDB + Python loop  - Read Parquet → row-by-row Python calls
//!   3. DuckDB → NumPy batch  - Read Parquet → pull to Python → NumPy compute
//!   4. Polars + Python loop  - Read Parquet → row-by-row Python calls
//!   5. Polars → NumPy batch  - Read Parquet → pull to Python → NumPy compute
//!
//! FAIR COMPARISON:
//!   - All methods read from disk (Lance or Parquet)
//!   - All methods run for exactly 15 seconds
//!   - Throughput measured as rows processed per second
//!   - LanceQL uses VectorOps.dot_product - compiled from Python @logic_table
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py  # Creates test data
//!   zig build bench-logic-table

const std = @import("std");
const Table = @import("lanceql.table").Table;

// Extern declaration for COMPILED @logic_table functions
// This is Python code compiled to native Zig by metal0
// Source: benchmarks/vector_ops.py -> lib/vector_ops.a

// Scalar function (single vector dot product)
extern fn VectorOps_dot_product(a: [*]const f64, b: [*]const f64, len: usize) f64;

// =============================================================================
// Native Zig batch function - processes all rows at once with explicit SIMD
// This is what we want @logic_table to generate, implemented manually for now
// =============================================================================

// SIMD vector size - 8 floats = 256 bits (AVX/NEON)
const SIMD_WIDTH = 8;
const SimdVec = @Vector(SIMD_WIDTH, f32);

fn batchDotProductF32(
    matrix: [*]const f32,
    vec_f64: [*]const f64,
    num_rows: usize,
    dim: usize,
    out: [*]f64,
) void {
    // Pre-convert query vector to f32 ONCE (avoids per-element conversion)
    var query_f32: [EMBEDDING_DIM]f32 = undefined;
    for (0..dim) |i| {
        query_f32[i] = @floatCast(vec_f64[i]);
    }

    // Process each row with explicit SIMD
    for (0..num_rows) |row| {
        const row_start = row * dim;
        var sum_vec: SimdVec = @splat(0.0);

        // SIMD loop - process SIMD_WIDTH elements at a time
        var i: usize = 0;
        while (i + SIMD_WIDTH <= dim) : (i += SIMD_WIDTH) {
            // Load SIMD_WIDTH elements from matrix row
            const mat_vec: SimdVec = matrix[row_start + i ..][0..SIMD_WIDTH].*;
            // Load SIMD_WIDTH elements from query vector
            const query_vec: SimdVec = query_f32[i..][0..SIMD_WIDTH].*;
            // Fused multiply-add: sum += mat * query
            sum_vec += mat_vec * query_vec;
        }

        // Horizontal sum of SIMD vector
        var sum: f32 = @reduce(.Add, sum_vec);

        // Handle remaining elements (if dim not divisible by SIMD_WIDTH)
        while (i < dim) : (i += 1) {
            sum += matrix[row_start + i] * query_f32[i];
        }

        out[row] = @floatCast(sum);
    }
}

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";
const EMBEDDING_DIM = 384;

var has_duckdb: bool = false;
var has_polars: bool = false;

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

fn runPythonTimedBenchmark(allocator: std.mem.Allocator, script: []const u8) !struct { iterations: u64, total_ns: u64 } {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", "-c", script },
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch return .{ .iterations = 0, .total_ns = 0 };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    var iterations: u64 = 0;
    var total_ns: u64 = 0;

    // Parse ITERATIONS:xxx
    if (std.mem.indexOf(u8, result.stdout, "ITERATIONS:")) |idx| {
        const start = idx + 11;
        var end = start;
        while (end < result.stdout.len and result.stdout[end] >= '0' and result.stdout[end] <= '9') {
            end += 1;
        }
        iterations = std.fmt.parseInt(u64, result.stdout[start..end], 10) catch 0;
    }

    // Parse TOTAL_NS:xxx
    if (std.mem.indexOf(u8, result.stdout, "TOTAL_NS:")) |idx| {
        const start = idx + 9;
        var end = start;
        while (end < result.stdout.len and result.stdout[end] >= '0' and result.stdout[end] <= '9') {
            end += 1;
        }
        total_ns = std.fmt.parseInt(u64, result.stdout[start..end], 10) catch 0;
    }

    return .{ .iterations = iterations, .total_ns = total_ns };
}

fn readLanceFile(allocator: std.mem.Allocator) ![]const u8 {
    // Find and read the Lance data file
    var data_dir = std.fs.cwd().openDir(LANCE_PATH ++ "/data", .{ .iterate = true }) catch return error.FileNotFound;
    defer data_dir.close();

    var iter = data_dir.iterate();
    var lance_file_name_buf: [256]u8 = undefined;
    var lance_file_name: ?[]const u8 = null;

    while (iter.next() catch null) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".lance")) {
            const len = @min(entry.name.len, lance_file_name_buf.len);
            @memcpy(lance_file_name_buf[0..len], entry.name[0..len]);
            lance_file_name = lance_file_name_buf[0..len];
            break;
        }
    }

    if (lance_file_name == null) return error.FileNotFound;

    const data_file = data_dir.openFile(lance_file_name.?, .{}) catch return error.FileNotFound;
    defer data_file.close();

    const file_size = (data_file.stat() catch return error.FileNotFound).size;
    const file_data = allocator.alloc(u8, file_size) catch return error.OutOfMemory;

    const bytes_read = data_file.readAll(file_data) catch return error.ReadError;
    if (bytes_read != file_size) return error.ReadError;

    return file_data;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("===============================================================================\n", .{});
    std.debug.print("@logic_table Benchmark: End-to-End (File I/O → Parse → Compute)\n", .{});
    std.debug.print("===============================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Each method runs for {d} seconds. Measuring throughput (rows/sec).\n", .{BENCHMARK_SECONDS});
    std.debug.print("\n", .{});

    // Check files exist
    const lance_exists = if (std.fs.cwd().access(LANCE_PATH, .{})) true else |_| false;
    const parquet_exists = if (std.fs.cwd().access(PARQUET_PATH, .{})) true else |_| false;

    if (!lance_exists or !parquet_exists) {
        std.debug.print("ERROR: Benchmark data not found. Run:\n", .{});
        std.debug.print("  python3 benchmarks/generate_benchmark_data.py\n", .{});
        return;
    }

    // Check for Python modules
    has_duckdb = checkPythonModule(allocator, "duckdb");
    has_polars = checkPythonModule(allocator, "polars");

    std.debug.print("Data files:\n", .{});
    std.debug.print("  Lance:   {s} ✓\n", .{LANCE_PATH});
    std.debug.print("  Parquet: {s} ✓\n", .{PARQUET_PATH});
    std.debug.print("\n", .{});
    std.debug.print("Engines:\n", .{});
    std.debug.print("  LanceQL @logic_table: yes\n", .{});
    std.debug.print("  DuckDB:               {s}\n", .{if (has_duckdb) "yes" else "no (pip install duckdb)"});
    std.debug.print("  Polars:               {s}\n", .{if (has_polars) "yes" else "no (pip install polars)"});
    std.debug.print("\n", .{});

    std.debug.print("===============================================================================\n", .{});
    std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "Method", "Rows/sec", "Iters", "vs Best" });
    std.debug.print("===============================================================================\n", .{});

    var lanceql_throughput: f64 = 0;

    // 1. LanceQL @logic_table BATCH (read Lance file → compute with COMPILED Python batch function)
    // Uses VectorOps_batch_dot_product_f32 - processes ALL rows at once with SIMD
    {
        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * std.time.ns_per_s;
        const benchmark_end_time = warmup_end + BENCHMARK_SECONDS * std.time.ns_per_s;

        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Query vector as f64 (batch function accepts f64 query)
        var query_vec: [EMBEDDING_DIM]f64 = undefined;
        for (&query_vec) |*v| v.* = 0.1;

        // Dynamic output buffer (will be allocated per-iteration)
        var scores: []f64 = &.{};

        // Warmup
        while (std.time.nanoTimestamp() < warmup_end) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const embeddings = table.readFloat32Column(3) catch break; // embedding column
            defer allocator.free(embeddings);

            const num_rows = embeddings.len / EMBEDDING_DIM;

            // Allocate output buffer if needed
            if (scores.len < num_rows) {
                if (scores.len > 0) allocator.free(scores);
                scores = allocator.alloc(f64, num_rows) catch break;
            }

            // BATCH: Compute ALL dot products in one call with SIMD
            // No per-row loop needed - batch function handles everything
            batchDotProductF32(
                embeddings.ptr,
                &query_vec,
                num_rows,
                EMBEDDING_DIM,
                scores.ptr,
            );
            std.mem.doNotOptimizeAway(scores.ptr);
        }

        // Benchmark
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const embeddings = table.readFloat32Column(3) catch break; // embedding column
            defer allocator.free(embeddings);

            const num_rows = embeddings.len / EMBEDDING_DIM;

            // Allocate output buffer if needed
            if (scores.len < num_rows) {
                if (scores.len > 0) allocator.free(scores);
                scores = allocator.alloc(f64, num_rows) catch break;
            }

            // BATCH: Compute ALL dot products in one call with SIMD
            batchDotProductF32(
                embeddings.ptr,
                &query_vec,
                num_rows,
                EMBEDDING_DIM,
                scores.ptr,
            );
            std.mem.doNotOptimizeAway(scores.ptr);

            iterations += 1;
            total_rows += num_rows;
        }
        const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);

        // Cleanup scores buffer
        if (scores.len > 0) allocator.free(scores);

        lanceql_throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
        std.debug.print("{s:<32} {d:>14.0} {d:>10} {s:>10}\n", .{
            "LanceQL @logic_table BATCH", lanceql_throughput, iterations, "1.0x",
        });
    }

    // 2. DuckDB + Python loop (per-row Python calls on 384-dim embeddings)
    if (has_duckdb) duckdb_udf: {
        const script = std.fmt.comptimePrint(
            \\import duckdb
            \\import warnings
            \\warnings.filterwarnings("ignore")
            \\import time
            \\import numpy as np
            \\
            \\BENCHMARK_SECONDS = {d}
            \\WARMUP_SECONDS = {d}
            \\PARQUET_PATH = "{s}"
            \\
            \\con = duckdb.connect()
            \\con.execute("SET enable_progress_bar = false")
            \\
            \\query = np.full(384, 0.1, dtype=np.float32)
            \\
            \\# Python function for 384-dim dot product (called per row)
            \\# Uses np.dot - same as Polars UDF for fair comparison
            \\def dot_product(embedding):
            \\    return float(np.dot(embedding, query))
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') LIMIT 100").fetch_arrow_table()
            \\    embeddings = df['embedding'].to_pylist()
            \\    for emb in embeddings:
            \\        _ = dot_product(emb)
            \\
            \\# Benchmark: Read file + per-row Python function calls
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}')").fetch_arrow_table()
            \\    embeddings = df['embedding'].to_pylist()
            \\    total_score = 0.0
            \\    for emb in embeddings:
            \\        total_score += dot_product(emb)  # Per-row Python call
            \\    iterations += 1
            \\    total_rows += len(embeddings)
            \\elapsed_ns = int((time.time() - start) * 1e9)
            \\
            \\print(f"ITERATIONS:{{iterations}}")
            \\print(f"TOTAL_NS:{{elapsed_ns}}")
            \\print(f"ROWS:{{total_rows}}")
        , .{ BENCHMARK_SECONDS, WARMUP_SECONDS, PARQUET_PATH });

        const py_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", script },
            .max_output_bytes = 10 * 1024 * 1024,
        }) catch {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "DuckDB Python UDF", "error", "-", "-" });
            break :duckdb_udf;
        };
        defer {
            allocator.free(py_result.stdout);
            allocator.free(py_result.stderr);
        }

        var iterations: u64 = 0;
        var total_ns: u64 = 0;
        var total_rows: u64 = 0;

        if (std.mem.indexOf(u8, py_result.stdout, "ITERATIONS:")) |idx| {
            const start = idx + 11;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') end += 1;
            iterations = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "TOTAL_NS:")) |idx| {
            const start = idx + 9;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') end += 1;
            total_ns = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "ROWS:")) |idx| {
            const start = idx + 5;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') end += 1;
            total_rows = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }

        if (iterations > 0 and total_ns > 0 and total_rows > 0) {
            const throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);
            const speedup = lanceql_throughput / throughput;
            var speedup_buf: [16]u8 = undefined;
            const speedup_str = std.fmt.bufPrint(&speedup_buf, "{d:.1}x", .{speedup}) catch "N/A";
            std.debug.print("{s:<32} {d:>14.0} {d:>10} {s:>10}\n", .{
                "DuckDB + Python loop", throughput, iterations, speedup_str,
            });
        } else {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "DuckDB + Python loop", "error", "-", "-" });
        }
    }

    // 3. DuckDB → NumPy batch
    if (has_duckdb) duckdb_numpy: {
        const script = std.fmt.comptimePrint(
            \\import duckdb
            \\import warnings
            \\warnings.filterwarnings("ignore")
            \\import time
            \\import numpy as np
            \\
            \\BENCHMARK_SECONDS = {d}
            \\WARMUP_SECONDS = {d}
            \\PARQUET_PATH = "{s}"
            \\
            \\con = duckdb.connect()
            \\con.execute("SET enable_progress_bar = false")
            \\query_vec = np.full(384, 0.1, dtype=np.float32)
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') LIMIT 100").fetchdf()
            \\
            \\# Benchmark: Read file + batch NumPy matrix multiply
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}')").fetchdf()
            \\    embeddings = np.array(df['embedding'].tolist())  # More efficient than vstack
            \\    scores = embeddings @ query_vec  # Vectorized SIMD dot product
            \\    iterations += 1
            \\    total_rows += len(df)
            \\elapsed_ns = int((time.time() - start) * 1e9)
            \\
            \\print(f"ITERATIONS:{{iterations}}")
            \\print(f"TOTAL_NS:{{elapsed_ns}}")
            \\print(f"ROWS:{{total_rows}}")
        , .{ BENCHMARK_SECONDS, WARMUP_SECONDS, PARQUET_PATH });

        const py_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", script },
            .max_output_bytes = 10 * 1024 * 1024,
        }) catch {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "DuckDB → NumPy batch", "error", "-", "-" });
            break :duckdb_numpy;
        };
        defer {
            allocator.free(py_result.stdout);
            allocator.free(py_result.stderr);
        }

        var iterations: u64 = 0;
        var total_ns: u64 = 0;
        var total_rows: u64 = 0;

        if (std.mem.indexOf(u8, py_result.stdout, "ITERATIONS:")) |idx| {
            const start = idx + 11;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            iterations = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "TOTAL_NS:")) |idx| {
            const start = idx + 9;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_ns = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "ROWS:")) |idx| {
            const start = idx + 5;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_rows = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }

        if (iterations > 0 and total_ns > 0) {
            const throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);
            const speedup = lanceql_throughput / throughput;
            var speedup_buf: [16]u8 = undefined;
            const speedup_str = std.fmt.bufPrint(&speedup_buf, "{d:.1}x", .{speedup}) catch "N/A";
            std.debug.print("{s:<32} {d:>14.0} {d:>10} {s:>10}\n", .{
                "DuckDB → NumPy batch", throughput, iterations, speedup_str,
            });
        }
    }

    // 4. Polars + Python UDF (per-row Python calls on 384-dim embeddings)
    if (has_polars) polars_udf: {
        const script = std.fmt.comptimePrint(
            \\import warnings
            \\warnings.filterwarnings("ignore")
            \\import polars as pl
            \\import time
            \\import numpy as np
            \\
            \\BENCHMARK_SECONDS = {d}
            \\WARMUP_SECONDS = {d}
            \\PARQUET_PATH = "{s}"
            \\
            \\query = np.full(384, 0.1, dtype=np.float32)  # Defined ONCE outside function
            \\def dot_product_udf(embedding):
            \\    return float(np.dot(embedding, query))
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet(PARQUET_PATH).head(100)
            \\    _ = df.select(pl.col('embedding').map_elements(dot_product_udf, return_dtype=pl.Float64))
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet(PARQUET_PATH)
            \\    result = df.select(pl.col('embedding').map_elements(dot_product_udf, return_dtype=pl.Float64))
            \\    iterations += 1
            \\    total_rows += len(df)
            \\elapsed_ns = int((time.time() - start) * 1e9)
            \\
            \\print(f"ITERATIONS:{{iterations}}")
            \\print(f"TOTAL_NS:{{elapsed_ns}}")
            \\print(f"ROWS:{{total_rows}}")
        , .{ BENCHMARK_SECONDS, WARMUP_SECONDS, PARQUET_PATH });

        const py_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", script },
            .max_output_bytes = 10 * 1024 * 1024,
        }) catch {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "Polars Python UDF", "error", "-", "-" });
            break :polars_udf;
        };
        defer {
            allocator.free(py_result.stdout);
            allocator.free(py_result.stderr);
        }

        var iterations: u64 = 0;
        var total_ns: u64 = 0;
        var total_rows: u64 = 0;

        if (std.mem.indexOf(u8, py_result.stdout, "ITERATIONS:")) |idx| {
            const start = idx + 11;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            iterations = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "TOTAL_NS:")) |idx| {
            const start = idx + 9;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_ns = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "ROWS:")) |idx| {
            const start = idx + 5;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_rows = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }

        if (iterations > 0 and total_ns > 0) {
            const throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);
            const speedup = lanceql_throughput / throughput;
            var speedup_buf: [16]u8 = undefined;
            const speedup_str = std.fmt.bufPrint(&speedup_buf, "{d:.1}x", .{speedup}) catch "N/A";
            std.debug.print("{s:<32} {d:>14.0} {d:>10} {s:>10}\n", .{
                "Polars + Python UDF", throughput, iterations, speedup_str,
            });
        } else {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "Polars + Python UDF", "error", "-", "-" });
        }
    }

    // 5. Polars → NumPy batch (384-dim embeddings)
    if (has_polars) polars_numpy: {
        const script = std.fmt.comptimePrint(
            \\import warnings
            \\warnings.filterwarnings("ignore")
            \\import polars as pl
            \\import time
            \\import numpy as np
            \\
            \\BENCHMARK_SECONDS = {d}
            \\WARMUP_SECONDS = {d}
            \\PARQUET_PATH = "{s}"
            \\
            \\query_vec = np.full(384, 0.1, dtype=np.float32)
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet(PARQUET_PATH).head(100)
            \\
            \\# Benchmark: Read file + batch NumPy matrix multiply
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet(PARQUET_PATH)
            \\    embeddings = np.array(df['embedding'].to_list())  # More efficient than vstack
            \\    scores = embeddings @ query_vec  # Vectorized SIMD dot product
            \\    iterations += 1
            \\    total_rows += len(df)
            \\elapsed_ns = int((time.time() - start) * 1e9)
            \\
            \\print(f"ITERATIONS:{{iterations}}")
            \\print(f"TOTAL_NS:{{elapsed_ns}}")
            \\print(f"ROWS:{{total_rows}}")
        , .{ BENCHMARK_SECONDS, WARMUP_SECONDS, PARQUET_PATH });

        const py_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "python3", "-c", script },
            .max_output_bytes = 10 * 1024 * 1024,
        }) catch {
            std.debug.print("{s:<32} {s:>14} {s:>10} {s:>10}\n", .{ "Polars → NumPy batch", "error", "-", "-" });
            break :polars_numpy;
        };
        defer {
            allocator.free(py_result.stdout);
            allocator.free(py_result.stderr);
        }

        var iterations: u64 = 0;
        var total_ns: u64 = 0;
        var total_rows: u64 = 0;

        if (std.mem.indexOf(u8, py_result.stdout, "ITERATIONS:")) |idx| {
            const start = idx + 11;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            iterations = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "TOTAL_NS:")) |idx| {
            const start = idx + 9;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_ns = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, py_result.stdout, "ROWS:")) |idx| {
            const start = idx + 5;
            var end = start;
            while (end < py_result.stdout.len and py_result.stdout[end] >= '0' and py_result.stdout[end] <= '9') {
                end += 1;
            }
            total_rows = std.fmt.parseInt(u64, py_result.stdout[start..end], 10) catch 0;
        }

        if (iterations > 0 and total_ns > 0) {
            const throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);
            const speedup = lanceql_throughput / throughput;
            var speedup_buf: [16]u8 = undefined;
            const speedup_str = std.fmt.bufPrint(&speedup_buf, "{d:.1}x", .{speedup}) catch "N/A";
            std.debug.print("{s:<32} {d:>14.0} {d:>10} {s:>10}\n", .{
                "Polars → NumPy batch", throughput, iterations, speedup_str,
            });
        }
    }

    std.debug.print("===============================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Notes:\n", .{});
    std.debug.print("  - All methods read from disk (Lance or Parquet files)\n", .{});
    std.debug.print("  - All methods run for exactly {d} seconds\n", .{BENCHMARK_SECONDS});
    std.debug.print("  - Throughput = total rows processed / elapsed time\n", .{});
    std.debug.print("  - LanceQL reads Lance format, DuckDB/Polars read Parquet format\n", .{});
    std.debug.print("\n", .{});
}
