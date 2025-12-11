/// Dev mode: Hot reload for Python development
/// - Uses .so runtime (fast linking, no DCE)
/// - Debug build (fast compile)
/// - File watcher for auto-recompile
const std = @import("std");
const common = @import("common.zig");
const compile_mod = @import("../compile.zig");
const daemon = @import("daemon.zig");

const Color = common.Color;

/// Dev mode entry point
pub fn cmdDev(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printDevUsage();
        return;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "run")) {
        try cmdDevRun(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "watch")) {
        try cmdDevWatch(allocator, args[1..]);
    } else if (std.mem.endsWith(u8, subcmd, ".py")) {
        // metal0 dev myfile.py -> run in dev mode
        try cmdDevRun(allocator, args);
    } else {
        std.debug.print("{s}Unknown dev command: {s}{s}\n", .{ Color.red, subcmd, Color.reset });
        printDevUsage();
    }
}

fn printDevUsage() void {
    std.debug.print(
        \\{s}metal0 dev{s} - Development mode with hot reload
        \\
        \\{s}Usage:{s}
        \\  metal0 dev <file.py>        Run file in dev mode (fast compile)
        \\  metal0 dev watch <file.py>  Watch and auto-recompile on changes
        \\
        \\{s}Dev mode features:{s}
        \\  - Builds runtime .so automatically on first run
        \\  - Debug build (faster compile, larger binary)
        \\  - Auto-starts daemon for even faster iterations
        \\
    , .{ Color.bold, Color.reset, Color.cyan, Color.reset, Color.cyan, Color.reset });
}

/// Run file in dev mode
fn cmdDevRun(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("{s}Error: No file specified{s}\n", .{ Color.red, Color.reset });
        return;
    }

    const file_path = args[0];

    // Auto-start daemon for faster subsequent runs
    _ = daemon.ensureDaemon(allocator, 1);

    // Compile and run in dev mode
    try compile_mod.compileFile(allocator, .{
        .input_file = file_path,
        .mode = "run",
        .dev_mode = true, // Debug build + .so runtime
    });
}

/// Watch file and auto-recompile
fn cmdDevWatch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("{s}Error: No file specified{s}\n", .{ Color.red, Color.reset });
        return;
    }

    const file_path = args[0];

    // Auto-start daemon
    _ = daemon.ensureDaemon(allocator, 1);

    std.debug.print("{s}Watching {s}{s} for changes... (Ctrl+C to stop)\n", .{ Color.cyan, file_path, Color.reset });

    var last_mtime: i128 = 0;

    while (true) {
        // Check file modification time
        const stat = std.fs.cwd().statFile(file_path) catch {
            std.debug.print("{s}File not found: {s}{s}\n", .{ Color.red, file_path, Color.reset });
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };

        const mtime = stat.mtime;
        if (mtime != last_mtime and last_mtime != 0) {
            std.debug.print("\n{s}Change detected, recompiling...{s}\n", .{ Color.yellow, Color.reset });

            // Recompile and run in dev mode
            compile_mod.compileFile(allocator, .{
                .input_file = file_path,
                .mode = "run",
                .dev_mode = true,
            }) catch |err| {
                std.debug.print("{s}Compile error: {s}{s}\n", .{ Color.red, @errorName(err), Color.reset });
            };
        }
        last_mtime = mtime;

        // Poll every 500ms
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
}
