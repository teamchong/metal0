//! Window Functions Benchmark - @logic_table vs Python UDFs
//!
//! SHOWCASE: Custom window functions that can't be done in standard SQL
//!
//! What we're comparing:
//!   1. LanceQL @logic_table  - Compiled native window function
//!   2. DuckDB + Python UDF   - Python callback per-window
//!   3. Polars map_elements   - Python per-row (slow)
//!
//! Window Function: Cumulative Weighted Average
//!   @logic_table
//!   class WindowOps:
//!       def cumulative_weighted_avg(self, values: list, weights: list) -> list:
//!           result = []
//!           cumsum_val = 0.0
//!           cumsum_weight = 0.0
//!           for i in range(len(values)):
//!               cumsum_val += values[i] * weights[i]
//!               cumsum_weight += weights[i]
//!               result.append(cumsum_val / cumsum_weight if cumsum_weight > 0 else 0)
//!           return result
//!
//! This beats Python because:
//!   - @logic_table compiles to native Zig (no Python interpreter overhead)
//!   - Vectorized memory access patterns
//!   - No GIL contention
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py
//!   zig build bench-window

const std = @import("std");
const Table = @import("lanceql.table").Table;

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";

// =============================================================================
// @logic_table COMPILED FUNCTION
// =============================================================================
// This is what metal0 compiles from Python @logic_table decorator.
// The Python source would be:
//
//   @logic_table
//   class WindowOps:
//       def cumulative_weighted_avg(self, values: list, weights: list) -> list:
//           result = []
//           cumsum_val = 0.0
//           cumsum_weight = 0.0
//           for i in range(len(values)):
//               cumsum_val += values[i] * weights[i]
//               cumsum_weight += weights[i]
//               result.append(cumsum_val / cumsum_weight if cumsum_weight > 0 else 0)
//           return result
//
// Compiled to native Zig:

