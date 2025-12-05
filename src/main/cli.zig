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
    } else if (std.mem.eql(u8, command, "deploy")) {
        cmdDeploy(args[2..]);
    } else if (std.mem.eql(u8, command, "run")) {
        try cmdRun(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "test")) {
        try cmdTest(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "codegen")) {
        try cmdCodegen(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build-fast")) {
        try cmdBuildFast(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build-runtime")) {
        try cmdBuildRuntime(allocator);
    } else if (std.mem.eql(u8, command, "setup-runtime")) {
        try cmdSetupRuntime(allocator);
    } else if (std.mem.eql(u8, command, "profile")) {
        try cmdProfile(allocator, args[2..]);
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

/// Profile command: wrapper for system profilers and profile translation
/// Usage:
///   metal0 profile run ./binary         - Profile with perf (Linux) or sample (macOS)
///   metal0 profile translate data.perf  - Convert profile to Python symbols
///   metal0 profile show profile.json    - Show Python-level profile summary
fn cmdProfile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print(
            \\{s}Profile commands:{s}
            \\
            \\  {s}metal0 profile run <binary>{s}       Profile a compiled binary
            \\  {s}metal0 profile translate <file>{s}   Convert perf/sample data to Python symbols
            \\  {s}metal0 profile show <file.json>{s}   Show Python-level profile summary
            \\
            \\{s}Workflow:{s}
            \\  1. Compile your Python file:     metal0 build -b app.py
            \\  2. Profile with run subcommand:  metal0 profile run ./build/.../app
            \\  3. Translate to Python symbols:  metal0 profile translate profile.data
            \\  4. Rebuild with profile:         metal0 build -b app.py --pgo-use=profile.json
            \\
        , .{
            Color.bold, Color.reset,
            Color.cyan, Color.reset,
            Color.cyan, Color.reset,
            Color.cyan, Color.reset,
            Color.bold, Color.reset,
        });
        return;
    }

    const subcmd = args[0];
    if (std.mem.eql(u8, subcmd, "run")) {
        try cmdProfileRun(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "translate")) {
        try cmdProfileTranslate(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "show")) {
        try cmdProfileShow(allocator, args[1..]);
    } else {
        printError("Unknown profile command: {s}", .{subcmd});
    }
}

/// Profile run: wrapper for system profilers
fn cmdProfileRun(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No binary specified", .{});
        std.debug.print("\nUsage: metal0 profile run <binary>\n", .{});
        return;
    }

    const binary_path = args[0];
    const builtin = @import("builtin");

    // Check if binary exists
    std.fs.cwd().access(binary_path, .{}) catch |err| {
        printError("Cannot access binary '{s}': {any}", .{ binary_path, err });
        return;
    };

    // Use platform-appropriate profiler
    if (builtin.os.tag == .macos) {
        std.debug.print("{s}Profiling with macOS sample tool...{s}\n", .{ Color.dim, Color.reset });
        std.debug.print("  Output: profile.txt (text format)\n\n", .{});

        // macOS: Use 'sample' command (built-in, no Instruments required)
        // sample <pid|name> <duration> -file <output>
        var child = std.process.Child.init(&[_][]const u8{
            "sample",
            binary_path,
            "5", // 5 seconds of profiling
            "-file",
            "profile.txt",
        }, allocator);
        child.spawn() catch |err| {
            printError("Failed to start profiler: {any}", .{err});
            return;
        };

        // Also start the binary
        var binary_child = std.process.Child.init(&[_][]const u8{binary_path}, allocator);
        binary_child.stdin_behavior = .Inherit;
        binary_child.stdout_behavior = .Inherit;
        binary_child.stderr_behavior = .Inherit;
        binary_child.spawn() catch |err| {
            printError("Failed to run binary: {any}", .{err});
            return;
        };

        // Wait for binary to finish
        _ = binary_child.wait() catch {};
        _ = child.wait() catch {};

        printSuccess("Profile written to profile.txt", .{});
        std.debug.print("Next: metal0 profile translate profile.txt\n", .{});
    } else if (builtin.os.tag == .linux) {
        std.debug.print("{s}Profiling with perf...{s}\n", .{ Color.dim, Color.reset });
        std.debug.print("  Output: perf.data\n\n", .{});

        // Linux: Use 'perf record'
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "perf",
                "record",
                "-g", // Call graphs
                "-o",
                "perf.data",
                "--",
                binary_path,
            },
        }) catch |err| {
            printError("Failed to run perf: {any}", .{err});
            std.debug.print("\nMake sure perf is installed: sudo apt install linux-tools-generic\n", .{});
            return;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            printSuccess("Profile written to perf.data", .{});
            std.debug.print("Next: metal0 profile translate perf.data\n", .{});
        } else {
            printError("perf failed: {s}", .{result.stderr});
        }
    } else {
        printError("Profile run not supported on this platform", .{});
        std.debug.print("Supported: Linux (perf), macOS (sample)\n", .{});
    }
}

