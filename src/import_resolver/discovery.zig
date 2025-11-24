/// Python path discovery - Find site-packages and stdlib directories
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
                        "{s}/Library/Application Support/uv/python/cpython-3.{d}.*/lib/python3.{d}",
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

                if (std.posix.getenv("APPDATA")) |appdata| {
                    const user_path = try std.fmt.allocPrint(
                        allocator,
                        "{s}\\Python\\Python3{d}\\Lib",
                        .{ appdata, version },
                    );
                    paths.append(allocator, user_path) catch allocator.free(user_path);
                }
            }
        },
        else => {},
    }

    return paths.toOwnedSlice(allocator);
}
