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

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// System Configuration
// ============================================================================

/// Thread-local int_max_str_digits limit (default 4300 in CPython 3.11+)
/// Controls the maximum digits for int/str conversions to prevent DoS
var int_max_str_digits: i64 = 4300;

/// Recursion limit (default 1000 in CPython)
var recursion_limit: u32 = 1000;

/// Switch interval for thread switching (seconds)
var switch_interval: f64 = 0.005;

/// Interactive mode flag
var is_interactive: bool = false;

// ============================================================================
// Version Information
// ============================================================================

/// Python version tuple (major, minor, micro, release, serial)
pub const version_info = struct {
    major: u32 = 3,
    minor: u32 = 12,
    micro: u32 = 0,
    releaselevel: []const u8 = "final",
    serial: u32 = 0,

    pub fn toTuple(self: @This()) struct { u32, u32, u32, []const u8, u32 } {
        return .{ self.major, self.minor, self.micro, self.releaselevel, self.serial };
    }
};

/// Version string
pub const version: []const u8 = "3.12.0 (metal0)";

/// Implementation info
pub const implementation = struct {
    name: []const u8 = "metal0",
    version: []const u8 = "0.1.0",
    cache_tag: []const u8 = "metal0-312",
    _multiarch: []const u8 = "",
};

/// Platform identifier
pub const platform: []const u8 = switch (builtin.os.tag) {
    .linux => "linux",
    .macos => "darwin",
    .windows => "win32",
    .freebsd => "freebsd",
    .openbsd => "openbsd",
    .netbsd => "netbsd",
    else => "unknown",
};

/// Byte order
pub const byteorder: []const u8 = if (builtin.cpu.arch.endian() == .little) "little" else "big";

/// Maximum integer value for Py_ssize_t
pub const maxsize: i64 = std.math.maxInt(i64);

/// Float information
pub const float_info = struct {
    max: f64 = std.math.floatMax(f64),
    max_exp: i32 = 1024,
    max_10_exp: i32 = 308,
    min: f64 = std.math.floatMin(f64),
    min_exp: i32 = -1021,
    min_10_exp: i32 = -307,
    dig: i32 = 15,
    mant_dig: i32 = 53,
    epsilon: f64 = std.math.floatEps(f64),
    radix: i32 = 2,
    rounds: i32 = 1, // Round to nearest
};

/// Int info
pub const int_info = struct {
    bits_per_digit: i32 = 30,
    sizeof_digit: i32 = 4,
    default_max_str_digits: i32 = 4300,
    str_digits_check_threshold: i32 = 640,
};

/// Hash info
pub const hash_info = struct {
    width: i32 = 64,
    modulus: i64 = (1 << 61) - 1, // 2^61 - 1 (Mersenne prime)
    inf: i64 = 314159,
    nan: i64 = 0,
    imag: i64 = 1000003,
    algorithm: []const u8 = "siphash24",
    hash_bits: i32 = 64,
    seed_bits: i32 = 128,
};

// ============================================================================
// Path and Module Search
// ============================================================================

/// Module search path (initialized at runtime)
threadlocal var path_storage: [256][]const u8 = undefined;
threadlocal var path_len: usize = 0;

/// Prefix for installed files
pub const prefix: []const u8 = "/usr/local";

/// Exec prefix for platform-specific files
pub const exec_prefix: []const u8 = "/usr/local";

/// Base prefix (same as prefix unless in venv)
pub const base_prefix: []const u8 = "/usr/local";

/// Base exec prefix
pub const base_exec_prefix: []const u8 = "/usr/local";

/// Get the module search path
pub fn getPath() []const []const u8 {
    return path_storage[0..path_len];
}

/// Set the module search path
pub fn setPath(paths: []const []const u8) void {
    const copy_len = @min(paths.len, path_storage.len);
    for (paths[0..copy_len], 0..) |p, i| {
        path_storage[i] = p;
    }
    path_len = copy_len;
}

/// Add a path to sys.path
pub fn addPath(new_path: []const u8) !void {
    if (path_len >= path_storage.len) {
        return error.PathStorageFull;
    }
    path_storage[path_len] = new_path;
    path_len += 1;
}

// ============================================================================
// Command Line Arguments
// ============================================================================

/// Command line arguments storage
threadlocal var argv_storage: [256][]const u8 = undefined;
threadlocal var argv_len: usize = 0;

/// Get sys.argv
pub fn getArgv() []const []const u8 {
    return argv_storage[0..argv_len];
}

/// Set sys.argv
pub fn setArgv(args: []const []const u8) void {
    const copy_len = @min(args.len, argv_storage.len);
    for (args[0..copy_len], 0..) |arg, i| {
        argv_storage[i] = arg;
    }
    argv_len = copy_len;
}

