//! Tests for Parquet file parsing.

const std = @import("std");
const format = @import("lanceql.format");
const ParquetFile = format.ParquetFile;
const ParquetError = format.ParquetError;
const CompressionCodec = format.parquet_metadata.CompressionCodec;
const parquet_enc = @import("lanceql.encoding.parquet");
const PageReader = parquet_enc.PageReader;

test "parse simple parquet file" {
    const allocator = std.testing.allocator;

    // Read the test file
    const file = std.fs.cwd().openFile("tests/fixtures/simple.parquet", .{}) catch |err| {
        std.debug.print("Could not open test file: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.debug.print("Could not read test file: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    // Parse the file
    var pf = try ParquetFile.init(allocator, data);
    defer pf.deinit();

    // Verify metadata
    std.debug.print("\n=== Parquet File Info ===\n", .{});
    std.debug.print("Version: {}\n", .{pf.getVersion()});
    std.debug.print("Rows: {}\n", .{pf.getNumRows()});
    std.debug.print("Row Groups: {}\n", .{pf.getNumRowGroups()});
    std.debug.print("Columns: {}\n", .{pf.getNumColumns()});

    if (pf.getCreatedBy()) |created_by| {
        std.debug.print("Created By: {s}\n", .{created_by});
    }

    // Should have 5 rows (from our test data)
    try std.testing.expectEqual(@as(i64, 5), pf.getNumRows());

    // Should have 1 row group
    try std.testing.expectEqual(@as(usize, 1), pf.getNumRowGroups());

    // Should have 3 columns (id, name, value)
    try std.testing.expectEqual(@as(usize, 3), pf.getNumColumns());

    // Get column names
    const names = try pf.getColumnNames();
    defer allocator.free(names);

    std.debug.print("\nColumns:\n", .{});
    for (names) |name| {
        std.debug.print("  - {s}\n", .{name});
    }

    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("id", names[0]);
    try std.testing.expectEqualStrings("name", names[1]);
    try std.testing.expectEqualStrings("value", names[2]);

    // Print schema
    std.debug.print("\nSchema:\n", .{});
    for (pf.getSchema(), 0..) |elem, i| {
        std.debug.print("  {}: {s}", .{ i, elem.name });
        if (elem.type_) |t| {
            std.debug.print(" ({s})", .{@tagName(t)});
        }
        if (elem.num_children) |nc| {
            std.debug.print(" (group, {} children)", .{nc});
        }
        std.debug.print("\n", .{});
    }
}

test "reject non-parquet file" {
    const allocator = std.testing.allocator;

    // Try to parse a Lance file as Parquet
    const file = std.fs.cwd().openFile("tests/fixtures/simple_int64.lance/data/0.lance", .{}) catch {
        // File doesn't exist, skip
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    // Should fail with InvalidMagic
    const result = ParquetFile.init(allocator, data);
    try std.testing.expectError(ParquetError.InvalidMagic, result);
}

test "row group metadata" {
    const allocator = std.testing.allocator;

    const file = std.fs.cwd().openFile("tests/fixtures/simple.parquet", .{}) catch {
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    var pf = try ParquetFile.init(allocator, data);
    defer pf.deinit();

    // Get row group
    const rg = pf.getRowGroup(0) orelse return error.SkipZigTest;

    std.debug.print("\n=== Row Group 0 ===\n", .{});
    std.debug.print("Rows: {}\n", .{rg.num_rows});
    std.debug.print("Columns: {}\n", .{rg.columns.len});
    std.debug.print("Total Bytes: {}\n", .{rg.total_byte_size});

    try std.testing.expectEqual(@as(i64, 5), rg.num_rows);
    try std.testing.expectEqual(@as(usize, 3), rg.columns.len);

    // Check column chunks
    for (rg.columns, 0..) |col, i| {
        if (col.meta_data) |meta| {
            std.debug.print("\n  Column {}: {s}\n", .{ i, @tagName(meta.type_) });
            std.debug.print("    Values: {}\n", .{meta.num_values});
            std.debug.print("    Codec: {s}\n", .{@tagName(meta.codec)});
            std.debug.print("    Data offset: {}\n", .{meta.data_page_offset});
        }
    }
}

test "read column data with PLAIN encoding" {
    const allocator = std.testing.allocator;

    // Use simple_plain.parquet which has PLAIN encoding (no dictionary)
    const file = std.fs.cwd().openFile("tests/fixtures/simple_plain.parquet", .{}) catch {
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    var pf = try ParquetFile.init(allocator, data);
    defer pf.deinit();

    std.debug.print("\n=== Reading Column Data ===\n", .{});

    // Get row group
    const rg = pf.getRowGroup(0) orelse return error.SkipZigTest;

    // Read column 0 (id - INT64)
    {
        const col = rg.columns[0];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 0 (id): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        // Get column data
        const col_data = pf.getColumnData(0, 0) orelse return error.SkipZigTest;
        std.debug.print("  Data size: {} bytes\n", .{col_data.len});

        // Read pages
        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.int64_values) |values| {
            std.debug.print("  INT64 values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{}", .{v});
            }
            std.debug.print(" }}\n", .{});

            // Verify expected values: [1, 2, 3, 4, 5]
            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqual(@as(i64, 1), values[0]);
            try std.testing.expectEqual(@as(i64, 2), values[1]);
            try std.testing.expectEqual(@as(i64, 3), values[2]);
            try std.testing.expectEqual(@as(i64, 4), values[3]);
            try std.testing.expectEqual(@as(i64, 5), values[4]);
        }
    }

    // Read column 2 (value - DOUBLE)
    {
        const col = rg.columns[2];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 2 (value): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        const col_data = pf.getColumnData(0, 2) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.double_values) |values| {
            std.debug.print("  DOUBLE values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{d:.1}", .{v});
            }
            std.debug.print(" }}\n", .{});

            // Verify expected values: [1.1, 2.2, 3.3, 4.4, 5.5]
            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectApproxEqAbs(@as(f64, 1.1), values[0], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 2.2), values[1], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 3.3), values[2], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 4.4), values[3], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 5.5), values[4], 0.001);
        }
    }

    // Read column 1 (name - BYTE_ARRAY)
    {
        const col = rg.columns[1];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 1 (name): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        const col_data = pf.getColumnData(0, 1) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.binary_values) |values| {
            std.debug.print("  STRING values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("\"{s}\"", .{v});
            }
            std.debug.print(" }}\n", .{});

            // Verify expected values: ["alice", "bob", "charlie", "diana", "eve"]
            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqualStrings("alice", values[0]);
            try std.testing.expectEqualStrings("bob", values[1]);
            try std.testing.expectEqualStrings("charlie", values[2]);
            try std.testing.expectEqualStrings("diana", values[3]);
            try std.testing.expectEqualStrings("eve", values[4]);
        }
    }
}

