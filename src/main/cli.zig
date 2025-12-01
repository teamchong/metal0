/// CLI argument parsing and main entry point
/// Drop-in replacement for python3 AND pip3 with compile superpowers
const std = @import("std");
const c_interop = @import("c_interop");
const CompileOptions = @import("../main.zig").CompileOptions;
const utils = @import("utils.zig");
const compile = @import("compile.zig");
const pkg = @import("pkg");

// ANSI color codes for terminal UX
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const cyan = "\x1b[36m";
    const bold_cyan = "\x1b[1;36m";
    const bold_green = "\x1b[1;32m";
    const bold_yellow = "\x1b[1;33m";
    const bold_red = "\x1b[1;31m";
};

fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}✓{s} ", .{ Color.bold_green, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

fn printError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}✗{s} ", .{ Color.bold_red, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

fn printInfo(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}→{s} ", .{ Color.bold_cyan, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

fn printWarn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}!{s} ", .{ Color.bold_yellow, Color.reset });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try c_interop.initGlobalRegistry(allocator);
    defer c_interop.deinitGlobalRegistry(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    // Python-compatible flags (drop-in replacement for python3)
    if (std.mem.eql(u8, command, "-c")) {
        try cmdExecCode(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "-m")) {
        try cmdRunModule(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "-")) {
        try cmdReadStdin(allocator);
    } else if (std.mem.eql(u8, command, "-V") or std.mem.eql(u8, command, "--version")) {
        cmdVersion();
    } else if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help")) {
        try printUsage();
    } else if (std.mem.eql(u8, command, "-u")) {
        // Unbuffered output - skip flag, run next arg as file
        if (args.len > 2) {
            try cmdRunFile(allocator, args[2..]);
        }
    } else if (std.mem.eql(u8, command, "-O") or std.mem.eql(u8, command, "-OO")) {
        // Optimize - we always optimize, skip flag
        if (args.len > 2) {
            try cmdRunFile(allocator, args[2..]);
        }
    }
    // pip-compatible commands
    else if (std.mem.eql(u8, command, "install")) {
        try cmdInstall(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "uninstall") or std.mem.eql(u8, command, "remove")) {
        cmdUninstall(args[2..]);
    } else if (std.mem.eql(u8, command, "freeze")) {
        cmdFreeze();
    } else if (std.mem.eql(u8, command, "list")) {
        cmdList(args[2..]);
    } else if (std.mem.eql(u8, command, "show")) {
        try cmdShow(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "cache")) {
        try cmdCache(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build")) {
        try cmdBuild(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "run")) {
        try cmdRun(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "test")) {
        try cmdTest(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        cmdVersion();
    } else if (std.mem.eql(u8, command, "help")) {
        try printUsage();
    } else if (std.mem.endsWith(u8, command, ".py") or std.mem.endsWith(u8, command, ".ipynb")) {
        try cmdRunFile(allocator, args[1..]);
    } else {
        printError("Unknown command: {s}", .{command});
        std.debug.print("\nRun {s}metal0 --help{s} for usage.\n", .{ Color.bold, Color.reset });
    }
}

fn cmdInstall(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No packages specified", .{});
        std.debug.print("\nUsage: metal0 install <package> [package...] [options]\n", .{});
        return;
    }

    var packages = std.ArrayList([]const u8){};
    defer packages.deinit(allocator);

    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "-")) {
            try packages.append(allocator, arg);
        }
    }

    if (packages.items.len == 0) {
        printError("No packages to install", .{});
        return;
    }

    const start_time = std.time.nanoTimestamp();
    std.debug.print("\n{s}Resolving dependencies...{s}\n", .{ Color.dim, Color.reset });

    var client = pkg.pypi.PyPIClient.init(allocator);
    defer client.deinit();

    const home = std.posix.getenv("HOME") orelse "/tmp";
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.metal0/cache", .{home});
    defer allocator.free(cache_dir);

    var disk_cache: ?pkg.cache.Cache = pkg.cache.Cache.init(allocator, .{
        .memory_size = 64 * 1024 * 1024,
        .memory_ttl = 300,
        .disk_dir = cache_dir,
        .disk_ttl = 86400,
    }) catch null;
    defer if (disk_cache) |*c| c.deinit();

    var resolver = pkg.resolver.Resolver.init(allocator, &client, if (disk_cache) |*c| c else null);
    defer resolver.deinit();

    var deps = std.ArrayList(pkg.pep508.Dependency){};
    defer {
        for (deps.items) |*d| pkg.pep508.freeDependency(allocator, d);
        deps.deinit(allocator);
    }

    for (packages.items) |pkg_name| {
        const dep = pkg.pep508.parseDependency(allocator, pkg_name) catch {
            printError("Invalid package spec: {s}", .{pkg_name});
            continue;
        };
        try deps.append(allocator, dep);
    }

    var resolution = resolver.resolve(deps.items) catch |err| {
        printError("Resolution failed: {any}", .{err});
        return;
    };
    defer resolution.deinit();

    const elapsed = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000_000.0;

    std.debug.print("\n", .{});
    printSuccess("Resolved {s}{d}{s} packages in {s}{d:.2}s{s}", .{
        Color.bold,
        resolution.packages.len,
        Color.reset,
        Color.dim,
        elapsed,
        Color.reset,
    });

    std.debug.print("\n{s}Packages to install:{s}\n", .{ Color.bold, Color.reset });
    for (resolution.packages) |p| {
        var version_buf: [128]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&version_buf);
        p.version.format(fbs.writer()) catch {};
        const version_str = fbs.getWritten();

        std.debug.print("   {s}{s}{s} {s}=={s}{s}\n", .{
            Color.green,
            p.name,
            Color.reset,
            Color.dim,
            version_str,
            Color.reset,
        });
    }

    std.debug.print("\n{s}(Download and install coming soon){s}\n", .{ Color.dim, Color.reset });
}

