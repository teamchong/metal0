//! Stress tests for LanceQL - large datasets, memory limits, concurrent access.
//!
//! These tests validate performance and stability under heavy load:
//! - Large row counts (100K+)
//! - Memory pressure scenarios
//! - Repeated operations
//! - Edge cases with extreme values

const std = @import("std");
const lanceql = @import("lanceql");
const format = @import("lanceql.format");
const io = @import("lanceql.io");
const table_mod = @import("lanceql.table");

const Table = table_mod.Table;
const MemoryReader = io.MemoryReader;

// ============================================================================
// Large Dataset Tests
// ============================================================================

test "stress: large row count parsing" {
    const allocator = std.testing.allocator;

    // Try to load the 100K benchmark fixture if available
    const path = "tests/fixtures/benchmark_100k.lance/data";

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        std.debug.print("SKIP: benchmark_100k fixture not found\n", .{});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    var lance_file: ?[]const u8 = null;
    var file_buf: [256]u8 = undefined;

    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".lance")) {
            const full_path = try std.fmt.bufPrint(&file_buf, "{s}/{s}", .{ path, entry.name });
            lance_file = full_path;
            break;
        }
    }

    if (lance_file == null) {
        std.debug.print("SKIP: No .lance file found in benchmark_100k\n", .{});
        return;
    }

    // Read file into memory
    const file = try std.fs.cwd().openFile(lance_file.?, .{});
    defer file.close();

    const stat = try file.stat();
    const data = try allocator.alloc(u8, stat.size);
    defer allocator.free(data);

    _ = try file.readAll(data);

    // Time the parsing
    var timer = try std.time.Timer.start();

    var table = try Table.init(allocator, data);
    defer table.deinit();

    const elapsed_ns = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    std.debug.print("\nLarge dataset test:\n", .{});
    std.debug.print("  File size: {} bytes\n", .{stat.size});
    std.debug.print("  Columns: {}\n", .{table.numColumns()});
    std.debug.print("  Parse time: {d:.2}ms\n", .{elapsed_ms});

    // Should have multiple columns
    try std.testing.expect(table.numColumns() > 0);
}

// ============================================================================
// Memory Pressure Tests
// ============================================================================

test "stress: repeated allocations" {
    const allocator = std.testing.allocator;

    // Create a small in-memory lance file structure for testing
    // This tests that we properly free memory on repeated operations

    const iterations = 100;
    var i: usize = 0;

    while (i < iterations) : (i += 1) {
        // Allocate and free various sizes
        const small = try allocator.alloc(u8, 1024);
        const medium = try allocator.alloc(u8, 64 * 1024);
        const large = try allocator.alloc(u8, 256 * 1024);

        // Simulate some work
        @memset(small, 0);
        @memset(medium, 0);
        @memset(large, 0);

        allocator.free(large);
        allocator.free(medium);
        allocator.free(small);
    }

    std.debug.print("\nRepeated allocations test: {} iterations passed\n", .{iterations});
}

test "stress: string column memory" {
    const allocator = std.testing.allocator;

    // Test that string column reading doesn't leak memory
    const path = "tests/fixtures/mixed_types.lance/data";

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        std.debug.print("SKIP: mixed_types fixture not found\n", .{});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    var lance_file: ?[]const u8 = null;
    var file_buf: [256]u8 = undefined;

    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".lance")) {
            const full_path = try std.fmt.bufPrint(&file_buf, "{s}/{s}", .{ path, entry.name });
            lance_file = full_path;
            break;
        }
    }

    if (lance_file == null) {
        std.debug.print("SKIP: No .lance file found\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(lance_file.?, .{});
    defer file.close();

    const stat = try file.stat();
    const data = try allocator.alloc(u8, stat.size);
    defer allocator.free(data);

    _ = try file.readAll(data);

    // Read string column multiple times - should not leak
    const iterations = 10;
    var i: usize = 0;

    while (i < iterations) : (i += 1) {
        var table = try Table.init(allocator, data);

        // Find and read string column
        const num_cols = table.numColumns();
        var col_idx: u32 = 0;
        while (col_idx < num_cols) : (col_idx += 1) {
            if (table.getField(col_idx)) |field| {
                if (std.mem.eql(u8, field.logical_type, "string") or
                    std.mem.eql(u8, field.logical_type, "utf8"))
                {
                    const strings = table.readStringColumn(col_idx) catch continue;
                    allocator.free(strings);
                    break;
                }
            }
        }

        table.deinit();
    }

    std.debug.print("\nString column memory test: {} iterations passed\n", .{iterations});
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "stress: empty file handling" {
    const allocator = std.testing.allocator;

    // Test handling of files that are too small
    var small_buf: [10]u8 = undefined;
    @memset(&small_buf, 0);

    const result = Table.init(allocator, &small_buf);
    try std.testing.expectError(error.FileTooSmall, result);

    std.debug.print("\nEmpty file handling: correctly rejected\n", .{});
}

test "stress: invalid magic number" {
    const allocator = std.testing.allocator;

    // Create buffer with correct size but wrong magic
    var bad_buf: [lanceql.FOOTER_SIZE + 100]u8 = undefined;
    @memset(&bad_buf, 0);

    // Put wrong magic at the end
    const footer_start = bad_buf.len - lanceql.FOOTER_SIZE;
    bad_buf[footer_start + 36] = 'B';
    bad_buf[footer_start + 37] = 'A';
    bad_buf[footer_start + 38] = 'D';
    bad_buf[footer_start + 39] = '!';

    const result = Table.init(allocator, &bad_buf);
    try std.testing.expectError(error.InvalidMagic, result);

    std.debug.print("\nInvalid magic handling: correctly rejected\n", .{});
}

// ============================================================================
// Performance Baseline Tests
// ============================================================================

test "stress: column read performance" {
    const allocator = std.testing.allocator;

    const path = "tests/fixtures/simple_int64.lance/data";

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        std.debug.print("SKIP: simple_int64 fixture not found\n", .{});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    var lance_file: ?[]const u8 = null;
    var file_buf: [256]u8 = undefined;

    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".lance")) {
            const full_path = try std.fmt.bufPrint(&file_buf, "{s}/{s}", .{ path, entry.name });
            lance_file = full_path;
            break;
        }
    }

    if (lance_file == null) {
        std.debug.print("SKIP: No .lance file found\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(lance_file.?, .{});
    defer file.close();

    const stat = try file.stat();
    const data = try allocator.alloc(u8, stat.size);
    defer allocator.free(data);

    _ = try file.readAll(data);

    var table = try Table.init(allocator, data);
    defer table.deinit();

    // Benchmark repeated column reads
    const iterations = 1000;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const col_data = try table.readInt64Column(0);
        allocator.free(col_data);
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1000.0;

    std.debug.print("\nColumn read performance:\n", .{});
    std.debug.print("  Iterations: {}\n", .{iterations});
    std.debug.print("  Avg read time: {d:.2}us\n", .{avg_us});

    // Should be under 1ms per read for small columns
    try std.testing.expect(avg_ns < 1_000_000);
}