// ============================================================================
// Standard IO Streams
// ============================================================================

/// Standard input (as file descriptor for now)
pub const stdin_fd: std.fs.File = std.io.getStdIn();

/// Standard output
pub const stdout_fd: std.fs.File = std.io.getStdOut();

/// Standard error
pub const stderr_fd: std.fs.File = std.io.getStdErr();

/// Write to stdout
pub fn stdout_write(data: []const u8) !void {
    try stdout_fd.writeAll(data);
}

/// Write to stderr
pub fn stderr_write(data: []const u8) !void {
    try stderr_fd.writeAll(data);
}

// ============================================================================
// Exit and Exception Handling
// ============================================================================

/// Exit the program with the given status code
/// Mirrors: sys.exit()
pub fn exit(status: anytype) noreturn {
    const code: u8 = switch (@typeInfo(@TypeOf(status))) {
        .int, .comptime_int => @intCast(@min(255, @max(0, status))),
        .optional => if (status) |s| @intCast(@min(255, @max(0, s))) else 0,
        else => 0,
    };
    std.process.exit(code);
}

/// Get last exception info (type, value, traceback)
/// Mirrors: sys.exc_info()
pub fn exc_info() struct { ?[]const u8, ?[]const u8, ?[]const u8 } {
    const errors = @import("errors.zig");
    const fetched = errors.fetch();
    return .{ fetched.type_name, fetched.value, fetched.traceback };
}

/// Get current exception (Python 3.11+ style)
/// Mirrors: sys.exception()
pub fn exception() ?[]const u8 {
    const errors = @import("errors.zig");
    return errors.occurredType();
}

// ============================================================================
// Recursion and Threading
// ============================================================================

/// Get the recursion limit
/// Mirrors: sys.getrecursionlimit()
pub fn getrecursionlimit() u32 {
    return recursion_limit;
}

/// Set the recursion limit
/// Mirrors: sys.setrecursionlimit()
pub fn setrecursionlimit(limit: u32) !void {
    if (limit < 1) {
        return error.ValueError;
    }
    recursion_limit = limit;
}

/// Get the thread switch interval
/// Mirrors: sys.getswitchinterval()
pub fn getswitchinterval() f64 {
    return switch_interval;
}

/// Set the thread switch interval
/// Mirrors: sys.setswitchinterval()
pub fn setswitchinterval(interval: f64) !void {
    if (interval <= 0) {
        return error.ValueError;
    }
    switch_interval = interval;
}

// ============================================================================
// Int/String Conversion Limits
// ============================================================================

/// Get the maximum number of digits for int/str conversions
/// Mirrors: sys.get_int_max_str_digits()
pub fn get_int_max_str_digits(_: anytype) !i64 {
    return int_max_str_digits;
}

/// Set the maximum number of digits for int/str conversions
/// Mirrors: sys.set_int_max_str_digits()
pub fn set_int_max_str_digits(_: anytype, limit: i64) !void {
    if (limit != 0 and limit < 640) {
        return error.ValueError; // CPython minimum is 640
    }
    int_max_str_digits = limit;
}

// ============================================================================
// Object Size and Reference Count
// ============================================================================

/// Get the size of an object in bytes
/// Mirrors: sys.getsizeof()
pub fn getsizeof(comptime T: type) usize {
    return @sizeOf(T);
}

/// Get the reference count of an object (always 1 in AOT Zig)
/// Mirrors: sys.getrefcount()
pub fn getrefcount(_: anytype) u64 {
    // In AOT compiled code without GC, everything is either
    // stack-allocated or has a single owner
    return 1;
}

// ============================================================================
// Interning
// ============================================================================

/// Intern a string (no-op in AOT - strings are compile-time)
/// Mirrors: sys.intern()
pub fn intern(s: []const u8) []const u8 {
    return s;
}

// ============================================================================
// Tracing and Profiling Hooks
// ============================================================================

/// Profile function type
pub const ProfileFunc = *const fn (frame: anytype, event: []const u8, arg: anytype) void;

/// Trace function type
pub const TraceFunc = *const fn (frame: anytype, event: []const u8, arg: anytype) void;

/// Current profile function (null = disabled)
var profile_func: ?ProfileFunc = null;

/// Current trace function (null = disabled)
var trace_func: ?TraceFunc = null;

/// Set the profile function
/// Mirrors: sys.setprofile()
pub fn setprofile(func: ?ProfileFunc) void {
    profile_func = func;
}

/// Get the profile function
/// Mirrors: sys.getprofile()
pub fn getprofile() ?ProfileFunc {
    return profile_func;
}

/// Set the trace function
/// Mirrors: sys.settrace()
pub fn settrace(func: ?TraceFunc) void {
    trace_func = func;
}