fn cmdUninstall(args: []const []const u8) void {
    if (args.len == 0) {
        printError("No packages specified", .{});
        return;
    }
    for (args) |pkg_name| {
        if (!std.mem.startsWith(u8, pkg_name, "-")) {
            printWarn("Uninstall not yet implemented: {s}", .{pkg_name});
        }
    }
}

fn cmdFreeze() void {
    std.debug.print("# Installed packages (pip freeze format)\n", .{});
    printWarn("Freeze not yet implemented", .{});
}

fn cmdList(args: []const []const u8) void {
    _ = args;
    std.debug.print("{s}Package       Version{s}\n", .{ Color.bold, Color.reset });
    std.debug.print("{s}------------ --------{s}\n", .{ Color.dim, Color.reset });
    printWarn("List not yet implemented", .{});
}

fn cmdShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No package specified", .{});
        return;
    }

    const pkg_name = args[0];
    printInfo("Fetching info for {s}{s}{s}", .{ Color.bold, pkg_name, Color.reset });

    var client = pkg.pypi.PyPIClient.init(allocator);
    defer client.deinit();

    var metadata = client.getPackageMetadata(pkg_name) catch |err| {
        printError("Cannot fetch package info: {any}", .{err});
        return;
    };
    defer metadata.deinit(allocator);

    std.debug.print("\n{s}Name:{s} {s}\n", .{ Color.bold, Color.reset, metadata.name });
    std.debug.print("{s}Version:{s} {s}\n", .{ Color.bold, Color.reset, metadata.latest_version });
    if (metadata.summary) |sum| {
        std.debug.print("{s}Summary:{s} {s}\n", .{ Color.bold, Color.reset, sum });
    }
}

fn cmdCache(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("\nUsage: metal0 cache <command>\n", .{});
        std.debug.print("\nCommands: dir, info, purge\n", .{});
        return;
    }

    const subcmd = args[0];
    if (std.mem.eql(u8, subcmd, "dir")) {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        std.debug.print("{s}/.metal0/cache\n", .{home});
    } else if (std.mem.eql(u8, subcmd, "purge")) {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const cache_path = try std.fmt.allocPrint(allocator, "{s}/.metal0/cache", .{home});
        defer allocator.free(cache_path);

        std.fs.cwd().deleteTree(cache_path) catch |err| {
            if (err != error.FileNotFound) {
                printError("Cannot purge cache: {any}", .{err});
                return;
            }
        };
        printSuccess("Cache purged", .{});
    } else {
        printWarn("Unknown cache command: {s}", .{subcmd});
    }
}

fn cmdBuild(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = CompileOptions{ .input_file = undefined, .mode = "build" };
    var input_file: ?[]const u8 = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            if (input_file == null) input_file = arg;
        }
    }

    if (input_file == null) {
        try utils.buildDirectory(allocator, ".", opts);
        return;
    }

    opts.input_file = input_file.?;
    try compile.compileFile(allocator, opts);
}

fn cmdRun(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No file specified", .{});
        return;
    }
    try cmdRunFile(allocator, args);
}

fn cmdRunFile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = CompileOptions{ .input_file = args[0], .mode = "run" };

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        }
    }

    try compile.compileFile(allocator, opts);
}