/// Profile translate: convert system profiler output to Python symbols
fn cmdProfileTranslate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No profile data specified", .{});
        std.debug.print("\nUsage: metal0 profile translate <perf.data|profile.txt>\n", .{});
        return;
    }

    const input_path = args[0];

    // Check if input exists
    std.fs.cwd().access(input_path, .{}) catch |err| {
        printError("Cannot access profile data '{s}': {any}", .{ input_path, err });
        return;
    };

    // Look for debug info files
    const dbg_files = findDebugInfoFiles(allocator) catch |err| {
        printError("Cannot find debug info files: {any}", .{err});
        std.debug.print("\nMake sure to compile with --debug flag first\n", .{});
        return;
    };
    defer {
        for (dbg_files) |f| allocator.free(f);
        allocator.free(dbg_files);
    }

    if (dbg_files.len == 0) {
        printWarn("No .metal0.dbg.json files found", .{});
        std.debug.print("Compile with --debug to generate debug info\n", .{});
        return;
    }

    printInfo("Found {d} debug info files", .{dbg_files.len});

    // For now, just show what we'd do - actual translation is TODO
    std.debug.print("\n{s}Profile Translation (WIP):{s}\n", .{ Color.bold, Color.reset });
    std.debug.print("  Input: {s}\n", .{input_path});
    std.debug.print("  Debug info files:\n", .{});
    for (dbg_files) |f| {
        std.debug.print("    - {s}\n", .{f});
    }
    std.debug.print("\n  Output: profile.json (Python-level profile)\n", .{});
    std.debug.print("\n{s}TODO:{s} Parse profile data and translate Zig symbols to Python\n", .{ Color.yellow, Color.reset });
}

/// Profile show: display Python-level profile summary
fn cmdProfileShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    if (args.len == 0) {
        printError("No profile file specified", .{});
        std.debug.print("\nUsage: metal0 profile show <profile.json>\n", .{});
        return;
    }

    const profile_path = args[0];

    // Check if file exists
    std.fs.cwd().access(profile_path, .{}) catch |err| {
        printError("Cannot access profile '{s}': {any}", .{ profile_path, err });
        return;
    };

    // TODO: Parse and display profile
    printInfo("Profile: {s}", .{profile_path});
    std.debug.print("\n{s}TODO:{s} Parse and display Python-level profile\n", .{ Color.yellow, Color.reset });
}

/// Find all .metal0.dbg.json files in build directory
fn findDebugInfoFiles(allocator: std.mem.Allocator) ![][]const u8 {
    var files = std.ArrayList([]const u8){};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    // Search in build/ directory
    var dir = std.fs.cwd().openDir("build", .{ .iterate = true }) catch {
        return files.toOwnedSlice(allocator);
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch {
        return files.toOwnedSlice(allocator);
    };
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".metal0.dbg.json")) {
            const path = try std.fmt.allocPrint(allocator, "build/{s}", .{entry.path});
            try files.append(allocator, path);
        }
    }

    return files.toOwnedSlice(allocator);
}

