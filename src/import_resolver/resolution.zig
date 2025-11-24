/// Module resolution logic - Find Python modules in various search paths
const std = @import("std");
const builtin = @import("builtin");
const discovery = @import("discovery.zig");

/// Check if a module is a built-in Zig module that should not be scanned/compiled
/// Built-in modules: json, http, asyncio, re, numpy, sqlite3, zlib, ssl, sys
pub fn isBuiltinModule(module_name: []const u8) bool {
    const builtins = [_][]const u8{
        "json",    "http",    "asyncio",  "re",
        "numpy",   "sqlite3", "zlib",     "ssl",
        "pathlib", "urllib",  "datetime", "importlib",
        "sys",     "time",
    };
    for (builtins) |builtin_module| {
        if (std.mem.eql(u8, module_name, builtin_module)) {
            return true;
        }
    }
    return false;
}

/// Find module in site-packages or stdlib directories
pub fn findInSitePackages(
    module_name: []const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    // Try site-packages first (for third-party packages)
    const site_packages = try discovery.discoverSitePackages(allocator);
    defer {
        for (site_packages) |path| allocator.free(path);
        allocator.free(site_packages);
    }

    for (site_packages) |site_dir| {
        // Try direct module file: site-packages/module.py
        const module_file = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}.py",
            .{ site_dir, module_name },
        );

        std.fs.cwd().access(module_file, .{}) catch {
            allocator.free(module_file);

            // Try package __init__.py: site-packages/module/__init__.py
            const package_init = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}/__init__.py",
                .{ site_dir, module_name },
            );

            std.fs.cwd().access(package_init, .{}) catch {
                allocator.free(package_init);
                continue;
            };

            return package_init;
        };

        return module_file;
    }

    // Try stdlib directories (for standard library modules like pathlib)
    const stdlib_dirs = try discovery.discoverStdlib(allocator);
    defer {
        for (stdlib_dirs) |path| allocator.free(path);
        allocator.free(stdlib_dirs);
    }

    for (stdlib_dirs) |stdlib_dir| {
        // Try direct module file: lib/python3.X/module.py
        const module_file = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}.py",
            .{ stdlib_dir, module_name },
        );

        std.fs.cwd().access(module_file, .{}) catch {
            allocator.free(module_file);

            // Try package __init__.py: lib/python3.X/module/__init__.py
            const package_init = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}/__init__.py",
                .{ stdlib_dir, module_name },
            );

            std.fs.cwd().access(package_init, .{}) catch {
                allocator.free(package_init);
                continue;
            };

            return package_init;
        };

        return module_file;
    }

    return null;
}

/// Resolve import to source .py file only (for compilation/scanning)
pub fn resolveImportSource(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    // Skip built-in Zig modules (json, http, etc.)
    if (isBuiltinModule(module_name)) {
        return null;
    }

    // Skip compiled .so check - only look for .py sources
    return resolveImportInternal(module_name, source_file_dir, allocator, false);
}

/// Resolve import including compiled .so files (for runtime)
pub fn resolveImport(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    return resolveImportInternal(module_name, source_file_dir, allocator, true);
}

fn resolveImportInternal(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
    check_compiled: bool,
) !?[]const u8 {
    // Try different search paths in order of priority:
    // 0. Compiled modules in build/lib.{platform}/ (if check_compiled)
    // 1. Same directory as source file (if provided)
    // 2. Current working directory
    // 3. examples/ directory (for backward compatibility)
    // 4. Site-packages directories

    // Check compiled modules first (if enabled)
    if (check_compiled) {
        const arch = switch (builtin.cpu.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "arm64",
            else => "unknown",
        };
        const compiled_paths = [_][]const u8{
            try std.fmt.allocPrint(allocator, "build/lib.macosx-11.0-{s}/{s}.cpython-312-darwin.so", .{ arch, module_name }),
            try std.fmt.allocPrint(allocator, "build/lib.macosx-11.0-{s}/{s}/__init__.cpython-312-darwin.so", .{ arch, module_name }),
        };

        for (compiled_paths) |compiled_path| {
            std.fs.cwd().access(compiled_path, .{}) catch {
                allocator.free(compiled_path);
                continue;
            };
            // Found compiled module - return it!
            return compiled_path;
        }
    }

    var search_paths = std.ArrayList([]const u8){};
    defer search_paths.deinit(allocator);

    // Add source file directory as first priority
    if (source_file_dir) |dir| {
        try search_paths.append(allocator, dir);
    }

    // Add current directory
    try search_paths.append(allocator, ".");

    // Add examples directory
    try search_paths.append(allocator, "examples");

    // Try each search path
    for (search_paths.items) |search_dir| {
        // Try module.py first
        const py_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}.py",
            .{ search_dir, module_name },
        );

        // Check if file exists
        std.fs.cwd().access(py_path, .{}) catch {
            allocator.free(py_path);

            // Try package/__init__.py
            const pkg_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}/__init__.py",
                .{ search_dir, module_name },
            );

            std.fs.cwd().access(pkg_path, .{}) catch {
                allocator.free(pkg_path);
                continue;
            };

            // Package found!
            return pkg_path;
        };

        // Module file found!
        return py_path;
    }

    // Try site-packages as fallback
    if (try findInSitePackages(module_name, allocator)) |site_path| {
        return site_path;
    }

    // Not found in any search path
    return null;
}

/// Check if a module name refers to a local Python file
pub fn isLocalModule(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !bool {
    const resolved = try resolveImport(module_name, source_file_dir, allocator);
    if (resolved) |path| {
        allocator.free(path);
        return true;
    }
    return false;
}

/// Check if a module is a C extension (.so, .dylib, .pyd)
/// Searches site-packages and virtual env paths
pub fn isCExtension(
    module_name: []const u8,
    allocator: std.mem.Allocator,
) bool {
    // C extension file suffixes by platform
    const extensions = switch (builtin.os.tag) {
        .macos => &[_][]const u8{ ".so", ".dylib" },
        .windows => &[_][]const u8{ ".pyd", ".dll" },
        else => &[_][]const u8{".so"},
    };

    // Get site-packages directories
    const site_packages = discovery.discoverSitePackages(allocator) catch return false;
    defer {
        for (site_packages) |path| allocator.free(path);
        allocator.free(site_packages);
    }

    // Check each site-packages directory for C extension files
    for (site_packages) |site_dir| {
        for (extensions) |ext| {
            const full_path = std.fmt.allocPrint(
                allocator,
                "{s}/{s}{s}",
                .{ site_dir, module_name, ext },
            ) catch continue;
            defer allocator.free(full_path);

            std.fs.cwd().access(full_path, .{}) catch continue;

            // Found a C extension!
            return true;
        }
    }

    return false;
}