fn WindowOps_cumulative_weighted_avg(
    values: [*]const f64,
    weights: [*]const f64,
    result: [*]f64,
    len: usize,
) void {
    var cumsum_val: f64 = 0.0;
    var cumsum_weight: f64 = 0.0;

    for (0..len) |i| {
        cumsum_val += values[i] * weights[i];
        cumsum_weight += weights[i];
        result[i] = if (cumsum_weight > 0) cumsum_val / cumsum_weight else 0;
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

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

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("Window Functions Benchmark: @logic_table vs Python UDFs\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\nOperation: Cumulative Weighted Average (custom window function)\n", .{});
    std.debug.print("This CAN'T be done in standard SQL - requires Python UDF or @logic_table\n", .{});
    std.debug.print("\nEach method runs for {d} seconds. Measuring throughput (rows/sec).\n", .{BENCHMARK_SECONDS});
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

    std.debug.print("\nEngines:\n", .{});
    std.debug.print("  LanceQL @logic_table: yes (compiled native)\n", .{});
    std.debug.print("  DuckDB + Python UDF:  {s}\n", .{if (has_duckdb) "yes" else "no"});
    std.debug.print("  Polars map_elements:  {s}\n", .{if (has_polars) "yes" else "no"});
    std.debug.print("\n", .{});

    // ==========================================================================
    // CUMULATIVE WEIGHTED AVERAGE
    // ==========================================================================
    std.debug.print("================================================================================\n", .{});
    std.debug.print("CUMULATIVE WEIGHTED AVERAGE: sum(v[i]*w[i]) / sum(w[i]) for i=0..n\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "-" ** 45, "-" ** 12, "-" ** 12, "-" ** 10 });

    // Allocate result buffer once
    var result_buffer: [100000]f64 = undefined;

    var lanceql_rps: f64 = 0;
    {
        // LanceQL @logic_table - COMPILED native function
        var iterations: u64 = 0;
        var total_rows: u64 = 0;

        // Warmup
        const warmup_end = std.time.nanoTimestamp() + WARMUP_SECONDS * 1_000_000_000;
        while (std.time.nanoTimestamp() < warmup_end) {
            const file_data = readLanceFile(allocator) catch break;
            defer allocator.free(file_data);
            var table = Table.init(allocator, file_data) catch break;
            defer table.deinit();

            // Use 'amount' as values and 'id' as weights (simulating real data)
            const amounts = table.readFloat64Column(1) catch break;
            defer allocator.free(amounts);
            const ids = table.readInt64Column(0) catch break;
            defer allocator.free(ids);

            // Convert ids to f64 weights
            var weights: [100000]f64 = undefined;
            for (ids, 0..) |id, i| {
                weights[i] = @as(f64, @floatFromInt(id)) + 1.0; // +1 to avoid zero weights
            }

            // Call compiled @logic_table function
            WindowOps_cumulative_weighted_avg(amounts.ptr, &weights, &result_buffer, amounts.len);
            std.mem.doNotOptimizeAway(&result_buffer);
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
            const ids = table.readInt64Column(0) catch break;
            defer allocator.free(ids);

            var weights: [100000]f64 = undefined;
            for (ids, 0..) |id, i| {
                weights[i] = @as(f64, @floatFromInt(id)) + 1.0;
            }

            WindowOps_cumulative_weighted_avg(amounts.ptr, &weights, &result_buffer, amounts.len);
            std.mem.doNotOptimizeAway(&result_buffer);

            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_rps = @as(f64, @floatFromInt(total_rows)) / elapsed_s;
        std.debug.print("{s:<45} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL @logic_table (COMPILED)",
            lanceql_rps / 1000.0,
            iterations,
            "1.0x",
        });
    }

    // DuckDB Python UDF
    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import numpy as np
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\def cumulative_weighted_avg(values, weights):
            \\    """Python UDF - runs in Python interpreter (SLOW)"""
            \\    result = []
            \\    cumsum_val = 0.0
            \\    cumsum_weight = 0.0
            \\    for i in range(len(values)):
            \\        cumsum_val += values[i] * weights[i]
            \\        cumsum_weight += weights[i]
            \\        result.append(cumsum_val / cumsum_weight if cumsum_weight > 0 else 0)
            \\    return result
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("SELECT amount, id FROM read_parquet('{s}')").fetchdf()
            \\    values = df['amount'].values
            \\    weights = df['id'].values.astype(float) + 1.0
            \\    _ = cumulative_weighted_avg(values, weights)
            \\    con.close()
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("SELECT amount, id FROM read_parquet('{s}')").fetchdf()
            \\    values = df['amount'].values
            \\    weights = df['id'].values.astype(float) + 1.0
            \\    _ = cumulative_weighted_avg(values, weights)
            \\    total_rows += len(df)
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
            std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB + Python UDF (INTERPRETED)", "error", "-", "-" });
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
            const speedup = lanceql_rps / rows_per_sec;
            std.debug.print("{s:<45} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB + Python UDF (INTERPRETED)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // DuckDB with NumPy (vectorized Python - still slower than native)
    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import numpy as np
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\def cumulative_weighted_avg_numpy(values, weights):
            \\    """NumPy vectorized - better than pure Python but still has overhead"""
            \\    weighted = values * weights
            \\    cumsum_weighted = np.cumsum(weighted)
            \\    cumsum_weights = np.cumsum(weights)
            \\    return np.where(cumsum_weights > 0, cumsum_weighted / cumsum_weights, 0)
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("SELECT amount, id FROM read_parquet('{s}')").fetchdf()
            \\    values = df['amount'].values
            \\    weights = df['id'].values.astype(float) + 1.0
            \\    _ = cumulative_weighted_avg_numpy(values, weights)
            \\    con.close()
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    df = con.execute("SELECT amount, id FROM read_parquet('{s}')").fetchdf()
            \\    values = df['amount'].values
            \\    weights = df['id'].values.astype(float) + 1.0
            \\    _ = cumulative_weighted_avg_numpy(values, weights)
            \\    total_rows += len(df)
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
            std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB → NumPy (VECTORIZED)", "error", "-", "-" });
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
            const speedup = lanceql_rps / rows_per_sec;
            std.debug.print("{s:<45} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB → NumPy (VECTORIZED)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // Polars with map_elements (per-row Python - VERY slow)
    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\def cumulative_weighted_avg(values, weights):
            \\    """Python function - same as DuckDB UDF"""
            \\    result = []
            \\    cumsum_val = 0.0
            \\    cumsum_weight = 0.0
            \\    for i in range(len(values)):
            \\        cumsum_val += values[i] * weights[i]
            \\        cumsum_weight += weights[i]
            \\        result.append(cumsum_val / cumsum_weight if cumsum_weight > 0 else 0)
            \\    return result
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}", columns=["amount", "id"])
            \\    values = df["amount"].to_numpy()
            \\    weights = df["id"].to_numpy().astype(float) + 1.0
            \\    _ = cumulative_weighted_avg(values, weights)
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}", columns=["amount", "id"])
            \\    values = df["amount"].to_numpy()
            \\    weights = df["id"].to_numpy().astype(float) + 1.0
            \\    _ = cumulative_weighted_avg(values, weights)
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
            std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "Polars + Python UDF (INTERPRETED)", "error", "-", "-" });
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
            const speedup = lanceql_rps / rows_per_sec;
            std.debug.print("{s:<45} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars + Python UDF (INTERPRETED)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        }
    }

    // Polars with NumPy vectorized
    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import numpy as np
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\
            \\def cumulative_weighted_avg_numpy(values, weights):
            \\    """NumPy vectorized"""
            \\    weighted = values * weights
            \\    cumsum_weighted = np.cumsum(weighted)
            \\    cumsum_weights = np.cumsum(weights)
            \\    return np.where(cumsum_weights > 0, cumsum_weighted / cumsum_weights, 0)
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}", columns=["amount", "id"])
            \\    values = df["amount"].to_numpy()
            \\    weights = df["id"].to_numpy().astype(float) + 1.0
            \\    _ = cumulative_weighted_avg_numpy(values, weights)
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}", columns=["amount", "id"])
            \\    values = df["amount"].to_numpy()
            \\    weights = df["id"].to_numpy().astype(float) + 1.0
            \\    _ = cumulative_weighted_avg_numpy(values, weights)
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
            std.debug.print("{s:<45} {s:>12} {s:>12} {s:>10}\n", .{ "Polars → NumPy (VECTORIZED)", "error", "-", "-" });
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
            const speedup = lanceql_rps / rows_per_sec;
            std.debug.print("{s:<45} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars → NumPy (VECTORIZED)",
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
    std.debug.print("@logic_table advantage: Custom window functions compiled to native code\n", .{});
    std.debug.print("- Python UDF (INTERPRETED): Runs in Python interpreter, GIL overhead\n", .{});
    std.debug.print("- NumPy (VECTORIZED): Better but still has Python/C boundary overhead\n", .{});
    std.debug.print("- @logic_table (COMPILED): Pure native Zig, zero interpreter overhead\n", .{});
    std.debug.print("\n", .{});
}
