//! Parquet Reader Benchmark: LanceQL vs DuckDB vs Polars
//!
//! Usage: zig build bench-parquet && ./zig-out/bin/bench_parquet <parquet_file>

const std = @import("std");

// Engine availability
var has_duckdb: bool = false;
var has_polars: bool = false;

fn checkCommand(alloc: std.mem.Allocator, cmd: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "which", cmd },
    }) catch return false;
    defer {
        alloc.free(result.stdout);
        alloc.free(result.stderr);
    }
    switch (result.term) {
        .Exited => |code| return code == 0,
        else => return false,
    }
}

fn runDuckDB(alloc: std.mem.Allocator, sql: []const u8) !u64 {
    var timer = try std.time.Timer.start();
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "duckdb", "-csv", "-c", sql },
        .max_output_bytes = 100 * 1024 * 1024, // 100MB for parquet output
    }) catch return error.DuckDBFailed;
    defer {
        alloc.free(result.stdout);
        alloc.free(result.stderr);
    }
    switch (result.term) {
        .Exited => |code| if (code != 0) return error.DuckDBFailed,
        else => return error.DuckDBFailed,
    }
    return timer.read();
}

fn runPolars(alloc: std.mem.Allocator, code: []const u8) !u64 {
    var timer = try std.time.Timer.start();
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "python3", "-c", code },
        .max_output_bytes = 100 * 1024 * 1024, // 100MB
    }) catch return error.PolarsFailed;
    defer {
        alloc.free(result.stdout);
        alloc.free(result.stderr);
    }
    switch (result.term) {
        .Exited => |exit_code| if (exit_code != 0) return error.PolarsFailed,
        else => return error.PolarsFailed,
    }
    return timer.read();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <parquet_file>\n", .{args[0]});
        return;
    }

    const file_path = args[1];

    // Check available engines
    has_duckdb = checkCommand(allocator, "duckdb");
    has_polars = checkCommand(allocator, "python3");

    // Read file into memory
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const data = try allocator.alloc(u8, file_size);
    defer allocator.free(data);

    _ = try file.readAll(data);

    std.debug.print("================================================================================\n", .{});
    std.debug.print("Parquet Reader Benchmark: LanceQL vs DuckDB vs Polars\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("File: {s}\n", .{file_path});
    std.debug.print("Size: {d:.2} MB\n", .{@as(f64, @floatFromInt(file_size)) / 1024 / 1024});
    std.debug.print("\nEngines:\n", .{});
    std.debug.print("  - LanceQL:  yes\n", .{});
    std.debug.print("  - DuckDB:   {s}\n", .{if (has_duckdb) "yes" else "no"});
    std.debug.print("  - Polars:   {s}\n", .{if (has_polars) "yes" else "no"});
    std.debug.print("\n", .{});

    // Import parquet modules
    const format = @import("lanceql.format");
    const ParquetFile = format.ParquetFile;
    const parquet_enc = @import("lanceql.encoding.parquet");
    const PageReader = parquet_enc.PageReader;

    // Warmup
    const warmup_iterations = 3;
    const bench_iterations = 10;

    std.debug.print("Warming up ({d} iterations)...\n", .{warmup_iterations});
    for (0..warmup_iterations) |_| {
        var pf = try ParquetFile.init(allocator, data);
        defer pf.deinit();

        const rg = pf.getRowGroup(0) orelse continue;
        for (0..rg.columns.len) |col_idx| {
            const col = rg.columns[col_idx];
            const col_meta = col.meta_data orelse continue;
            const col_data = pf.getColumnData(0, col_idx) orelse continue;

            var reader = PageReader.init(col_data, col_meta.type_, null, col_meta.codec, allocator);
            defer reader.deinit();

            var page = reader.readAll() catch continue;
            defer page.deinit(allocator);
        }
    }

    // Benchmark
    std.debug.print("Running benchmark ({d} iterations)...\n\n", .{bench_iterations});

    var total_ns: u64 = 0;
    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_rows: usize = 0;

    for (0..bench_iterations) |_| {
        var timer = try std.time.Timer.start();

        var pf = try ParquetFile.init(allocator, data);
        defer pf.deinit();

        const rg = pf.getRowGroup(0) orelse continue;
        var rows_in_rg: usize = 0;

        for (0..rg.columns.len) |col_idx| {
            const col = rg.columns[col_idx];
            const col_meta = col.meta_data orelse continue;
            const col_data = pf.getColumnData(0, col_idx) orelse continue;

            var reader = PageReader.init(col_data, col_meta.type_, null, col_meta.codec, allocator);
            defer reader.deinit();

            var page = reader.readAll() catch continue;
            defer page.deinit(allocator);

            if (col_idx == 0) rows_in_rg = page.num_values;
        }

        const elapsed = timer.read();
        total_ns += elapsed;
        min_ns = @min(min_ns, elapsed);
        max_ns = @max(max_ns, elapsed);
        total_rows += rows_in_rg;
    }

    const avg_ns = total_ns / bench_iterations;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000;
    const min_ms = @as(f64, @floatFromInt(min_ns)) / 1_000_000;
    const max_ms = @as(f64, @floatFromInt(max_ns)) / 1_000_000;
    const avg_rows = total_rows / bench_iterations;
    const throughput = @as(f64, @floatFromInt(avg_rows)) / (avg_ms / 1000) / 1_000_000;

    std.debug.print("LanceQL Results:\n", .{});
    std.debug.print("  Rows per iteration: {d}\n", .{avg_rows});
    std.debug.print("  Min:  {d:.2} ms\n", .{min_ms});
    std.debug.print("  Avg:  {d:.2} ms\n", .{avg_ms});
    std.debug.print("  Max:  {d:.2} ms\n", .{max_ms});
    std.debug.print("  Throughput: {d:.2}M rows/sec\n", .{throughput});

    // =========================================================================
    // DuckDB Benchmark
    // =========================================================================
    if (has_duckdb) {
        std.debug.print("\nDuckDB Benchmark ({d} iterations)...\n", .{bench_iterations});

        const sql = try std.fmt.allocPrint(allocator,
            \\SELECT COUNT(*) FROM read_parquet('{s}');
        , .{file_path});
        defer allocator.free(sql);

        // Warmup
        for (0..warmup_iterations) |_| {
            _ = runDuckDB(allocator, sql) catch 0;
        }

        var duckdb_total_ns: u64 = 0;
        var duckdb_min_ns: u64 = std.math.maxInt(u64);
        var duckdb_max_ns: u64 = 0;

        for (0..bench_iterations) |_| {
            const elapsed = runDuckDB(allocator, sql) catch 0;
            duckdb_total_ns += elapsed;
            duckdb_min_ns = @min(duckdb_min_ns, elapsed);
            duckdb_max_ns = @max(duckdb_max_ns, elapsed);
        }

        const duckdb_avg_ns = duckdb_total_ns / bench_iterations;
        const duckdb_avg_ms = @as(f64, @floatFromInt(duckdb_avg_ns)) / 1_000_000;
        const duckdb_min_ms = @as(f64, @floatFromInt(duckdb_min_ns)) / 1_000_000;
        const duckdb_max_ms = @as(f64, @floatFromInt(duckdb_max_ns)) / 1_000_000;
        const duckdb_throughput = @as(f64, @floatFromInt(avg_rows)) / (duckdb_avg_ms / 1000) / 1_000_000;

        std.debug.print("DuckDB Results:\n", .{});
        std.debug.print("  Min:  {d:.2} ms\n", .{duckdb_min_ms});
        std.debug.print("  Avg:  {d:.2} ms\n", .{duckdb_avg_ms});
        std.debug.print("  Max:  {d:.2} ms\n", .{duckdb_max_ms});
        std.debug.print("  Throughput: {d:.2}M rows/sec\n", .{duckdb_throughput});
        std.debug.print("  vs LanceQL: {d:.1}x\n", .{duckdb_avg_ms / avg_ms});
    }

    // =========================================================================
    // Polars Benchmark
    // =========================================================================
    if (has_polars) {
        std.debug.print("\nPolars Benchmark ({d} iterations)...\n", .{bench_iterations});

        const py_code = try std.fmt.allocPrint(allocator,
            \\import polars as pl
            \\df = pl.read_parquet('{s}')
            \\print(len(df))
        , .{file_path});
        defer allocator.free(py_code);

        // Warmup
        for (0..warmup_iterations) |_| {
            _ = runPolars(allocator, py_code) catch 0;
        }

        var polars_total_ns: u64 = 0;
        var polars_min_ns: u64 = std.math.maxInt(u64);
        var polars_max_ns: u64 = 0;

        for (0..bench_iterations) |_| {
            const elapsed = runPolars(allocator, py_code) catch 0;
            polars_total_ns += elapsed;
            polars_min_ns = @min(polars_min_ns, elapsed);
            polars_max_ns = @max(polars_max_ns, elapsed);
        }

        const polars_avg_ns = polars_total_ns / bench_iterations;
        const polars_avg_ms = @as(f64, @floatFromInt(polars_avg_ns)) / 1_000_000;
        const polars_min_ms = @as(f64, @floatFromInt(polars_min_ns)) / 1_000_000;
        const polars_max_ms = @as(f64, @floatFromInt(polars_max_ns)) / 1_000_000;
        const polars_throughput = @as(f64, @floatFromInt(avg_rows)) / (polars_avg_ms / 1000) / 1_000_000;

        std.debug.print("Polars Results:\n", .{});
        std.debug.print("  Min:  {d:.2} ms\n", .{polars_min_ms});
        std.debug.print("  Avg:  {d:.2} ms\n", .{polars_avg_ms});
        std.debug.print("  Max:  {d:.2} ms\n", .{polars_max_ms});
        std.debug.print("  Throughput: {d:.2}M rows/sec\n", .{polars_throughput});
        std.debug.print("  vs LanceQL: {d:.1}x\n", .{polars_avg_ms / avg_ms});
    }

    // =========================================================================
    // Summary
    // =========================================================================
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("Summary\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("{s:<20} {s:>15}\n", .{ "Engine", "Throughput" });
    std.debug.print("{s:<20} {s:>15}\n", .{ "-" ** 20, "-" ** 15 });
    std.debug.print("{s:<20} {d:>12.2}M/s\n", .{ "LanceQL", throughput });
    std.debug.print("\nNote: DuckDB/Polars times include subprocess overhead.\n", .{});
}
