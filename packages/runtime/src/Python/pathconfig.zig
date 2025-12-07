/// pathconfig - Path Configuration
/// Mirrors cpython/Python/pathconfig.c
///
/// This module handles Python path configuration:
/// - Module search paths (sys.path)
/// - Python home directory
/// - Executable path resolution
/// - Prefix and exec_prefix calculation

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// Landmark file for standard library detection
pub const STDLIB_LANDMARK = "os.py";

/// Python version for path calculation
pub const PYTHON_VERSION = "3.13";

/// Default module search paths separator
pub const PATH_SEPARATOR = if (builtin.os.tag == .windows) ";" else ":";

// ============================================================================
// Path Configuration
// ============================================================================

/// Python path configuration state
pub const PyPathConfig = struct {
    /// Program name (argv[0] or sys.executable)
    program_name: ?[]const u8 = null,

    /// Python home directory
    home: ?[]const u8 = null,

    /// Full path to Python executable
    executable: ?[]const u8 = null,

    /// Base executable (for virtual environments)
    base_executable: ?[]const u8 = null,

    /// Installation prefix
    prefix: ?[]const u8 = null,

    /// Base prefix (without venv)
    base_prefix: ?[]const u8 = null,

    /// Exec prefix
    exec_prefix: ?[]const u8 = null,

    /// Base exec prefix
    base_exec_prefix: ?[]const u8 = null,

    /// Module search path
    module_search_path: ?[]const u8 = null,

    /// Standard library directory
    stdlib_dir: ?[]const u8 = null,

    /// Path configuration is initialized
    initialized: bool = false,

    /// Allocator
    allocator: ?Allocator = null,

    const Self = @This();

    /// Create empty path config
    pub fn init() Self {
        return .{};
    }

    /// Create with allocator
    pub fn initWithAllocator(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Clear all paths
    pub fn clear(self: *Self) void {
        self.program_name = null;
        self.home = null;
        self.executable = null;
        self.base_executable = null;
        self.prefix = null;
        self.base_prefix = null;
        self.exec_prefix = null;
        self.base_exec_prefix = null;
        self.module_search_path = null;
        self.stdlib_dir = null;
        self.initialized = false;
    }

    /// Copy from another config
    pub fn copy(other: *const Self) Self {
        return other.*;
    }

    /// Check if config is valid
    pub fn isValid(self: *const Self) bool {
        return self.initialized and
            self.executable != null and
            self.prefix != null;
    }
};

// ============================================================================
// Path Resolution
// ============================================================================

/// Resolve the Python executable path
pub fn resolveExecutable(program_name: []const u8, allocator: Allocator) ![]const u8 {
    // Check if it's already an absolute path
    if (std.fs.path.isAbsolute(program_name)) {
        return try allocator.dupe(u8, program_name);
    }

    // Check if it contains a path separator
    if (std.mem.indexOf(u8, program_name, std.fs.path.sep_str) != null) {
        // Resolve relative to current directory
        const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);
        return try std.fs.path.join(allocator, &[_][]const u8{ cwd, program_name });
    }

    // Search in PATH
    if (std.posix.getenv("PATH")) |path_env| {
        var path_iter = std.mem.splitScalar(u8, path_env, ':');
        while (path_iter.next()) |dir| {
            const candidate = try std.fs.path.join(allocator, &[_][]const u8{ dir, program_name });
            defer allocator.free(candidate);

            if (std.fs.accessAbsolute(candidate, .{})) |_| {
                return try allocator.dupe(u8, candidate);
            } else |_| {}
        }
    }

    // Fall back to program name
    return try allocator.dupe(u8, program_name);
}