/// Get the trace function
/// Mirrors: sys.gettrace()
pub fn gettrace() ?TraceFunc {
    return trace_func;
}

// ============================================================================
// Flags and Configuration
// ============================================================================

/// System flags (read-only configuration)
pub const flags = struct {
    debug: bool = false,
    inspect: bool = false,
    interactive: bool = false,
    optimize: i32 = 0,
    dont_write_bytecode: bool = true, // AOT doesn't write .pyc
    no_user_site: bool = false,
    no_site: bool = false,
    ignore_environment: bool = false,
    verbose: i32 = 0,
    bytes_warning: i32 = 0,
    quiet: bool = false,
    hash_randomization: bool = true,
    isolated: bool = false,
    dev_mode: bool = false,
    utf8_mode: bool = true,
    warn_default_encoding: bool = false,
    safe_path: bool = false,
    int_max_str_digits: i32 = 4300,
};

// ============================================================================
// Special Values
// ============================================================================

/// Displayhook for interactive output
pub fn displayhook(value: anytype) void {
    if (@TypeOf(value) == void) return;
    const stdout = std.io.getStdOut().writer();
    stdout.print("{any}\n", .{value}) catch {};
}

/// Excepthook for unhandled exceptions
pub fn excepthook(exc_type: []const u8, exc_value: []const u8, exc_tb: ?[]const u8) void {
    const stderr = std.io.getStdErr().writer();
    if (exc_tb) |tb| {
        stderr.print("Traceback (most recent call last):\n{s}\n", .{tb}) catch {};
    }
    stderr.print("{s}: {s}\n", .{ exc_type, exc_value }) catch {};
}

// ============================================================================
// Module Loading Info
// ============================================================================

/// Dictionary of loaded modules (names only for now)
threadlocal var modules_storage: [1024][]const u8 = undefined;
threadlocal var modules_len: usize = 0;

/// Get list of loaded module names
pub fn getModules() []const []const u8 {
    return modules_storage[0..modules_len];
}

/// Register a module as loaded
pub fn registerModule(name: []const u8) !void {
    if (modules_len >= modules_storage.len) {
        return error.ModuleStorageFull;
    }
    modules_storage[modules_len] = name;
    modules_len += 1;
}

// ============================================================================
// Audit Events
// ============================================================================

/// Audit hook type
pub const AuditHook = *const fn (event: []const u8, args: anytype) void;

/// Registered audit hooks
var audit_hooks: [16]?AuditHook = [_]?AuditHook{null} ** 16;
var audit_hook_count: usize = 0;

/// Add an audit hook
/// Mirrors: sys.addaudithook()
pub fn addaudithook(hook: AuditHook) !void {
    if (audit_hook_count >= audit_hooks.len) {
        return error.TooManyAuditHooks;
    }
    audit_hooks[audit_hook_count] = hook;
    audit_hook_count += 1;
}

/// Trigger audit event
pub fn audit(event: []const u8, args: anytype) void {
    for (audit_hooks[0..audit_hook_count]) |maybe_hook| {
        if (maybe_hook) |hook| {
            hook(event, args);
        }
    }
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the sys module
pub fn init() void {
    // Initialize default paths
    path_storage[0] = "";
    path_storage[1] = ".";
    path_len = 2;

    // Initialize empty argv
    argv_len = 0;
}

/// Initialize sys module with command line args
pub fn initWithArgs(args: []const []const u8) void {
    init();
    setArgv(args);
}

// ============================================================================
// Tests
// ============================================================================

test "version info" {
    const v = version_info{};
    try std.testing.expectEqual(@as(u32, 3), v.major);
    try std.testing.expectEqual(@as(u32, 12), v.minor);
}

test "recursion limit" {
    try std.testing.expectEqual(@as(u32, 1000), getrecursionlimit());
    try setrecursionlimit(2000);
    try std.testing.expectEqual(@as(u32, 2000), getrecursionlimit());
    recursion_limit = 1000; // Reset
}

test "int max str digits" {
    try std.testing.expectEqual(@as(i64, 4300), try get_int_max_str_digits(.{}));
    try set_int_max_str_digits(.{}, 5000);
    try std.testing.expectEqual(@as(i64, 5000), try get_int_max_str_digits(.{}));

    // Test minimum limit
    const result = set_int_max_str_digits(.{}, 100);
    try std.testing.expectError(error.ValueError, result);

    int_max_str_digits = 4300; // Reset
}

test "path operations" {
    init();
    try std.testing.expect(path_len >= 2);

    try addPath("/custom/path");
    const paths = getPath();
    try std.testing.expectEqualStrings("/custom/path", paths[paths.len - 1]);
}
