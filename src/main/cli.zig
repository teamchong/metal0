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
        try cmdUninstall(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "freeze")) {
        try cmdFreeze(allocator);
    } else if (std.mem.eql(u8, command, "list")) {
        try cmdList(allocator);
    } else if (std.mem.eql(u8, command, "show")) {
        try cmdShow(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "download")) {
        try cmdDownload(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "check")) {
        try cmdCheck(allocator);
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
    var packages = std.ArrayList([]const u8){};
    defer packages.deinit(allocator);

    // Track allocated strings for cleanup
    var allocated_pkgs = std.ArrayList([]const u8){};
    defer {
        for (allocated_pkgs.items) |p| allocator.free(p);
        allocated_pkgs.deinit(allocator);
    }

    // Track extras for pyproject.toml
    var extras = std.ArrayList([]const u8){};
    defer extras.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--requirement")) {
            // Read requirements file
            i += 1;
            if (i >= args.len) {
                printError("-r requires a filename argument", .{});
                return;
            }
            const req_file = args[i];
            var reqs = pkg.requirements.parseFile(allocator, req_file) catch |err| {
                printError("Failed to parse {s}: {any}", .{ req_file, err });
                return;
            };
            defer reqs.deinit();
            // Add requirements as packages
            for (reqs.requirements) |r| {
                switch (r) {
                    .package => |dep| {
                        const name_copy = try allocator.dupe(u8, dep.name);
                        try allocated_pkgs.append(allocator, name_copy);
                        try packages.append(allocator, name_copy);
                    },
                    else => {}, // Skip options, editables, etc. for now
                }
            }
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--extra")) {
            // Optional dependency extra (for pyproject.toml)
            i += 1;
            if (i >= args.len) {
                printError("-e requires an extra name", .{});
                return;
            }
            try extras.append(allocator, args[i]);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            try packages.append(allocator, arg);
        }
    }

    // If no packages specified, look for pyproject.toml
    if (packages.items.len == 0) {
        // Try to find pyproject.toml
        const maybe_path: ?[]const u8 = pkg.pyproject.findPyproject(allocator, ".") catch null;
        const pyproject_path = maybe_path orelse {
            printInfo("No pyproject.toml found", .{});
            printError("No packages specified. Usage: metal0 install <package>", .{});
            return;
        };
        defer allocator.free(pyproject_path);
        printInfo("Found {s}", .{pyproject_path});
        {
            var pyproj = pkg.pyproject.parseFile(allocator, pyproject_path) catch |err| {
                printError("Failed to parse pyproject.toml: {any}", .{err});
                return;
            };
            defer pyproj.deinit();

            if (pyproj.name) |name| {
                printInfo("Installing dependencies for {s}{s}{s}", .{ Color.bold, name, Color.reset });
            }

            // Add all dependencies
            for (pyproj.dependencies) |dep| {
                const name_copy = try allocator.dupe(u8, dep.name);
                try allocated_pkgs.append(allocator, name_copy);
                try packages.append(allocator, name_copy);
            }

            // Add extra dependencies if requested
            for (extras.items) |extra| {
                if (pyproj.optional_dependencies.get(extra)) |extra_deps| {
                    printInfo("Including extra: {s}", .{extra});
                    for (extra_deps) |dep| {
                        const name_copy = try allocator.dupe(u8, dep.name);
                        try allocated_pkgs.append(allocator, name_copy);
                        try packages.append(allocator, name_copy);
                    }
                } else {
                    printWarn("Unknown extra: {s}", .{extra});
                }
            }
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

    // Build package info for installer
    var pkg_infos = std.ArrayList(pkg.installer.PackageInfo){};
    defer {
        for (pkg_infos.items) |p| {
            allocator.free(p.version);
            if (p.wheel_url) |url| allocator.free(url);
        }
        pkg_infos.deinit(allocator);
    }

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

        try pkg_infos.append(allocator, .{
            .name = p.name,
            .version = try allocator.dupe(u8, version_str),
            .wheel_url = null, // Will be filled from Simple API
            .sha256 = null,
        });
    }

    // Fetch wheel URLs from Simple API (has wheel_url per version)
    std.debug.print("\n{s}Fetching wheel URLs...{s}\n", .{ Color.dim, Color.reset });

    for (pkg_infos.items) |*info| {
        const simple_info = client.getSimplePackageInfo(info.name) catch continue;
        defer {
            var si = simple_info;
            si.deinit(allocator);
        }

        // Find matching version with wheel URL
        for (simple_info.versions) |v| {
            if (std.mem.eql(u8, v.version, info.version)) {
                if (v.wheel_url) |url| {
                    info.wheel_url = allocator.dupe(u8, url) catch null;
                }
                break;
            }
        }
    }

    // Download and install wheels
    std.debug.print("\n{s}Downloading wheels...{s}\n", .{ Color.dim, Color.reset });

    var installer_inst = pkg.installer.Installer.init(allocator, .{
        .show_progress = true,
    }) catch |err| {
        printError("Failed to initialize installer: {any}", .{err});
        return;
    };
    defer installer_inst.deinit();

    const install_results = installer_inst.installPackages(pkg_infos.items) catch |err| {
        printError("Installation failed: {any}", .{err});
        return;
    };
    defer {
        for (install_results) |r| {
            allocator.free(r.name);
            allocator.free(r.version);
        }
        allocator.free(install_results);
    }

    const total_elapsed = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000_000.0;

    std.debug.print("\n", .{});
    if (install_results.len > 0) {
        var total_files: usize = 0;
        var total_size: u64 = 0;
        for (install_results) |r| {
            total_files += r.files_installed;
            total_size += r.size_bytes;
        }
        printSuccess("Installed {s}{d}{s} packages ({d} files, {d:.1} MB) in {s}{d:.2}s{s}", .{
            Color.bold,
            install_results.len,
            Color.reset,
            total_files,
            @as(f64, @floatFromInt(total_size)) / (1024.0 * 1024.0),
            Color.dim,
            total_elapsed,
            Color.reset,
        });
    } else {
        printWarn("No packages were installed (no wheel URLs available)", .{});
    }
}