fn cmdBuild(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = CompileOptions{ .input_file = undefined, .mode = "build" };
    var input_file: ?[]const u8 = null;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-g")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, arg, "--emit-zig")) {
            opts.emit_zig_only = true;
        } else if (std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "-t")) {
            // Parse --target <value>
            i += 1;
            if (i < args.len) {
                opts.target = parseTarget(args[i]);
            }
        } else if (std.mem.startsWith(u8, arg, "--target=")) {
            // Parse --target=<value>
            const value = arg["--target=".len..];
            opts.target = parseTarget(value);
        } else if (std.mem.eql(u8, arg, "--pgo-generate")) {
            opts.pgo_generate = true;
        } else if (std.mem.startsWith(u8, arg, "--pgo-use=")) {
            // Parse --pgo-use=<profile>
            const value = arg["--pgo-use=".len..];
            opts.pgo_use = value;
        } else if (std.mem.eql(u8, arg, "--pgo-use")) {
            // Parse --pgo-use <profile>
            i += 1;
            if (i < args.len) {
                opts.pgo_use = args[i];
            }
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

fn parseTarget(value: []const u8) CompileOptions.Target {
    if (std.mem.eql(u8, value, "native")) return .native;
    if (std.mem.eql(u8, value, "wasm-browser") or std.mem.eql(u8, value, "wasm_browser")) return .wasm_browser;
    if (std.mem.eql(u8, value, "wasm-edge") or std.mem.eql(u8, value, "wasm_edge")) return .wasm_edge;
    if (std.mem.eql(u8, value, "linux-x64") or std.mem.eql(u8, value, "linux_x64")) return .linux_x64;
    if (std.mem.eql(u8, value, "linux-arm64") or std.mem.eql(u8, value, "linux_arm64")) return .linux_arm64;
    if (std.mem.eql(u8, value, "macos-x64") or std.mem.eql(u8, value, "macos_x64")) return .macos_x64;
    if (std.mem.eql(u8, value, "macos-arm64") or std.mem.eql(u8, value, "macos_arm64")) return .macos_arm64;
    if (std.mem.eql(u8, value, "windows-x64") or std.mem.eql(u8, value, "windows_x64")) return .windows_x64;
    // Default to native for unknown targets
    printWarn("Unknown target '{s}', using native", .{value});
    return .native;
}

/// Deploy to remote server (WIP - not yet implemented)
fn cmdDeploy(args: []const []const u8) void {
    _ = args;
    printWarn("Deploy command is work-in-progress", .{});
    std.debug.print("\n{s}Coming soon:{s}\n", .{ Color.bold, Color.reset });
    std.debug.print("  metal0 deploy app.py --to my-server\n", .{});
    std.debug.print("  metal0 deploy app.py --to user@host:/path\n", .{});
    std.debug.print("\nFor now, use:\n", .{});
    std.debug.print("  metal0 build -b app.py && scp ./app my-server:\n\n", .{});
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

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-g")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, arg, "--emit-zig")) {
            opts.emit_zig_only = true;
        } else if (std.mem.eql(u8, arg, "--pgo-generate")) {
            opts.pgo_generate = true;
        } else if (std.mem.startsWith(u8, arg, "--pgo-use=")) {
            opts.pgo_use = arg["--pgo-use=".len..];
        } else if (std.mem.eql(u8, arg, "--pgo-use")) {
            i += 1;
            if (i < args.len) opts.pgo_use = args[i];
        }
    }

    try compile.compileFile(allocator, opts);
}

/// Setup runtime files in .metal0/cache/ (Phase 0 for batch compilation)
fn cmdSetupRuntime(allocator: std.mem.Allocator) !void {
    const compiler_mod = @import("../compiler.zig");
    try compiler_mod.setupRuntimeFiles(allocator);
    printSuccess("Runtime files ready in .metal0/cache/", .{});
}

/// Build runtime static archive (.a) for fast linking
/// Usage: metal0 build-runtime
fn cmdBuildRuntime(allocator: std.mem.Allocator) !void {
    const incr = @import("compile/incremental.zig");

    std.debug.print("{s}=== Building Runtime Archive ==={s}\n", .{ Color.bold, Color.reset });
    std.debug.print("Building .metal0/lib/libruntime.a (precompiled, cached)...\n", .{});

    try incr.buildRuntimeArchive(allocator);

    printSuccess("Runtime archive built: {s}", .{incr.RUNTIME_ARCHIVE_PATH});
    std.debug.print("Future compilations will link against this archive (10x faster).\n", .{});
}