test "read column data with DICTIONARY encoding" {
    const allocator = std.testing.allocator;

    // Use simple.parquet which has dictionary encoding (PyArrow default)
    const file = std.fs.cwd().openFile("tests/fixtures/simple.parquet", .{}) catch {
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    var pf = try ParquetFile.init(allocator, data);
    defer pf.deinit();

    std.debug.print("\n=== Reading Dictionary-Encoded Data ===\n", .{});

    const rg = pf.getRowGroup(0) orelse return error.SkipZigTest;

    // Read column 0 (id - INT64 with dictionary)
    {
        const col = rg.columns[0];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 0 (id): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        const col_data = pf.getColumnData(0, 0) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.int64_values) |values| {
            std.debug.print("  INT64 values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{}", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqual(@as(i64, 1), values[0]);
            try std.testing.expectEqual(@as(i64, 2), values[1]);
            try std.testing.expectEqual(@as(i64, 3), values[2]);
            try std.testing.expectEqual(@as(i64, 4), values[3]);
            try std.testing.expectEqual(@as(i64, 5), values[4]);
        } else {
            std.debug.print("  No INT64 values returned\n", .{});
            return error.SkipZigTest;
        }
    }

    // Read column 1 (name - BYTE_ARRAY with dictionary)
    {
        const col = rg.columns[1];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 1 (name): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        const col_data = pf.getColumnData(0, 1) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.binary_values) |values| {
            std.debug.print("  STRING values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("\"{s}\"", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqualStrings("alice", values[0]);
            try std.testing.expectEqualStrings("bob", values[1]);
            try std.testing.expectEqualStrings("charlie", values[2]);
            try std.testing.expectEqualStrings("diana", values[3]);
            try std.testing.expectEqualStrings("eve", values[4]);
        } else {
            std.debug.print("  No STRING values returned\n", .{});
            return error.SkipZigTest;
        }
    }

    // Read column 2 (value - DOUBLE with dictionary)
    {
        const col = rg.columns[2];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 2 (value): type={s}, values={}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
        });

        const col_data = pf.getColumnData(0, 2) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.double_values) |values| {
            std.debug.print("  DOUBLE values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{d:.1}", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectApproxEqAbs(@as(f64, 1.1), values[0], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 2.2), values[1], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 3.3), values[2], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 4.4), values[3], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 5.5), values[4], 0.001);
        } else {
            std.debug.print("  No DOUBLE values returned\n", .{});
            return error.SkipZigTest;
        }
    }
}