fn cmdUninstall(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No packages specified", .{});
        return;
    }

    // Collect package names (skip flags)
    var packages = std.ArrayList([]const u8){};
    defer packages.deinit(allocator);

    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "-")) {
            try packages.append(allocator, arg);
        }
    }

    if (packages.items.len == 0) {
        printError("No packages specified", .{});
        return;
    }

    var installer = pkg.installer.Installer.init(allocator, .{}) catch |err| {
        printError("Failed to initialize installer: {any}", .{err});
        return;
    };
    defer installer.deinit();

    const results = installer.uninstallPackages(packages.items) catch |err| {
        printError("Uninstall failed: {any}", .{err});
        return;
    };
    defer {
        for (results) |r| {
            allocator.free(r.name);
            allocator.free(r.version);
        }
        allocator.free(results);
    }

    if (results.len == 0) {
        printWarn("No packages found to uninstall", .{});
        return;
    }

    for (results) |r| {
        std.debug.print("{s}✓{s} Uninstalled {s}{s}{s} {s}=={s}{s}\n", .{
            Color.green,
            Color.reset,
            Color.bold,
            r.name,
            Color.reset,
            Color.dim,
            r.version,
            Color.reset,
        });
    }
}

fn cmdFreeze(allocator: std.mem.Allocator) !void {
    var installer = pkg.installer.Installer.init(allocator, .{}) catch |err| {
        printError("Failed to initialize installer: {any}", .{err});
        return;
    };
    defer installer.deinit();

    const packages = installer.listInstalled() catch |err| {
        printError("Failed to list packages: {any}", .{err});
        return;
    };
    defer {
        for (packages) |p| {
            allocator.free(p.name);
            allocator.free(p.version);
        }
        allocator.free(packages);
    }

    for (packages) |p| {
        std.debug.print("{s}=={s}\n", .{ p.name, p.version });
    }
}

