//! CPython source: Lib/site.py
//!
//! Provides site-specific customization of the Python installation.
//! Automatically imported during initialization.
//!
//! Mirrors: CPython Lib/site.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const builtin = @import("builtin");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Module-level variables
// ============================================================================

/// List of site-packages directories
var PREFIXES: std.ArrayList([]const u8) = undefined;
/// Whether user site-packages are enabled
var ENABLE_USER_SITE: ?bool = null;
/// The user site-packages directory
var USER_SITE: ?[]const u8 = null;
/// The user base directory
var USER_BASE: ?[]const u8 = null;
/// sys.path - module search path (simulated)
var sys_path: std.ArrayList([]const u8) = undefined;
var sys_path_initialized: bool = false;

/// Get sys.path (initializes if needed)
pub fn getSysPath(allocator: std.mem.Allocator) *std.ArrayList([]const u8) {
    _ = allocator;
    if (!sys_path_initialized) {
        sys_path = .{};
        sys_path_initialized = true;
    }
    return &sys_path;
}

/// Add a path to sys.path if not already present
pub fn addToSysPath(allocator: std.mem.Allocator, path: []const u8) !void {
    const sp = getSysPath(allocator);
    // Check if already in path
    for (sp.items) |existing| {
        if (std.mem.eql(u8, existing, path)) return;
    }
    try sp.append(allocator, path);
}

// ============================================================================
// Site Initialization
// ============================================================================

/// Initialize the site module
pub fn main(allocator: std.mem.Allocator) void {
    PREFIXES = .{};

    // Add standard prefixes
    PREFIXES.append(allocator, "/usr/local") catch unreachable;
    PREFIXES.append(allocator, "/usr") catch unreachable;

    // Determine user directories
    if (std.posix.getenv("PYTHONUSERBASE")) |base| {
        USER_BASE = base;
    } else {
        USER_BASE = getDefaultUserBase(allocator);
    }

    // Check if user site should be enabled
    if (std.posix.getenv("PYTHONNOUSERSITE")) |_| {
        ENABLE_USER_SITE = false;
    } else {
        ENABLE_USER_SITE = true;
    }

    // Set user site directory
    if (USER_BASE) |base| {
        USER_SITE = getUserSitePackages(allocator, base) catch null;
    }
}

/// Get the default user base directory
fn getDefaultUserBase(allocator: std.mem.Allocator) ?[]const u8 {
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.local", .{home}) catch null;
    }
    return null;
}

/// Get user site-packages path from base
fn getUserSitePackages(allocator: std.mem.Allocator, user_base: []const u8) ![]const u8 {
    return switch (builtin.os.tag) {
        .macos => try std.fmt.allocPrint(
            allocator,
            "{s}/lib/python3.12/site-packages",
            .{user_base},
        ),
        .windows => try std.fmt.allocPrint(
            allocator,
            "{s}\\Python312\\site-packages",
            .{user_base},
        ),
        else => try std.fmt.allocPrint(
            allocator,
            "{s}/lib/python3.12/site-packages",
            .{user_base},
        ),
    };
}

// ============================================================================
// Site Packages Path Management
// ============================================================================

/// Add a site-packages directory to sys.path
pub fn addsitedir(allocator: std.mem.Allocator, sitedir: []const u8, known_paths: ?*hashmap_helper.StringHashMap(void)) !void {
    // Verify directory exists
    std.fs.cwd().access(sitedir, .{}) catch return;

    // Add to sys.path
    try addToSysPath(allocator, sitedir);

    // Track known paths to avoid duplicates
    if (known_paths) |kp| {
        try kp.put(sitedir, {});
    }

    // Process .pth files in the directory
    var dir = std.fs.cwd().openDir(sitedir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".pth")) {
            addpackage(allocator, sitedir, entry.name) catch {};
        }
    }
}

/// Get standard site-packages directories
pub fn getsitepackages(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result: std.ArrayList([]const u8) = .{};

    // Platform-specific site-packages locations
    switch (builtin.os.tag) {
        .linux, .macos => {
            try result.append(allocator, "/usr/local/lib/python3.12/site-packages");
            try result.append(allocator, "/usr/lib/python3.12/site-packages");
            try result.append(allocator, "/usr/lib/python3/dist-packages");
        },
        .windows => {
            try result.append(allocator, "C:\\Python312\\Lib\\site-packages");
        },
        else => {},
    }

    return result;
}

/// Get user site-packages directory
pub fn getusersitepackages() ?[]const u8 {
    return USER_SITE;
}

/// Check if running in a virtual environment
pub fn invenv() bool {
    // Check for virtual environment indicators
    if (std.posix.getenv("VIRTUAL_ENV")) |_| {
        return true;
    }
    // Check sys.prefix != sys.base_prefix (simplified)
    return false;
}

