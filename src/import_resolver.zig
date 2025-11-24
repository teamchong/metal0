/// Import resolution for multi-file Python projects
const std = @import("std");
const builtin = @import("builtin");

/// Discover Python site-packages directories for Python 3.8-3.13
/// Returns owned slice of directory paths (caller must free)
pub fn discoverSitePackages(allocator: std.mem.Allocator) ![][]const u8 {
    var paths = std.ArrayList([]const u8){};
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    // Check for virtual environment first (VIRTUAL_ENV env var)
    if (std.posix.getenv("VIRTUAL_ENV")) |venv| {
        var venv_version: u8 = 8;
        while (venv_version <= 13) : (venv_version += 1) {
            const venv_path = std.fmt.allocPrint(
                allocator,
                "{s}/lib/python3.{d}/site-packages",
                .{ venv, venv_version },
            ) catch continue;
            paths.append(allocator, venv_path) catch allocator.free(venv_path);
        }
    }

    // Also check for .venv in current directory (common pattern)
    var local_venv_version: u8 = 8;
    while (local_venv_version <= 13) : (local_venv_version += 1) {
        const local_venv = std.fmt.allocPrint(
            allocator,
            ".venv/lib/python3.{d}/site-packages",
            .{local_venv_version},
        ) catch continue;
        paths.append(allocator, local_venv) catch allocator.free(local_venv);
    }

    switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd => {
            // Linux/BSD paths
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                // System site-packages
                const sys_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/lib/python3.{d}/site-packages",
                    .{version},
                );
                paths.append(allocator, sys_path) catch allocator.free(sys_path);

                const local_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/local/lib/python3.{d}/site-packages",
                    .{version},
                );
                paths.append(allocator, local_path) catch allocator.free(local_path);

                // User site-packages
                if (std.posix.getenv("HOME")) |home| {
                    const user_path = try std.fmt.allocPrint(
                        allocator,
                        "{s}/.local/lib/python3.{d}/site-packages",
                        .{ home, version },
                    );
                    paths.append(allocator, user_path) catch allocator.free(user_path);
                }
            }
        },
        .macos => {
            // macOS paths
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                // Framework installation
                const framework_path = try std.fmt.allocPrint(
                    allocator,
                    "/Library/Frameworks/Python.framework/Versions/3.{d}/lib/python3.{d}/site-packages",
                    .{ version, version },
                );
                paths.append(allocator, framework_path) catch allocator.free(framework_path);

                // Homebrew/local
                const local_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/local/lib/python3.{d}/site-packages",
                    .{version},
                );
                paths.append(allocator, local_path) catch allocator.free(local_path);

                // User site-packages
                if (std.posix.getenv("HOME")) |home| {
                    const user_path = try std.fmt.allocPrint(
                        allocator,
                        "{s}/Library/Python/3.{d}/lib/python/site-packages",
                        .{ home, version },
                    );
                    paths.append(allocator, user_path) catch allocator.free(user_path);
                }
            }
        },
        .windows => {
            // Windows paths
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                // Standard installation
                const sys_path = try std.fmt.allocPrint(
                    allocator,
                    "C:\\Python3{d}\\Lib\\site-packages",
                    .{version},
                );
                paths.append(allocator, sys_path) catch allocator.free(sys_path);

                // AppData installation
                if (std.posix.getenv("APPDATA")) |appdata| {
                    const user_path = try std.fmt.allocPrint(
                        allocator,
                        "{s}\\Python\\Python3{d}\\site-packages",
                        .{ appdata, version },
                    );
                    paths.append(allocator, user_path) catch allocator.free(user_path);
                }
            }
        },
        else => {
            // Unsupported platform - return empty list
        },
    }

    return paths.toOwnedSlice(allocator);
}

/// Discover Python standard library directories
/// Returns owned slice of directory paths (caller must free)
pub fn discoverStdlib(allocator: std.mem.Allocator) ![][]const u8 {
    var paths = std.ArrayList([]const u8){};
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    // Check for virtual environment first
    if (std.posix.getenv("VIRTUAL_ENV")) |venv| {
        var venv_version: u8 = 8;
        while (venv_version <= 13) : (venv_version += 1) {
            const venv_path = std.fmt.allocPrint(
                allocator,
                "{s}/lib/python3.{d}",
                .{ venv, venv_version },
            ) catch continue;
            paths.append(allocator, venv_path) catch allocator.free(venv_path);
        }
    }

    // Check .venv in current directory
    var local_venv_version: u8 = 8;
    while (local_venv_version <= 13) : (local_venv_version += 1) {
        const local_venv = std.fmt.allocPrint(
            allocator,
            ".venv/lib/python3.{d}",
            .{local_venv_version},
        ) catch continue;
        paths.append(allocator, local_venv) catch allocator.free(local_venv);
    }

    switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd => {
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                const sys_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/lib/python3.{d}",
                    .{version},
                );
                paths.append(allocator, sys_path) catch allocator.free(sys_path);

                const local_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/local/lib/python3.{d}",
                    .{version},
                );
                paths.append(allocator, local_path) catch allocator.free(local_path);
            }
        },
        .macos => {
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                const framework_path = try std.fmt.allocPrint(
                    allocator,
                    "/Library/Frameworks/Python.framework/Versions/3.{d}/lib/python3.{d}",
                    .{ version, version },
                );
                paths.append(allocator, framework_path) catch allocator.free(framework_path);

                const local_path = try std.fmt.allocPrint(
                    allocator,
                    "/usr/local/lib/python3.{d}",
                    .{version},
                );
                paths.append(allocator, local_path) catch allocator.free(local_path);

                // uv python installations
                if (std.posix.getenv("HOME")) |home| {
                    const uv_path = try std.fmt.allocPrint(
                        allocator,
                        "{s}/.local/share/uv/python/cpython-3.{d}*/lib/python3.{d}",
                        .{ home, version, version },
                    );
                    paths.append(allocator, uv_path) catch allocator.free(uv_path);
                }
            }
        },
        .windows => {
            var version: u8 = 8;
            while (version <= 13) : (version += 1) {
                const sys_path = try std.fmt.allocPrint(
                    allocator,
                    "C:\\Python3{d}\\Lib",
                    .{version},
                );
                paths.append(allocator, sys_path) catch allocator.free(sys_path);
            }
        },
        else => {},
    }

    return paths.toOwnedSlice(allocator);
}