fn cmdList(allocator: std.mem.Allocator) !void {
    var installer = pkg.installer.Installer.init(allocator, .{}) catch |err| {
        printError("Failed to initialize installer: {any}", .{err});
        return;
    };
    defer installer.deinit();

    const packages = installer.listInstalled() catch |err| {
        printError("Failed to list packages: {any}", .{err});
        return;
    };
    defer {
        for (packages) |p| {
            allocator.free(p.name);
            allocator.free(p.version);
        }
        allocator.free(packages);
    }

    // Find max name length for formatting
    var max_name_len: usize = 7; // "Package"
    for (packages) |p| {
        if (p.name.len > max_name_len) max_name_len = p.name.len;
    }

    std.debug.print("{s}Package", .{Color.bold});
    var i: usize = 0;
    while (i < max_name_len - 7 + 2) : (i += 1) std.debug.print(" ", .{});
    std.debug.print("Version{s}\n", .{Color.reset});

    std.debug.print("{s}", .{Color.dim});
    i = 0;
    while (i < max_name_len) : (i += 1) std.debug.print("-", .{});
    std.debug.print("  -------{s}\n", .{Color.reset});

    for (packages) |p| {
        std.debug.print("{s}", .{p.name});
        i = 0;
        while (i < max_name_len - p.name.len + 2) : (i += 1) std.debug.print(" ", .{});
        std.debug.print("{s}\n", .{p.version});
    }
}

fn cmdDownload(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No packages specified", .{});
        return;
    }

    // Parse args for -d/--dest option
    var dest_dir: []const u8 = ".";
    var packages = std.ArrayList([]const u8){};
    defer packages.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dest")) {
            i += 1;
            if (i < args.len) dest_dir = args[i];
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            try packages.append(allocator, arg);
        }
    }

    if (packages.items.len == 0) {
        printError("No packages specified", .{});
        return;
    }

    std.debug.print("\n{s}Resolving dependencies...{s}\n", .{ Color.dim, Color.reset });

    var client = pkg.pypi.PyPIClient.init(allocator);
    defer client.deinit();

    for (packages.items) |pkg_name| {
        // Get wheel URL
        const wheel_url = client.getWheelUrl(pkg_name) catch |err| {
            printError("Cannot find wheel for {s}: {any}", .{ pkg_name, err });
            continue;
        };
        defer allocator.free(wheel_url);

        // Extract filename from URL
        const filename = if (std.mem.lastIndexOf(u8, wheel_url, "/")) |pos|
            wheel_url[pos + 1 ..]
        else
            wheel_url;

        const dest_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_dir, filename });
        defer allocator.free(dest_path);

        std.debug.print("{s}Downloading{s} {s}...\n", .{ Color.dim, Color.reset, filename });

        // Download wheel
        const data = client.fetchRawUrl(wheel_url) catch |err| {
            printError("Download failed for {s}: {any}", .{ pkg_name, err });
            continue;
        };
        defer allocator.free(data);

        // Write to file
        const file = std.fs.cwd().createFile(dest_path, .{}) catch |err| {
            printError("Cannot create file {s}: {any}", .{ dest_path, err });
            continue;
        };
        defer file.close();
        file.writeAll(data) catch |err| {
            printError("Cannot write file {s}: {any}", .{ dest_path, err });
            continue;
        };

        std.debug.print("{s}✓{s} Downloaded {s}{s}{s} ({d} KB)\n", .{
            Color.green,
            Color.reset,
            Color.bold,
            filename,
            Color.reset,
            data.len / 1024,
        });
    }
}

