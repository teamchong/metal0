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
        \\  metal0 dev <file.py>        Run file in dev mode
        \\  metal0 dev watch            Watch current dir for .py changes
        \\  metal0 dev watch <file.py>  Watch single file
        \\  metal0 dev watch <dir>      Watch directory recursively
        \\
        \\{s}Dev mode features:{s}
        \\  - Auto-starts daemon for faster iterations
        \\  - Zero config - just run and edit
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

/// Watch file or directory and auto-recompile
fn cmdDevWatch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // If no arg, watch current directory for .py files
    const watch_path = if (args.len > 0) args[0] else ".";
    const is_dir = blk: {
        const stat = std.fs.cwd().statFile(watch_path) catch break :blk false;
        break :blk stat.kind == .directory;
    };

    // Auto-start daemon
    _ = daemon.ensureDaemon(allocator, 1);

    if (is_dir) {
        std.debug.print("{s}Watching {s}/**/*.py{s} for changes... (Ctrl+C to stop)\n", .{ Color.cyan, watch_path, Color.reset });
        try watchDirectory(allocator, watch_path);
    } else {
        std.debug.print("{s}Watching {s}{s} for changes... (Ctrl+C to stop)\n", .{ Color.cyan, watch_path, Color.reset });
        try watchFile(allocator, watch_path);
    }
}

/// Watch a single file
fn watchFile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var last_mtime: i128 = 0;

    while (true) {
        const stat = std.fs.cwd().statFile(file_path) catch {
            std.debug.print("{s}File not found: {s}{s}\n", .{ Color.red, file_path, Color.reset });
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };

        const mtime = stat.mtime;
        if (mtime != last_mtime and last_mtime != 0) {
            std.debug.print("\n{s}Change detected, recompiling...{s}\n", .{ Color.yellow, Color.reset });
            compile_mod.compileFile(allocator, .{
                .input_file = file_path,
                .mode = "run",
                .dev_mode = true,
            }) catch |err| {
                std.debug.print("{s}Compile error: {s}{s}\n", .{ Color.red, @errorName(err), Color.reset });
            };
        }
        last_mtime = mtime;
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
}

/// Watch directory for any .py file changes
fn watchDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var file_mtimes = std.StringHashMap(i128).init(allocator);
    defer file_mtimes.deinit();

    while (true) {
        // Scan for .py files
        var changed_file: ?[]const u8 = null;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };
        defer dir.close();

        var walker = dir.walk(allocator) catch {
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };
        defer walker.deinit();

        while (walker.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".py")) continue;

            const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.path }) catch continue;

            const stat = std.fs.cwd().statFile(full_path) catch continue;
            const mtime = stat.mtime;

            if (file_mtimes.get(full_path)) |old_mtime| {
                if (mtime != old_mtime) {
                    changed_file = full_path;
                    file_mtimes.put(full_path, mtime) catch {};
                    break;
                }
            } else {
                file_mtimes.put(full_path, mtime) catch {};
            }
        }

        if (changed_file) |path| {
            std.debug.print("\n{s}Change detected: {s}{s}\n", .{ Color.yellow, path, Color.reset });
            compile_mod.compileFile(allocator, .{
                .input_file = path,
                .mode = "run",
                .dev_mode = true,
            }) catch |err| {
                std.debug.print("{s}Compile error: {s}{s}\n", .{ Color.red, @errorName(err), Color.reset });
            };
        }

        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
}