/// Find Python home directory
pub fn findPythonHome(executable: []const u8, allocator: Allocator) !?[]const u8 {
    // Check PYTHONHOME environment variable
    if (std.posix.getenv("PYTHONHOME")) |home| {
        return try allocator.dupe(u8, home);
    }

    // Try to find based on executable location
    // Go up from executable to find lib/pythonX.Y
    const exe_dir = std.fs.path.dirname(executable) orelse return null;

    // Check if we're in a bin directory
    if (std.mem.endsWith(u8, exe_dir, "bin")) {
        const parent = std.fs.path.dirname(exe_dir) orelse return null;
        // Check for lib/pythonX.Y/os.py
        const lib_path = try std.fs.path.join(allocator, &[_][]const u8{
            parent,
            "lib",
            "python" ++ PYTHON_VERSION,
            STDLIB_LANDMARK,
        });
        defer allocator.free(lib_path);

        if (std.fs.accessAbsolute(lib_path, .{})) |_| {
            return try allocator.dupe(u8, parent);
        } else |_| {}
    }

    return null;
}

/// Calculate prefix from home
pub fn calculatePrefix(home: ?[]const u8, executable: []const u8, allocator: Allocator) ![]const u8 {
    if (home) |h| {
        return try allocator.dupe(u8, h);
    }

    // Derive from executable
    const exe_dir = std.fs.path.dirname(executable) orelse return error.InvalidExecutable;
    if (std.mem.endsWith(u8, exe_dir, "bin")) {
        const parent = std.fs.path.dirname(exe_dir) orelse return error.InvalidExecutable;
        return try allocator.dupe(u8, parent);
    }

    return try allocator.dupe(u8, exe_dir);
}

/// Get stdlib directory
pub fn getStdlibDir(prefix: []const u8, allocator: Allocator) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{
        prefix,
        "lib",
        "python" ++ PYTHON_VERSION,
    });
}

/// Build module search path
pub fn buildModuleSearchPath(config: *const PyPathConfig, allocator: Allocator) ![]const u8 {
    var paths = std.ArrayList(u8).init(allocator);
    defer paths.deinit();

    // Add stdlib directory
    if (config.stdlib_dir) |stdlib| {
        try paths.appendSlice(stdlib);
        try paths.appendSlice(PATH_SEPARATOR);
    }

    // Add site-packages
    if (config.prefix) |prefix| {
        const site_packages = try std.fs.path.join(allocator, &[_][]const u8{
            prefix,
            "lib",
            "python" ++ PYTHON_VERSION,
            "site-packages",
        });
        defer allocator.free(site_packages);
        try paths.appendSlice(site_packages);
        try paths.appendSlice(PATH_SEPARATOR);
    }

    // Add current directory
    try paths.append('.');

    return try paths.toOwnedSlice();
}

// ============================================================================
// Virtual Environment Support
// ============================================================================

/// Check if running in virtual environment
pub fn isVirtualEnv(config: *const PyPathConfig) bool {
    if (config.prefix == null or config.base_prefix == null) {
        return false;
    }
    return !std.mem.eql(u8, config.prefix.?, config.base_prefix.?);
}

/// Get pyvenv.cfg path
pub fn getPyVenvCfgPath(executable: []const u8, allocator: Allocator) !?[]const u8 {
    const exe_dir = std.fs.path.dirname(executable) orelse return null;

    // Check executable directory
    const cfg_in_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "pyvenv.cfg" });
    defer allocator.free(cfg_in_dir);

    if (std.fs.accessAbsolute(cfg_in_dir, .{})) |_| {
        return try allocator.dupe(u8, cfg_in_dir);
    } else |_| {}

    // Check parent directory (for venv/bin/python layout)
    if (std.fs.path.dirname(exe_dir)) |parent_dir| {
        const cfg_in_parent = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir, "pyvenv.cfg" });
        defer allocator.free(cfg_in_parent);

        if (std.fs.accessAbsolute(cfg_in_parent, .{})) |_| {
            return try allocator.dupe(u8, cfg_in_parent);
        } else |_| {}
    }

    return null;
}