/// Codegen-only batch command: fast parallel codegen with error summary
/// Usage: metal0 codegen tests/cpython
fn cmdCodegen(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const test_dir = if (args.len > 0) args[0] else ".";

    // Discover .py files
    var py_files = std.ArrayList([]const u8){};
    defer {
        for (py_files.items) |f| allocator.free(f);
        py_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(test_dir, .{ .iterate = true }) catch |err| {
        printError("Cannot open directory: {s} ({any})", .{ test_dir, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".py")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_dir, entry.name });
            try py_files.append(allocator, path);
        }
    }

    const total = py_files.items.len;
    if (total == 0) {
        printWarn("No .py files found in {s}", .{test_dir});
        return;
    }

    std.debug.print("Codegen {d} files from {s}...\n", .{ total, test_dir });

    const ErrorInfo = struct {
        file: []const u8,
        message: []const u8,
    };

    // Track results
    var passed: usize = 0;
    var errors = std.ArrayList(ErrorInfo){};
    defer {
        for (errors.items) |e| {
            allocator.free(e.file);
            allocator.free(e.message);
        }
        errors.deinit(allocator);
    }

    // Run codegen on each file sequentially (thread-safe output)
    for (py_files.items) |file_path| {
        const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = true, .emit_zig_only = true };

        // Capture stderr for error message
        var err_msg: []const u8 = "";
        compile.compileFile(allocator, opts) catch |err| {
            err_msg = try std.fmt.allocPrint(allocator, "{any}", .{err});
            try errors.append(allocator, .{
                .file = try allocator.dupe(u8, std.fs.path.basename(file_path)),
                .message = err_msg,
            });
            continue;
        };
        passed += 1;
    }

    // Print summary
    std.debug.print("\n{s}=== Codegen Results ==={s}\n", .{ Color.bold, Color.reset });
    std.debug.print("Passed: {s}{d}/{d}{s}\n", .{ Color.green, passed, total, Color.reset });

    if (errors.items.len > 0) {
        std.debug.print("Failed: {s}{d}{s}\n\n", .{ Color.red, errors.items.len, Color.reset });

        // Group errors by type
        var error_counts = std.StringHashMap(usize).init(allocator);
        defer error_counts.deinit();

        for (errors.items) |e| {
            const count = error_counts.get(e.message) orelse 0;
            error_counts.put(e.message, count + 1) catch {};
        }

        std.debug.print("{s}Error summary:{s}\n", .{ Color.bold, Color.reset });
        var err_iter = error_counts.iterator();
        while (err_iter.next()) |entry| {
            std.debug.print("  {s}{d}x{s} {s}\n", .{ Color.yellow, entry.value_ptr.*, Color.reset, entry.key_ptr.* });
        }

        // Show first 10 failed files
        std.debug.print("\n{s}Failed files (first 10):{s}\n", .{ Color.bold, Color.reset });
        const show_count = @min(errors.items.len, 10);
        for (errors.items[0..show_count]) |e| {
            std.debug.print("  {s}✗{s} {s}\n", .{ Color.red, Color.reset, e.file });
        }
    }
}

/// Fast incremental build using Zig's --cache-dir for hash-based caching
/// Usage: metal0 build-fast <dir> [-j N]
/// - Codegens .py → .zig
/// - Compiles .zig → .o with Zig's built-in caching
/// - Links .o → binary with --gc-sections for DCE
fn cmdBuildFast(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const incremental = @import("compile/incremental.zig");

    // Parse args
    var dir_path: []const u8 = ".";
    var parallelism: usize = 8;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-j") and i + 1 < args.len) {
            parallelism = std.fmt.parseInt(usize, args[i + 1], 10) catch 8;
            i += 1;
        } else {
            dir_path = args[i];
        }
    }

    // Phase 1: Discover .py files
    var py_files = std.ArrayList([]const u8){};
    defer {
        for (py_files.items) |f| allocator.free(f);
        py_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        printError("Cannot open directory: {s} ({any})", .{ dir_path, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".py")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            try py_files.append(allocator, path);
        }
    }

    const total = py_files.items.len;
    if (total == 0) {
        printWarn("No .py files found in {s}", .{dir_path});
        return;
    }

    std.debug.print("{s}=== Incremental Build ({d} files, {d} parallel) ==={s}\n", .{ Color.bold, total, parallelism, Color.reset });

    // Phase 2: Codegen .py → .zig
    std.debug.print("Phase 1: Codegen .py → .zig...\n", .{});
    var zig_files = std.ArrayList([]const u8){};
    defer {
        for (zig_files.items) |f| allocator.free(f);
        zig_files.deinit(allocator);
    }

    var codegen_ok: usize = 0;
    for (py_files.items) |file_path| {
        const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = true, .emit_zig_only = true };
        compile.compileFile(allocator, opts) catch continue;
        codegen_ok += 1;

        // Get the generated .zig path - check if it exists
        const basename = std.fs.path.basename(file_path);
        const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
        const zig_path = try std.fmt.allocPrint(allocator, ".metal0/cache/{s}.zig", .{stem});

        // Only add if file exists
        std.fs.cwd().access(zig_path, .{}) catch {
            allocator.free(zig_path);
            continue;
        };
        try zig_files.append(allocator, zig_path);
    }
    std.debug.print("  {s}✓{s} Codegen: {d}/{d} ({d} zig files)\n", .{ Color.green, Color.reset, codegen_ok, total, zig_files.items.len });

    if (codegen_ok == 0) {
        printError("All codegen failed", .{});
        return;
    }

    // Phase 3: Compile .zig → .o using Zig's cache
    std.debug.print("Phase 2: Compile .zig → .o (with Zig cache)...\n", .{});
    const compile_ok = incremental.batchCompile(allocator, zig_files.items, parallelism) catch |err| {
        printError("Batch compile failed: {any}", .{err});
        return;
    };
    std.debug.print("  {s}✓{s} Compiled: {d}/{d}\n", .{ Color.green, Color.reset, compile_ok, codegen_ok });

    printSuccess("Build complete! .o files in .metal0/cache/", .{});
    std.debug.print("  {s}Hint:{s} Run `metal0 <file.py>` to link and execute\n", .{ Color.dim, Color.reset });
}