fn cmdTest(allocator: std.mem.Allocator) !void {
    printInfo("Running tests...", .{});
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "pytest", "-v" },
    });
}

// Python-compatible commands (drop-in replacement for python3)

fn cmdExecCode(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No code to execute", .{});
        std.debug.print("\nUsage: metal0 -c \"print('hello')\"\n", .{});
        return;
    }

    const code = args[0];

    // Write code to temp file
    const tmp_path = "/tmp/metal0_exec.py";
    const file = try std.fs.cwd().createFile(tmp_path, .{});
    defer file.close();
    try file.writeAll(code);

    // Compile and run
    const opts = CompileOptions{ .input_file = tmp_path, .mode = "run", .force = true };
    try compile.compileFile(allocator, opts);
}

fn cmdRunModule(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No module specified", .{});
        std.debug.print("\nUsage: metal0 -m module_name\n", .{});
        return;
    }

    const module_name = args[0];

    // Common Python modules we can handle
    if (std.mem.eql(u8, module_name, "pip")) {
        // Redirect to our pip-compatible install
        if (args.len > 1) {
            if (std.mem.eql(u8, args[1], "install")) {
                try cmdInstall(allocator, args[2..]);
                return;
            } else if (std.mem.eql(u8, args[1], "list")) {
                cmdList(args[2..]);
                return;
            } else if (std.mem.eql(u8, args[1], "show")) {
                try cmdShow(allocator, args[2..]);
                return;
            }
        }
        try printUsage();
        return;
    }

    // Try to find module as a file
    const module_path = try std.fmt.allocPrint(allocator, "{s}.py", .{module_name});
    defer allocator.free(module_path);

    if (std.fs.cwd().access(module_path, .{})) |_| {
        const opts = CompileOptions{ .input_file = module_path, .mode = "run" };
        try compile.compileFile(allocator, opts);
    } else |_| {
        // Try as package/__main__.py
        const pkg_path = try std.fmt.allocPrint(allocator, "{s}/__main__.py", .{module_name});
        defer allocator.free(pkg_path);

        if (std.fs.cwd().access(pkg_path, .{})) |_| {
            const opts = CompileOptions{ .input_file = pkg_path, .mode = "run" };
            try compile.compileFile(allocator, opts);
        } else |_| {
            printError("No module named '{s}'", .{module_name});
        }
    }
}

fn cmdReadStdin(allocator: std.mem.Allocator) !void {
    // Read Python code from stdin (file handle 0)
    const stdin_file = std.fs.File{ .handle = 0 };
    const code = try stdin_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(code);

    // Write to temp file
    const tmp_path = "/tmp/metal0_stdin.py";
    const file = try std.fs.cwd().createFile(tmp_path, .{});
    defer file.close();
    try file.writeAll(code);

    // Compile and run
    const opts = CompileOptions{ .input_file = tmp_path, .mode = "run", .force = true };
    try compile.compileFile(allocator, opts);
}

fn cmdVersion() void {
    std.debug.print("{s}metal0{s} 0.1.0\n", .{ Color.bold_cyan, Color.reset });
    std.debug.print("{s}30x faster than CPython{s}\n", .{ Color.dim, Color.reset });
}

fn printUsage() !void {
    std.debug.print(
        \\{s}metal0{s} - AOT Python compiler (30x faster than CPython)
        \\
        \\{s}USAGE (python3-compatible):{s}
        \\   metal0 <file.py>              # Compile and run
        \\   metal0 -c "code"              # Execute code string
        \\   metal0 -m module              # Run module as script
        \\   metal0 -                      # Read from stdin
        \\
        \\{s}PACKAGE COMMANDS (pip-compatible):{s}
        \\   install      Install packages from PyPI
        \\   uninstall    Uninstall packages
        \\   freeze       Output installed packages
        \\   list         List installed packages
        \\   show         Show package info
        \\   cache        Manage cache (dir, info, purge)
        \\
        \\{s}BUILD COMMANDS:{s}
        \\   build        Compile Python to native code
        \\   run          Compile and run a Python file
        \\   test         Run test suite
        \\
        \\{s}EXAMPLES:{s}
        \\   metal0 app.py                 # Run Python file (30x faster)
        \\   metal0 -c "print('hi')"       # Execute code string
        \\   metal0 -m pip install numpy   # Use pip through metal0
        \\   metal0 install requests       # Install packages
        \\   metal0 build -b app.py        # Compile to binary
        \\
    , .{
        Color.bold_cyan, Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
    });
}
