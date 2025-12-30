//! @logic_table Pushdown Benchmark - End-to-End Comparison
//!
//! HONEST benchmark measuring filter + compute from cold start:
//!   1. LanceQL @logic_table  - Read Lance file → filter → compute with COMPILED Python
//!   2. DuckDB + Python loop  - Read Parquet → filter → row-by-row Python
//!   3. DuckDB → NumPy batch  - Read Parquet → filter → NumPy compute
//!   4. Polars + Python loop  - Read Parquet → filter → row-by-row Python
//!   5. Polars → NumPy batch  - Read Parquet → filter → NumPy compute
//!
//! FAIR COMPARISON:
//!   - All methods read from disk (Lance or Parquet files)
//!   - All methods run for exactly 15 seconds
//!   - Throughput measured as rows processed per second
//!   - Filter condition: amount > 500 (filters ~50% of data)
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py  # Creates test data
//!   zig build bench-pushdown

const std = @import("std");
const Table = @import("lanceql.table").Table;

// Extern declaration for COMPILED @logic_table function
// This is Python code compiled to native Zig by metal0
// Source: benchmarks/vector_ops.py -> lib/vector_ops.a
extern fn VectorOps_dot_product(a: [*]const f64, b: [*]const f64, len: usize) f64;

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";
const EMBEDDING_DIM = 384;

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
    std.debug.print("================================================================================\n", .{});
    std.debug.print("@logic_table Pushdown Benchmark: End-to-End (Filter + Compute)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Each method runs for {d} seconds. Measuring throughput (rows/sec).\n", .{BENCHMARK_SECONDS});
    std.debug.print("Filter: amount > 500.0 (filters ~50%% of data)\n", .{});
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
    const has_duckdb = checkPythonModule(allocator, "duckdb");
    const has_polars = checkPythonModule(allocator, "polars");

    std.debug.print("Data files:\n", .{});
    std.debug.print("  Lance:   {s} ✓\n", .{LANCE_PATH});
    std.debug.print("  Parquet: {s} ✓\n", .{PARQUET_PATH});
    std.debug.print("\n", .{});
    std.debug.print("Engines:\n", .{});
    std.debug.print("  LanceQL @logic_table: yes\n", .{});
    std.debug.print("  DuckDB:               {s}\n", .{if (has_duckdb) "yes" else "no (pip install duckdb)"});
    std.debug.print("  Polars:               {s}\n", .{if (has_polars) "yes" else "no (pip install polars)"});
    std.debug.print("\n", .{});

    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("================================================================================\n", .{});

    var lanceql_throughput: f64 = 0;

    // 1. LanceQL @logic_table (read Lance file → filter → compute with COMPILED Python)
    {
        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * std.time.ns_per_s;
        const benchmark_end_time = warmup_end + BENCHMARK_SECONDS * std.time.ns_per_s;

        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Query vector as f64 (VectorOps_dot_product expects f64)
        var query_vec: [EMBEDDING_DIM]f64 = undefined;
        for (&query_vec) |*v| v.* = 0.1;

        // Pre-allocate conversion buffer for f32 -> f64
        var emb_f64: [EMBEDDING_DIM]f64 = undefined;

        // Warmup
        while (std.time.nanoTimestamp() < warmup_end) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const embeddings = table.readFloat32Column(2) catch break;
            defer allocator.free(embeddings);
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);

            const num_rows = embeddings.len / EMBEDDING_DIM;
            var total_score: f64 = 0;
            for (0..num_rows) |row| {
                // Filter: amount > 500
                if (amounts[row] > 500.0) {
                    const emb = embeddings[row * EMBEDDING_DIM .. (row + 1) * EMBEDDING_DIM];
                    // Convert f32 -> f64 for the compiled function
                    for (emb, 0..) |v, i| emb_f64[i] = v;
                    // VectorOps_dot_product is COMPILED from Python @logic_table
                    total_score += VectorOps_dot_product(&emb_f64, &query_vec, EMBEDDING_DIM);
                }
            }
            std.mem.doNotOptimizeAway(&total_score);
        }

        // Benchmark
        const start_time = std.time.nanoTimestamp();
        while (std.time.nanoTimestamp() < benchmark_end_time) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);

            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            const embeddings = table.readFloat32Column(2) catch break;
            defer allocator.free(embeddings);
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);

            const num_rows = embeddings.len / EMBEDDING_DIM;
            var total_score: f64 = 0;
            var filtered_rows: u64 = 0;
            for (0..num_rows) |row| {
                // Filter: amount > 500
                if (amounts[row] > 500.0) {
                    const emb = embeddings[row * EMBEDDING_DIM .. (row + 1) * EMBEDDING_DIM];
                    // Convert f32 -> f64 for the compiled function
                    for (emb, 0..) |v, i| emb_f64[i] = v;
                    // VectorOps_dot_product is COMPILED from Python @logic_table
                    total_score += VectorOps_dot_product(&emb_f64, &query_vec, EMBEDDING_DIM);
                    filtered_rows += 1;
                }
            }
            std.mem.doNotOptimizeAway(&total_score);

            iterations += 1;
            total_rows += filtered_rows;
        }
        const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);

        lanceql_throughput = @as(f64, @floatFromInt(total_rows)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
        std.debug.print("{s:<35} {d:>12.0} {d:>12} {s:>10}\n", .{
            "LanceQL @logic_table", lanceql_throughput, iterations, "1.0x",
        });
    }

    // 2. DuckDB + Python loop (filter + 384-dim dot product per row)
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
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') WHERE amount > 500 LIMIT 100").fetch_arrow_table()
            \\    embeddings = df['embedding'].to_pylist()
            \\    for emb in embeddings:
            \\        _ = dot_product(emb)
            \\
            \\# Benchmark: Read + filter + per-row Python function calls
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') WHERE amount > 500").fetch_arrow_table()
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
            std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB Python UDF", "error", "-", "-" });
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
            std.debug.print("{s:<35} {d:>12.0} {d:>12} {s:>10}\n", .{
                "DuckDB + Python loop", throughput, iterations, speedup_str,
            });
        } else {
            std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB + Python loop", "error", "-", "-" });
        }
    }

    // 3. DuckDB → NumPy batch (filter + 384-dim batch)
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
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') WHERE amount > 500 LIMIT 100").fetchdf()
            \\
            \\# Benchmark: Filter + batch NumPy matrix multiply
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = con.execute(f"SELECT embedding FROM read_parquet('{{PARQUET_PATH}}') WHERE amount > 500").fetchdf()
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
            std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB → NumPy batch", "error", "-", "-" });
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
            std.debug.print("{s:<35} {d:>12.0} {d:>12} {s:>10}\n", .{
                "DuckDB → NumPy batch", throughput, iterations, speedup_str,
            });
        }
    }

    // 4. Polars Python UDF (filter + Python UDF per row)
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
            \\    df = pl.read_parquet(PARQUET_PATH).filter(pl.col('amount') > 500).head(100)
            \\    _ = df.select(pl.col('embedding').map_elements(dot_product_udf, return_dtype=pl.Float64))
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet(PARQUET_PATH).filter(pl.col('amount') > 500)
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
            std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "Polars Python UDF", "error", "-", "-" });
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
            std.debug.print("{s:<35} {d:>12.0} {d:>12} {s:>10}\n", .{
                "Polars Python UDF", throughput, iterations, speedup_str,
            });
        }
    }

    // 5. Polars → NumPy batch (filter in Polars, compute in NumPy)
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
            \\    df = pl.read_parquet(PARQUET_PATH).filter(pl.col('amount') > 500).head(100)
            \\
            \\# Benchmark: Filter + batch NumPy matrix multiply
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet(PARQUET_PATH).filter(pl.col('amount') > 500)
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
            std.debug.print("{s:<35} {s:>12} {s:>12} {s:>10}\n", .{ "Polars → NumPy batch", "error", "-", "-" });
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
            std.debug.print("{s:<35} {d:>12.0} {d:>12} {s:>10}\n", .{
                "Polars → NumPy batch", throughput, iterations, speedup_str,
            });
        }
    }

    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Notes:\n", .{});
    std.debug.print("  - All methods include filter pushdown (WHERE amount > 500)\n", .{});
    std.debug.print("  - All methods read from disk (Lance or Parquet files)\n", .{});
    std.debug.print("  - All methods run for exactly {d} seconds\n", .{BENCHMARK_SECONDS});
    std.debug.print("  - Throughput = filtered rows processed / elapsed time\n", .{});
    std.debug.print("\n", .{});
}