// ============================================================================
// Path Configuration File Processing
// ============================================================================

/// Process a .pth file and add paths to sys.path
pub fn addpackage(allocator: std.mem.Allocator, sitedir: []const u8, name: []const u8) !void {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ sitedir, name });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();

    var line_buf: [1024]u8 = undefined;
    var buf_stream = std.io.fixedBufferStream(&line_buf);
    _ = buf_stream;

    const reader = file.reader();

    while (true) {
        const line = reader.readUntilDelimiter(&line_buf, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return;
        };

        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Lines starting with 'import' are executed (skip in AOT context)
        if (std.mem.startsWith(u8, trimmed, "import ")) continue;

        // Resolve path relative to sitedir if not absolute
        if (std.fs.path.isAbsolute(trimmed)) {
            try addToSysPath(allocator, trimmed);
        } else {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ sitedir, trimmed });
            // Verify path exists before adding
            if (std.fs.cwd().access(full_path, .{})) |_| {
                try addToSysPath(allocator, full_path);
            } else |_| {
                allocator.free(full_path);
            }
        }
    }
}

// ============================================================================
// License and Copyright
// ============================================================================

/// Print license information
pub fn license() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("See https://docs.python.org/3/license.html\n", .{}) catch {};
}

/// Print copyright information
pub fn copyright() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("Copyright (c) 2001-2024 Python Software Foundation.\nAll Rights Reserved.\n", .{}) catch {};
}

/// Print credits
pub fn credits() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("Thanks to CWI, CNRI, BeOpen.com, Zope Corporation and a cast of thousands\nfor supporting Python development.\n", .{}) catch {};
}

// ============================================================================
// setquit - Set up quit/exit
// ============================================================================

/// Quitter object that provides quit() and exit() builtins
pub const Quitter = struct {
    name: []const u8,
    eof: []const u8,

    const Self = @This();

    pub fn init(name: []const u8, eof: []const u8) Self {
        return .{ .name = name, .eof = eof };
    }

    /// Called when quit() or exit() is invoked
    pub fn call(self: *const Self) noreturn {
        const stderr = std.io.getStdErr().writer();
        stderr.print("Use {s}() or {s} plus Return to exit.\n", .{ self.name, self.eof }) catch {};
        std.process.exit(0);
    }

    /// Representation for interactive mode
    pub fn repr(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Use {s}() or {s} to exit", .{ self.name, self.eof });
    }
};

/// Global quit and exit objects
var quit_obj: ?Quitter = null;
var exit_obj: ?Quitter = null;

/// Set up quit() and exit() builtins
pub fn setquit() void {
    // Determine EOF key based on platform
    const eof_char = switch (builtin.os.tag) {
        .windows => "Ctrl-Z",
        else => "Ctrl-D",
    };

    quit_obj = Quitter.init("quit", eof_char);
    exit_obj = Quitter.init("exit", eof_char);
}

/// Get the quit object
pub fn getQuit() ?*const Quitter {
    if (quit_obj) |*obj| return obj;
    return null;
}

/// Get the exit object
pub fn getExit() ?*const Quitter {
    if (exit_obj) |*obj| return obj;
    return null;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the site module (called automatically on import)
pub fn initWithAllocator(allocator: std.mem.Allocator) void {
    if (initialized) return;
    initialized = true;

    // Initialize sys.path
    _ = getSysPath(allocator);

    // Call main to set up site-packages
    main(allocator);
}

/// Initialize the site module (uses page allocator as fallback)
pub fn init() void {
    initWithAllocator(allocator_helper.fast_allocator);
}

/// Reset module state
pub fn reset() void {
    ENABLE_USER_SITE = null;
    USER_SITE = null;
    USER_BASE = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "invenv no venv" {
    // Clear VIRTUAL_ENV if set for testing
    const result = invenv();
    // Result depends on environment
    _ = result;
}

test "getsitepackages" {
    const allocator = std.testing.allocator;
    var paths = try getsitepackages(allocator);
    defer paths.deinit();

    // Should have at least one path
    try std.testing.expect(paths.items.len > 0);
}

test "getusersitepackages" {
    // May be null if not initialized
    _ = getusersitepackages();
}

test "getDefaultUserBase" {
    const allocator = std.testing.allocator;
    const base = getDefaultUserBase(allocator);
    if (base) |b| {
        defer allocator.free(b);
        try std.testing.expect(std.mem.indexOf(u8, b, ".local") != null);
    }
}

test "getUserSitePackages" {
    const allocator = std.testing.allocator;
    const site = getUserSitePackages(allocator, "/home/user/.local") catch null;
    if (site) |s| {
        defer allocator.free(s);
        try std.testing.expect(std.mem.indexOf(u8, s, "site-packages") != null);
    }
}
