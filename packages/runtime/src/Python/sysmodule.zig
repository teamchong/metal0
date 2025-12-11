/// sysmodule - sys Module Implementation
/// Mirrors cpython/Python/sysmodule.c
///
/// The sys module provides access to interpreter state and configuration:
/// - argv: Command line arguments
/// - path: Module search path
/// - stdin/stdout/stderr: Standard IO streams
/// - version info: Python version and implementation details
/// - Platform info: OS, byteorder, etc.
/// - Exit/exception handling
/// - Memory management settings

// ============================================================================
// Submodule Organization
// ============================================================================
// This module is split into logical submodules:
// - config: System configuration variables and limits
// - version: Version information and platform details
// - paths: Path and module search functionality
// - args: Command line arguments handling
// - stdio: Standard IO streams
// - control: Exit and exception handling
// - limits: Recursion, threading, and conversion limits
// - introspection: Object size, reference count, interning
// - hooks: Tracing, profiling, and audit hooks
// - modules: Module loading info and initialization

const config = @import("sysmodule/config.zig");
const version = @import("sysmodule/version.zig");
const paths = @import("sysmodule/paths.zig");
const args = @import("sysmodule/args.zig");
const stdio = @import("sysmodule/stdio.zig");
const control = @import("sysmodule/control.zig");
const limits = @import("sysmodule/limits.zig");
const introspection = @import("sysmodule/introspection.zig");
const hooks = @import("sysmodule/hooks.zig");
const modules = @import("sysmodule/modules.zig");

// ============================================================================
// Re-exports: Configuration
// ============================================================================

pub const int_max_str_digits = &config.int_max_str_digits;
pub const recursion_limit = &config.recursion_limit;
pub const switch_interval = &config.switch_interval;
pub const is_interactive = &config.is_interactive;
pub const flags = config.flags;

// ============================================================================
// Re-exports: Version Information
// ============================================================================

pub const version_info = version.version_info;
pub const version = version.version;
pub const implementation = version.implementation;
pub const platform = version.platform;
pub const byteorder = version.byteorder;
pub const maxsize = version.maxsize;
pub const float_info = version.float_info;
pub const int_info = version.int_info;
pub const hash_info = version.hash_info;

// ============================================================================
// Re-exports: Path Management
// ============================================================================

pub const prefix = paths.prefix;
pub const exec_prefix = paths.exec_prefix;
pub const base_prefix = paths.base_prefix;
pub const base_exec_prefix = paths.base_exec_prefix;
pub const getPath = paths.getPath;
pub const setPath = paths.setPath;
pub const addPath = paths.addPath;

// ============================================================================
// Re-exports: Arguments
// ============================================================================

pub const getArgv = args.getArgv;
pub const setArgv = args.setArgv;

// ============================================================================
// Re-exports: Standard IO
// ============================================================================

pub const stdin_fd = stdio.stdin_fd;
pub const stdout_fd = stdio.stdout_fd;
pub const stderr_fd = stdio.stderr_fd;
pub const stdout_write = stdio.stdout_write;
pub const stderr_write = stdio.stderr_write;
pub const displayhook = stdio.displayhook;
pub const excepthook = stdio.excepthook;

// ============================================================================
// Re-exports: Control Flow
// ============================================================================

pub const exit = control.exit;
pub const exc_info = control.exc_info;
pub const exception = control.exception;

// ============================================================================
// Re-exports: Limits
// ============================================================================

pub const getrecursionlimit = limits.getrecursionlimit;
pub const setrecursionlimit = limits.setrecursionlimit;
pub const getswitchinterval = limits.getswitchinterval;
pub const setswitchinterval = limits.setswitchinterval;
pub const get_int_max_str_digits = limits.get_int_max_str_digits;
pub const set_int_max_str_digits = limits.set_int_max_str_digits;

// ============================================================================
// Re-exports: Introspection
// ============================================================================

pub const getsizeof = introspection.getsizeof;
pub const getrefcount = introspection.getrefcount;
pub const intern = introspection.intern;

// ============================================================================
// Re-exports: Hooks
// ============================================================================

pub const ProfileFunc = hooks.ProfileFunc;
pub const TraceFunc = hooks.TraceFunc;
pub const AuditHook = hooks.AuditHook;
pub const setprofile = hooks.setprofile;
pub const getprofile = hooks.getprofile;
pub const settrace = hooks.settrace;
pub const gettrace = hooks.gettrace;
pub const addaudithook = hooks.addaudithook;
pub const audit = hooks.audit;

// ============================================================================
// Re-exports: Module Management
// ============================================================================

pub const getModules = modules.getModules;
pub const registerModule = modules.registerModule;
pub const init = modules.init;
pub const initWithArgs = modules.initWithArgs;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "version info" {
    const v = version_info{};
    try std.testing.expectEqual(@as(u32, 3), v.major);
    try std.testing.expectEqual(@as(u32, 12), v.minor);
}

test "recursion limit" {
    try std.testing.expectEqual(@as(u32, 1000), getrecursionlimit());
    try setrecursionlimit(2000);
    try std.testing.expectEqual(@as(u32, 2000), getrecursionlimit());
    config.recursion_limit = 1000; // Reset
}

test "int max str digits" {
    try std.testing.expectEqual(@as(i64, 4300), try get_int_max_str_digits(.{}));
    try set_int_max_str_digits(.{}, 5000);
    try std.testing.expectEqual(@as(i64, 5000), try get_int_max_str_digits(.{}));

    // Test minimum limit
    const result = set_int_max_str_digits(.{}, 100);
    try std.testing.expectError(error.ValueError, result);

    config.int_max_str_digits = 4300; // Reset
}

test "path operations" {
    init();
    const test_paths = getPath();
    try std.testing.expect(test_paths.len >= 2);

    try addPath("/custom/path");
    const updated_paths = getPath();
    try std.testing.expectEqualStrings("/custom/path", updated_paths[updated_paths.len - 1]);
}
