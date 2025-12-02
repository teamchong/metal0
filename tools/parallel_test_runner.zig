//! Parallel Test Runner - runs CPython tests concurrently using process polling
//!
//! Uses the same async pattern as the state machine async: spawn processes,
//! poll for completion, collect results. This avoids threads and uses the
//! OS's process management for true parallelism.
//!
//! Usage: zig run tools/parallel_test_runner.zig -- [num_workers] [timeout_secs]

const std = @import("std");
const builtin = @import("builtin");

const TestResult = struct {
    file: []const u8,
    passed: bool,
    duration_ms: u64,
};

const TestProcess = struct {
    file: []const u8,
    process: std.process.Child,
    start_time: i64,
    state: enum { running, done },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const num_workers: usize = if (args.len > 1) std.fmt.parseInt(usize, args[1], 10) catch 8 else 8;
    const timeout_ms: u64 = if (args.len > 2) (std.fmt.parseInt(u64, args[2], 10) catch 15) * 1000 else 15000;

    std.debug.print("Parallel Test Runner: {d} workers, {d}ms timeout\n", .{ num_workers, timeout_ms });

    // Find all test files
    var test_files = std.ArrayList([]const u8){};
    defer test_files.deinit(allocator);

    var dir = std.fs.cwd().openDir("tests/cpython", .{ .iterate = true }) catch {
        std.debug.print("Error: Could not open tests/cpython directory\n", .{});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const name = entry.name;
            if (std.mem.startsWith(u8, name, "test_") and std.mem.endsWith(u8, name, ".py")) {
                const path = try std.fmt.allocPrint(allocator, "tests/cpython/{s}", .{name});
                try test_files.append(allocator, path);
            }
        }
    }

    // Sort for consistent ordering
    std.mem.sort([]const u8, test_files.items, {}, struct {
        fn cmp(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.cmp);

    std.debug.print("Found {d} test files\n", .{test_files.items.len});

    // Results
    var passed: usize = 0;
    var failed: usize = 0;
    var failed_files = std.ArrayList([]const u8){};
    defer failed_files.deinit(allocator);

    // Active processes
    var active = std.ArrayList(TestProcess){};
    defer active.deinit(allocator);

    var file_idx: usize = 0;
    const start_time = std.time.milliTimestamp();

    // Main poll loop - state machine style
    while (file_idx < test_files.items.len or active.items.len > 0) {
        // Spawn new processes up to worker limit
        while (active.items.len < num_workers and file_idx < test_files.items.len) {
            const file = test_files.items[file_idx];
            file_idx += 1;

            const argv = [_][]const u8{ "./zig-out/bin/metal0", file, "--force" };
            var child = std.process.Child.init(&argv, allocator);
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;

            if (child.spawn()) {
                try active.append(allocator, .{
                    .file = file,
                    .process = child,
                    .start_time = std.time.milliTimestamp(),
                    .state = .running,
                });
            } else |_| {
                failed += 1;
                try failed_files.append(allocator, file);
            }
        }

        // Poll active processes (non-blocking)
        var i: usize = 0;
        while (i < active.items.len) {
            var proc = &active.items[i];
            const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - proc.start_time));

            // Check if done or timeout
            const result = proc.process.wait() catch null;
            if (result) |term| {
                // Process completed
                if (term.Exited == 0) {
                    passed += 1;
                    std.debug.print("✓ {s} ({d}ms)\n", .{ proc.file, elapsed });
                } else {
                    failed += 1;
                    try failed_files.append(allocator, proc.file);
                    std.debug.print("✗ {s}\n", .{proc.file});
                }
                _ = active.swapRemove(i);
            } else if (elapsed > timeout_ms) {
                // Timeout - kill process
                _ = proc.process.kill() catch {};
                failed += 1;
                try failed_files.append(allocator, proc.file);
                std.debug.print("⏱ {s} (timeout)\n", .{proc.file});
                _ = active.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Brief yield to avoid busy waiting
        std.time.sleep(1_000_000); // 1ms
    }

    const total_time = std.time.milliTimestamp() - start_time;

    // Print summary
    std.debug.print("\n{'='**60}\n", .{});
    std.debug.print("Results: {d} passed, {d} failed ({d} total)\n", .{ passed, failed, passed + failed });
    std.debug.print("Time: {d}ms ({d:.1}s)\n", .{ total_time, @as(f64, @floatFromInt(total_time)) / 1000.0 });
    std.debug.print("Pass rate: {d:.1}%\n", .{ @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(passed + failed)) * 100.0 });

    if (failed_files.items.len > 0 and failed_files.items.len <= 20) {
        std.debug.print("\nFailed tests:\n", .{});
        for (failed_files.items) |f| {
            std.debug.print("  - {s}\n", .{f});
        }
    }
}