/// Find a module in site-packages or stdlib directories
/// Returns owned path to module or null if not found
pub fn findInSitePackages(
    module_name: []const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    // Try site-packages first (for third-party packages)
    const site_packages = try discoverSitePackages(allocator);
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
    const stdlib_dirs = try discoverStdlib(allocator);
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

/// Resolve a Python module import to a .py file path
/// Returns null if module is not a local .py file
/// Resolve import to source .py file only (for compilation/scanning)
pub fn resolveImportSource(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !?[]const u8 {
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

/// Extract the directory from a file path
/// Returns "." if path has no directory component
pub fn getFileDirectory(file_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Find last slash
    var i = file_path.len;
    while (i > 0) {
        i -= 1;
        if (file_path[i] == '/' or file_path[i] == '\\') {
            // Return everything before the slash
            return try allocator.dupe(u8, file_path[0..i]);
        }
    }

    // No slash found - file is in current directory
    return try allocator.dupe(u8, ".");
}

/// Package information
pub const PackageInfo = struct {
    is_package: bool,
    init_path: []const u8, // Path to __init__.py
    package_dir: []const u8, // Directory containing package
    submodules: [][]const u8, // List of submodule names

    pub fn deinit(self: *PackageInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.init_path);
        allocator.free(self.package_dir);
        for (self.submodules) |submod| {
            allocator.free(submod);
        }
        allocator.free(self.submodules);
    }
};

/// Analyze a resolved import path to determine if it's a package with submodules
pub fn analyzePackage(
    import_path: []const u8,
    allocator: std.mem.Allocator,
) !PackageInfo {
    // Check if path points to __init__.py (package) or regular .py file (module)
    const is_init = std.mem.endsWith(u8, import_path, "__init__.py");

    if (!is_init) {
        // Single module, not a package
        return PackageInfo{
            .is_package = false,
            .init_path = try allocator.dupe(u8, import_path),
            .package_dir = try allocator.dupe(u8, "."),
            .submodules = &[_][]const u8{},
        };
    }

    // It's a package - extract directory path
    const package_dir = blk: {
        const last_slash = std.mem.lastIndexOf(u8, import_path, "/") orelse break :blk ".";
        break :blk import_path[0..last_slash];
    };

    // Scan package directory for submodules
    var submodules = std.ArrayList([]const u8){};
    errdefer {
        for (submodules.items) |item| allocator.free(item);
        submodules.deinit(allocator);
    }

    // Try to open directory
    var dir = std.fs.cwd().openDir(package_dir, .{ .iterate = true }) catch {
        // Can't open directory - treat as simple package
        return PackageInfo{
            .is_package = true,
            .init_path = try allocator.dupe(u8, import_path),
            .package_dir = try allocator.dupe(u8, package_dir),
            .submodules = &[_][]const u8{},
        };
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            // Check for .py files (excluding __init__.py and __pycache__)
            if (std.mem.endsWith(u8, entry.name, ".py") and
                !std.mem.eql(u8, entry.name, "__init__.py") and
                !std.mem.startsWith(u8, entry.name, "__"))
            {
                // Extract module name (remove .py)
                const mod_name = try allocator.dupe(u8, entry.name[0 .. entry.name.len - 3]);
                try submodules.append(allocator, mod_name);
            }
        } else if (entry.kind == .directory) {
            // Check for subpackages (directories with __init__.py)
            if (!std.mem.startsWith(u8, entry.name, "__")) {
                const subpkg_init = try std.fmt.allocPrint(allocator, "{s}/{s}/__init__.py", .{ package_dir, entry.name });
                defer allocator.free(subpkg_init);

                std.fs.cwd().access(subpkg_init, .{}) catch continue;

                // It's a subpackage
                const subpkg_name = try allocator.dupe(u8, entry.name);
                try submodules.append(allocator, subpkg_name);
            }
        }
    }

    return PackageInfo{
        .is_package = true,
        .init_path = try allocator.dupe(u8, import_path),
        .package_dir = try allocator.dupe(u8, package_dir),
        .submodules = try submodules.toOwnedSlice(allocator),
    };
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
    const site_packages = discoverSitePackages(allocator) catch return false;
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