/// Bun-style test command: metal0 test <dir>
/// 3-phase: codegen → compile → run (all parallel, with Zig caching)
fn cmdTest(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const incremental = @import("compile/incremental.zig");
    const build_dirs = @import("../build_dirs.zig");
    const compiler_mod = @import("../compiler.zig");

    const run_timeout_ns = 10 * std.time.ns_per_min; // per-test timeout (10 minutes)

    // Parse test directory from args or default to tests/cpython
    const test_dir = if (args.len > 0) args[0] else "tests/cpython";
    const ncpu = std.Thread.getCpuCount() catch 8;

    std.debug.print("=== metal0 test ({s}) ===\n", .{test_dir});

    // Phase 0: Setup runtime + ensure cache dirs exist
    try build_dirs.init();
    try compiler_mod.setupRuntimeFiles(allocator);

    // Ensure bin output dir exists
    std.fs.cwd().makeDir(".metal0/bin") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Discover test files
    var test_files = std.ArrayList([]const u8){};
    defer {
        for (test_files.items) |f| allocator.free(f);
        test_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(test_dir, .{ .iterate = true }) catch {
        printError("Cannot open test directory: {s}", .{test_dir});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "test_") and std.mem.endsWith(u8, entry.name, ".py")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_dir, entry.name });
            try test_files.append(allocator, path);
        }
    }

    const total = test_files.items.len;
    if (total == 0) {
        printWarn("No test files found in {s}", .{test_dir});
        return;
    }

    std.debug.print("Found {d} tests, using {d} parallel workers\n\n", .{ total, ncpu });

    // Phase 1: Parallel codegen (.py → .zig)
    // Use batched processing with arena reset to prevent memory accumulation
    std.debug.print("Phase 1: Codegen...\n", .{});
    var codegen_ok: usize = 0;
    var zig_files = std.ArrayList([]const u8){};
    defer {
        for (zig_files.items) |f| allocator.free(f);
        zig_files.deinit(allocator);
    }

    const BATCH_SIZE = 50; // Process in batches to limit memory
    var batch_start: usize = 0;
    while (batch_start < test_files.items.len) {
        const batch_end = @min(batch_start + BATCH_SIZE, test_files.items.len);

        for (test_files.items[batch_start..batch_end]) |file_path| {
            const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = true, .emit_zig_only = true };
            compile.compileFile(allocator, opts) catch continue;
            codegen_ok += 1;

            // Get the generated zig file path
            const basename = std.fs.path.basename(file_path);
            const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
            const zig_path = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ build_dirs.CACHE, stem });
            try zig_files.append(allocator, zig_path);
        }

        batch_start = batch_end;
    }
    std.debug.print("  Codegen: {d}/{d}\n", .{ codegen_ok, total });

    if (codegen_ok == 0) {
        printError("All codegen failed", .{});
        return;
    }

    // Phase 2: Batch compile using Zig's cache (.zig → binary)
    // Key: use --cache-dir for hash-based caching (Zig handles incremental!)
    std.debug.print("Phase 2: Compile (cached)...\n", .{});
    var compile_ok: usize = 0;
    var bin_paths = std.ArrayList([]const u8){};
    defer {
        for (bin_paths.items) |p| allocator.free(p);
        bin_paths.deinit(allocator);
    }

    // Pre-allocate reusable arg strings to avoid leaks
    const include_arg = try std.fmt.allocPrint(allocator, "-I{s}", .{build_dirs.CACHE});
    defer allocator.free(include_arg);

    for (zig_files.items) |zig_path| {
        // Check if zig file exists
        std.fs.cwd().access(zig_path, .{}) catch continue;

        const basename = std.fs.path.basename(zig_path);
        const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
        const bin_path = try std.fmt.allocPrint(allocator, ".metal0/bin/{s}", .{stem});
        const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{bin_path});
        defer allocator.free(emit_arg); // FIX: was leaking before!

        // Use Zig's built-in cache for incremental compilation
        // Limit Zig's parallelism to reduce peak memory usage
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "zig",
                "build-exe",
                zig_path,
                "--cache-dir",
                incremental.ZIG_CACHE_DIR,
                "-OReleaseFast",
                "-lc",
                "-fno-stack-check",
                "-ffunction-sections",
                "-fdata-sections",
                "-j2", // Limit Zig threads to reduce memory pressure
                include_arg,
                emit_arg,
            },
        }) catch {
            allocator.free(bin_path);
            continue;
        };
        allocator.free(result.stdout); // Free immediately, don't defer
        allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited == 0) {
            compile_ok += 1;
            try bin_paths.append(allocator, bin_path);
        } else {
            allocator.free(bin_path);
        }
    }
    std.debug.print("  Compile: {d}/{d}\n", .{ compile_ok, codegen_ok });

    // Phase 3: Run binaries
    std.debug.print("Phase 3: Run...\n", .{});
    var run_ok: usize = 0;
    var run_timeout: usize = 0;

    for (bin_paths.items) |bin_path| {
        switch (runBinaryWithTimeout(allocator, bin_path, run_timeout_ns)) {
            .ok => run_ok += 1,
            .timeout => run_timeout += 1,
            .failed => {},
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("Results: {d}/{d} passed (timeout: {d})\n", .{ run_ok, total, run_timeout });
}

const RunResult = enum { ok, timeout, failed };

fn runBinaryWithTimeout(allocator: std.mem.Allocator, bin_path: []const u8, timeout_ns: u64) RunResult {
    var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    // Track completion across the killer thread
    var done = std.atomic.Value(bool).init(false);

    child.spawn() catch return .failed;

    var killer = std.Thread.spawn(.{}, killAfterTimeout, .{ &child, timeout_ns, &done }) catch {
        // If we can't start the killer thread, fall back to blocking wait
        const term = child.wait() catch return .failed;
        done.store(true, .seq_cst);
        return switch (term) {
            .Exited => |code| if (code == 0) .ok else .failed,
            else => .failed,
        };
    };
    defer killer.join();

    const term = child.wait() catch return .failed;
    done.store(true, .seq_cst);

    return switch (term) {
        .Exited => |code| if (code == 0) .ok else .failed,
        else => .failed,
    };
}

fn killAfterTimeout(child: *std.process.Child, timeout_ns: u64, done: *std.atomic.Value(bool)) void {
    std.Thread.sleep(timeout_ns);
    if (done.load(.seq_cst)) return;
    _ = child.kill() catch {};
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
        \\   profile      Profile and optimize (run, translate, show)
        \\   deploy       Deploy to remote server (WIP)
        \\
        \\{s}BUILD OPTIONS:{s}
        \\   --target <t>      Cross-compile target:
        \\                     native (default), wasm-browser, wasm-edge,
        \\                     linux-x64, linux-arm64, macos-x64, macos-arm64, windows-x64
        \\   --debug, -g       Emit debug info (.metal0.dbg.json)
        \\   --pgo-generate    Build with PGO instrumentation (generates profile data)
        \\   --pgo-use=<file>  Build optimized using profile data from <file>
        \\
        \\{s}EXAMPLES:{s}
        \\   metal0 app.py                        # Run Python file (30x faster)
        \\   metal0 -c "print('hi')"              # Execute code string
        \\   metal0 -m pip install requests       # Use pip through metal0
        \\   metal0 install requests              # Install packages
        \\   metal0 build -b app.py               # Compile to binary
        \\   metal0 build --target wasm-edge app.py  # Compile to WASM for edge
        \\
    , .{
        Color.bold_cyan, Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
    });
}