/// Parse pyvenv.cfg file
pub const PyVenvConfig = struct {
    home: ?[]const u8 = null,
    include_system_site_packages: bool = false,
    version: ?[]const u8 = null,

    pub fn parse(content: []const u8, allocator: Allocator) !PyVenvConfig {
        var config = PyVenvConfig{};
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

                if (std.mem.eql(u8, key, "home")) {
                    config.home = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "include-system-site-packages")) {
                    config.include_system_site_packages = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "version")) {
                    config.version = try allocator.dupe(u8, value);
                }
            }
        }

        return config;
    }
};

// ============================================================================
// Global State
// ============================================================================

var g_pathconfig: PyPathConfig = PyPathConfig.init();

/// Get global path configuration
pub fn getPathConfig() *const PyPathConfig {
    return &g_pathconfig;
}

/// Get mutable global path configuration
pub fn getPathConfigMut() *PyPathConfig {
    return &g_pathconfig;
}

/// Set global path configuration
pub fn setPathConfig(config: *const PyPathConfig) void {
    g_pathconfig = config.*;
}

/// Clear global path configuration
pub fn clearPathConfig() void {
    g_pathconfig.clear();
}

// ============================================================================
// sys.path Helpers
// ============================================================================

/// Split a path string into list
pub fn splitPath(path_str: []const u8, allocator: Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(allocator);

    var iter = std.mem.splitSequence(u8, path_str, PATH_SEPARATOR);
    while (iter.next()) |part| {
        if (part.len > 0) {
            try result.append(part);
        }
    }

    return result;
}

/// Join paths into string
pub fn joinPath(paths: []const []const u8, allocator: Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (paths, 0..) |path, i| {
        if (i > 0) {
            try result.appendSlice(PATH_SEPARATOR);
        }
        try result.appendSlice(path);
    }

    return try result.toOwnedSlice();
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "path config init" {
    var config = PyPathConfig.init();
    try std.testing.expect(!config.initialized);
    try std.testing.expect(!config.isValid());

    config.executable = "/usr/bin/python3";
    config.prefix = "/usr";
    config.initialized = true;
    try std.testing.expect(config.isValid());
}

test "path config copy" {
    var orig = PyPathConfig.init();
    orig.executable = "/usr/bin/python3";
    orig.prefix = "/usr";
    orig.initialized = true;

    const copied = PyPathConfig.copy(&orig);
    try std.testing.expect(copied.initialized);
    try std.testing.expectEqualStrings("/usr/bin/python3", copied.executable.?);
}

test "is virtual env" {
    var config = PyPathConfig.init();
    config.prefix = "/home/user/venv";
    config.base_prefix = "/usr";

    try std.testing.expect(isVirtualEnv(&config));

    config.base_prefix = "/home/user/venv";
    try std.testing.expect(!isVirtualEnv(&config));
}

test "split path" {
    const paths = try splitPath("/usr/lib:/usr/local/lib:.", std.testing.allocator);
    defer paths.deinit();

    try std.testing.expectEqual(@as(usize, 3), paths.items.len);
    try std.testing.expectEqualStrings("/usr/lib", paths.items[0]);
    try std.testing.expectEqualStrings("/usr/local/lib", paths.items[1]);
    try std.testing.expectEqualStrings(".", paths.items[2]);
}

test "join path" {
    const paths = [_][]const u8{ "/usr/lib", "/usr/local/lib", "." };
    const joined = try joinPath(&paths, std.testing.allocator);
    defer std.testing.allocator.free(joined);

    try std.testing.expectEqualStrings("/usr/lib:/usr/local/lib:.", joined);
}

test "pyvenv config parse" {
    const content =
        \\home = /usr/bin
        \\include-system-site-packages = true
        \\version = 3.13.0
    ;

    const config = try PyVenvConfig.parse(content, std.testing.allocator);
    defer {
        if (config.home) |h| std.testing.allocator.free(h);
        if (config.version) |v| std.testing.allocator.free(v);
    }

    try std.testing.expect(config.home != null);
    try std.testing.expectEqualStrings("/usr/bin", config.home.?);
    try std.testing.expect(config.include_system_site_packages);
    try std.testing.expectEqualStrings("3.13.0", config.version.?);
}