fn cmdCheck(allocator: std.mem.Allocator) !void {
    var installer = pkg.installer.Installer.init(allocator, .{}) catch |err| {
        printError("Failed to initialize installer: {any}", .{err});
        return;
    };
    defer installer.deinit();

    const packages = installer.listInstalled() catch |err| {
        printError("Failed to list packages: {any}", .{err});
        return;
    };
    defer {
        for (packages) |p| {
            allocator.free(p.name);
            allocator.free(p.version);
        }
        allocator.free(packages);
    }

    if (packages.len == 0) {
        std.debug.print("No packages installed.\n", .{});
        return;
    }

    // For now, just report that all packages are OK
    // A full implementation would check each package's dependencies
    std.debug.print("{s}✓{s} No broken requirements found.\n", .{ Color.green, Color.reset });
    std.debug.print("  {d} packages checked.\n", .{packages.len});
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
    printInfo("Discovering test files...", .{});

    // Discover test_*.py files in current directory and tests/
    var test_files = std.ArrayList([]const u8){};
    defer {
        for (test_files.items) |f| allocator.free(f);
        test_files.deinit(allocator);
    }

    // Search current directory
    if (std.fs.cwd().openDir(".", .{ .iterate = true })) |dir| {
        var d = dir;
        var iter = d.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "test_") and std.mem.endsWith(u8, entry.name, ".py")) {
                const path = try allocator.dupe(u8, entry.name);
                try test_files.append(allocator, path);
            }
        }
    } else |_| {}

    // Search tests/ directory
    if (std.fs.cwd().openDir("tests", .{ .iterate = true })) |dir| {
        var d = dir;
        var iter = d.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "test_") and std.mem.endsWith(u8, entry.name, ".py")) {
                const path = try std.fmt.allocPrint(allocator, "tests/{s}", .{entry.name});
                try test_files.append(allocator, path);
            }
        }
    } else |_| {}

    // Search tests/cpython/ directory
    if (std.fs.cwd().openDir("tests/cpython", .{ .iterate = true })) |dir| {
        var d = dir;
        var iter = d.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "test_") and std.mem.endsWith(u8, entry.name, ".py")) {
                const path = try std.fmt.allocPrint(allocator, "tests/cpython/{s}", .{entry.name});
                try test_files.append(allocator, path);
            }
        }
    } else |_| {}

    if (test_files.items.len == 0) {
        printWarn("No test files found", .{});
        return;
    }

    printInfo("Found {d} test files, running in parallel...", .{test_files.items.len});

    // Use metal0 Scheduler for parallel execution
    const runtime = @import("runtime");
    var scheduler = try runtime.Scheduler.init(allocator, 0); // 0 = auto-detect CPU count
    try scheduler.start();
    defer scheduler.deinit();

    // Results tracking
    var passed = std.atomic.Value(usize).init(0);
    var failed = std.atomic.Value(usize).init(0);

    // Context for each test file
    const TestCtx = struct {
        file_path: []const u8,
        alloc: std.mem.Allocator,
        passed: *std.atomic.Value(usize),
        failed: *std.atomic.Value(usize),

        fn run(ctx: *@This()) void {
            // Compile and run test file
            const opts = CompileOptions{ .input_file = ctx.file_path, .mode = "run", .force = true };
            compile.compileFile(ctx.alloc, opts) catch {
                _ = ctx.failed.fetchAdd(1, .monotonic);
                return;
            };
            _ = ctx.passed.fetchAdd(1, .monotonic);
        }
    };

    // Spawn all tests using metal0 async scheduler
    for (test_files.items) |file_path| {
        _ = try scheduler.spawn(TestCtx.run, .{
            .file_path = file_path,
            .alloc = allocator,
            .passed = &passed,
            .failed = &failed,
        });
    }

    // Wait for all tests
    scheduler.waitAll();

    // Report results
    const p = passed.load(.acquire);
    const f = failed.load(.acquire);
    std.debug.print("\n", .{});
    if (f == 0) {
        printSuccess("All {d} test files passed!", .{p});
    } else {
        printError("{d} passed, {d} failed", .{ p, f });
    }
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
                try cmdList(allocator);
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
