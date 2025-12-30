//! RAG Pipeline Benchmark - End-to-End Comparison
//!
//! HONEST benchmark simulating RAG (Retrieval-Augmented Generation) pipeline:
//!   1. LanceQL native  - Read Lance file → compute similarity scores
//!   2. DuckDB SQL           - Read Parquet → compute similarity via SQL
//!   3. Polars DataFrame     - Read Parquet → compute similarity
//!
//! FAIR COMPARISON:
//!   - All methods read from disk (Lance or Parquet files)
//!   - All methods run for exactly 15 seconds
//!   - Throughput measured as rows processed per second
//!   - Simulates RAG by computing similarity between query and document scores
//!
//! Setup:
//!   python3 benchmarks/generate_benchmark_data.py  # Creates test data
//!   zig build bench-rag

const std = @import("std");
const Table = @import("lanceql.table").Table;

const WARMUP_SECONDS = 2;
const BENCHMARK_SECONDS = 15;
const LANCE_PATH = "benchmarks/benchmark_e2e.lance";
const PARQUET_PATH = "benchmarks/benchmark_e2e.parquet";

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
    std.debug.print("RAG Pipeline Benchmark: End-to-End (Read + Similarity Search)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\nPipeline: Read file → compute similarity scores → find top matches\n", .{});
    std.debug.print("Simulates retrieval-augmented generation document search.\n", .{});
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

    std.debug.print("\nEngines:\n", .{});
    std.debug.print("  LanceQL native: yes\n", .{});
    std.debug.print("  DuckDB:               {s}\n", .{if (has_duckdb) "yes" else "no"});
    std.debug.print("  Polars:               {s}\n", .{if (has_polars) "yes" else "no"});
    std.debug.print("\n", .{});

    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Method", "Rows/sec", "Iterations", "Speedup" });
    std.debug.print("================================================================================\n", .{});

    var lanceql_rows_per_sec: f64 = 0;

    // Query value for similarity (simulates embedding query)
    const query_value: f64 = 150.0;

    // =========================================================================
    // LanceQL native - Read Lance file, compute similarity scores
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

            // Compute similarity: how close is each amount to query_value
            // This simulates finding documents similar to a query embedding
            var top_score: f64 = -std.math.inf(f64);
            for (amounts) |a| {
                const diff = @abs(a - query_value);
                const similarity = 1.0 / (1.0 + diff); // Inverse distance
                top_score = @max(top_score, similarity);
            }
            std.mem.doNotOptimizeAway(&top_score);
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

            // Compute similarity: how close is each amount to query_value
            var top_score: f64 = -std.math.inf(f64);
            for (amounts) |a| {
                const diff = @abs(a - query_value);
                const similarity = 1.0 / (1.0 + diff);
                top_score = @max(top_score, similarity);
            }
            std.mem.doNotOptimizeAway(&top_score);

            iterations += 1;
            total_rows += amounts.len;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        lanceql_rows_per_sec = @as(f64, @floatFromInt(total_rows)) / elapsed_s;

        std.debug.print("{s:<40} {d:>10.0}K {d:>12} {s:>10}\n", .{
            "LanceQL native (similarity search)",
            lanceql_rows_per_sec / 1000.0,
            iterations,
            "1.0x",
        });
    }

    // =========================================================================
    // DuckDB - Read Parquet file, compute similarity via SQL
    // =========================================================================
    if (has_duckdb) {
        const py_script = std.fmt.comptimePrint(
            \\import duckdb
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\query_value = 150.0
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    con = duckdb.connect()
            \\    # Compute similarity score and find max
            \\    df = con.execute(f"""
            \\        SELECT MAX(1.0 / (1.0 + ABS(amount - {{query_value}}))) as top_score
            \\        FROM read_parquet('{s}')
            \\    """).fetchdf()
            \\    con.close()
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    con = duckdb.connect()
            \\    result = con.execute(f"""
            \\        SELECT COUNT(*), MAX(1.0 / (1.0 + ABS(amount - {{query_value}}))) as top_score
            \\        FROM read_parquet('{s}')
            \\    """).fetchone()
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
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "DuckDB SQL (similarity search)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        } else {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "DuckDB SQL", "error", "-", "-" });
        }
    }

    // =========================================================================
    // Polars - Read Parquet file, compute similarity via DataFrame
    // =========================================================================
    if (has_polars) {
        const py_script = std.fmt.comptimePrint(
            \\import polars as pl
            \\import time
            \\
            \\WARMUP_SECONDS = {d}
            \\BENCHMARK_SECONDS = {d}
            \\query_value = 150.0
            \\
            \\# Warmup
            \\warmup_end = time.time() + WARMUP_SECONDS
            \\while time.time() < warmup_end:
            \\    df = pl.read_parquet("{s}")
            \\    # Compute similarity score
            \\    similarity = 1.0 / (1.0 + (df["amount"] - query_value).abs())
            \\    top_score = similarity.max()
            \\
            \\# Benchmark
            \\iterations = 0
            \\total_rows = 0
            \\start = time.time()
            \\benchmark_end = start + BENCHMARK_SECONDS
            \\while time.time() < benchmark_end:
            \\    df = pl.read_parquet("{s}")
            \\    similarity = 1.0 / (1.0 + (df["amount"] - query_value).abs())
            \\    top_score = similarity.max()
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
            std.debug.print("{s:<40} {d:>10.0}K {d:>12} {d:>9.1}x\n", .{
                "Polars DataFrame (similarity search)",
                rows_per_sec / 1000.0,
                iterations,
                speedup,
            });
        } else {
            std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10}\n", .{ "Polars DataFrame", "error", "-", "-" });
        }
    }

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("Summary\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("All methods: Read file → compute similarity → find top match\n", .{});
    std.debug.print("Similarity: 1/(1 + |value - query|) - higher is more similar\n", .{});
    std.debug.print("\n", .{});
}