test "benchmark parquet reader" {
    // Use testing.allocator for CI compatibility
    const allocator = std.testing.allocator;

    // Use benchmark file (100K rows)
    const file = std.fs.cwd().openFile("tests/fixtures/benchmark_100k.parquet", .{}) catch {
        std.debug.print("\nSkipping benchmark - file not found\n", .{});
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    std.debug.print("\n=== Parquet Reader Benchmark ===\n", .{});
    std.debug.print("File size: {d:.1} KB\n", .{@as(f64, @floatFromInt(data.len)) / 1024});

    const warmup_iterations = 3;
    const bench_iterations = 10;

    // Warmup
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

    std.debug.print("Rows: {d}\n", .{avg_rows});
    std.debug.print("Min:  {d:.2} ms\n", .{min_ms});
    std.debug.print("Avg:  {d:.2} ms\n", .{avg_ms});
    std.debug.print("Max:  {d:.2} ms\n", .{max_ms});
    std.debug.print("Throughput: {d:.1}M rows/sec\n", .{throughput});
}

test "benchmark uncompressed parquet" {
    // Test without Snappy to isolate decompression overhead
    const allocator = std.testing.allocator;

    const file = std.fs.cwd().openFile("tests/fixtures/benchmark_100k_uncompressed.parquet", .{}) catch {
        std.debug.print("\nSkipping uncompressed benchmark - file not found\n", .{});
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    std.debug.print("\n=== Uncompressed Benchmark ===\n", .{});
    std.debug.print("File size: {d:.1} KB\n", .{@as(f64, @floatFromInt(data.len)) / 1024});

    const warmup_iterations = 3;
    const bench_iterations = 10;

    // Warm up
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
    var total_ns: u64 = 0;
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
        total_ns += timer.read();
        total_rows += rows_in_rg;
    }

    const avg_ns = total_ns / bench_iterations;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000;
    const avg_rows = total_rows / bench_iterations;
    const throughput = @as(f64, @floatFromInt(avg_rows)) / (avg_ms / 1000) / 1_000_000;

    std.debug.print("Rows: {d}\n", .{avg_rows});
    std.debug.print("Avg:  {d:.2} ms\n", .{avg_ms});
    std.debug.print("Throughput: {d:.1}M rows/sec (no Snappy, PLAIN encoding)\n", .{throughput});
}

test "read column data with SNAPPY compression" {
    const allocator = std.testing.allocator;

    // Use simple_snappy.parquet which has Snappy compression
    const file = std.fs.cwd().openFile("tests/fixtures/simple_snappy.parquet", .{}) catch {
        return error.SkipZigTest;
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.SkipZigTest;
    };
    defer allocator.free(data);

    var pf = try ParquetFile.init(allocator, data);
    defer pf.deinit();

    std.debug.print("\n=== Reading Snappy-Compressed Data ===\n", .{});

    const rg = pf.getRowGroup(0) orelse return error.SkipZigTest;

    // Verify codec is snappy
    {
        const col = rg.columns[0];
        const col_meta = col.meta_data orelse return error.SkipZigTest;
        std.debug.print("Codec: {s}\n", .{@tagName(col_meta.codec)});
        try std.testing.expectEqual(CompressionCodec.snappy, col_meta.codec);
    }

    // Read column 0 (id - INT64)
    {
        const col = rg.columns[0];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 0 (id): type={s}, values={}, codec={s}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
            @tagName(col_meta.codec),
        });

        const col_data = pf.getColumnData(0, 0) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.int64_values) |values| {
            std.debug.print("  INT64 values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{}", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqual(@as(i64, 1), values[0]);
            try std.testing.expectEqual(@as(i64, 2), values[1]);
            try std.testing.expectEqual(@as(i64, 3), values[2]);
            try std.testing.expectEqual(@as(i64, 4), values[3]);
            try std.testing.expectEqual(@as(i64, 5), values[4]);
        } else {
            std.debug.print("  No INT64 values returned\n", .{});
            return error.SkipZigTest;
        }
    }

    // Read column 1 (name - STRING)
    {
        const col = rg.columns[1];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 1 (name): type={s}, values={}, codec={s}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
            @tagName(col_meta.codec),
        });

        const col_data = pf.getColumnData(0, 1) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.binary_values) |values| {
            std.debug.print("  STRING values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("\"{s}\"", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectEqualStrings("alice", values[0]);
            try std.testing.expectEqualStrings("bob", values[1]);
            try std.testing.expectEqualStrings("charlie", values[2]);
            try std.testing.expectEqualStrings("diana", values[3]);
            try std.testing.expectEqualStrings("eve", values[4]);
        } else {
            std.debug.print("  No STRING values returned\n", .{});
            return error.SkipZigTest;
        }
    }

    // Read column 2 (value - DOUBLE)
    {
        const col = rg.columns[2];
        const col_meta = col.meta_data orelse return error.SkipZigTest;

        std.debug.print("\nColumn 2 (value): type={s}, values={}, codec={s}\n", .{
            @tagName(col_meta.type_),
            col_meta.num_values,
            @tagName(col_meta.codec),
        });

        const col_data = pf.getColumnData(0, 2) orelse return error.SkipZigTest;

        var reader = PageReader.init(
            col_data,
            col_meta.type_,
            null,
            col_meta.codec,
            allocator,
        );
        defer reader.deinit();

        var page = reader.readAll() catch |err| {
            std.debug.print("  Error reading pages: {}\n", .{err});
            return error.SkipZigTest;
        };
        defer page.deinit(allocator);

        std.debug.print("  Read {} values\n", .{page.num_values});

        if (page.double_values) |values| {
            std.debug.print("  DOUBLE values: {{ ", .{});
            for (values, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{d:.1}", .{v});
            }
            std.debug.print(" }}\n", .{});

            try std.testing.expectEqual(@as(usize, 5), values.len);
            try std.testing.expectApproxEqAbs(@as(f64, 1.1), values[0], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 2.2), values[1], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 3.3), values[2], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 4.4), values[3], 0.001);
            try std.testing.expectApproxEqAbs(@as(f64, 5.5), values[4], 0.001);
        } else {
            std.debug.print("  No DOUBLE values returned\n", .{});
            return error.SkipZigTest;
        }
    }
}
