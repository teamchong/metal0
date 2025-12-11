/// initconfig - Initialization Configuration
/// Mirrors cpython/Python/initconfig.c
///
/// This module handles Python interpreter configuration:
/// - PyConfig structure for full initialization
/// - Path configuration
/// - Module search paths
/// - Runtime options
///
/// Modular structure:
/// - widestring.zig - PyWideStringList for string lists
/// - config.zig - PyConfig structure and methods
/// - args_parser.zig - Command-line argument parsing
/// - status.zig - ConfigStatus enum
/// - global.zig - Global configuration state

const std = @import("std");

// Re-export submodules
pub const widestring = @import("initconfig/widestring.zig");
pub const config = @import("initconfig/config.zig");
pub const args_parser = @import("initconfig/args_parser.zig");
pub const status = @import("initconfig/status.zig");
pub const global = @import("initconfig/global.zig");

// Re-export commonly used types
pub const PyWideStringList = widestring.PyWideStringList;
pub const PyConfig = config.PyConfig;
pub const ConfigStatus = status.ConfigStatus;

// Re-export functions
pub const readArgs = args_parser.readArgs;
pub const parseXOption = args_parser.parseXOption;
pub const getConfig = global.getConfig;
pub const setConfig = global.setConfig;
pub const clearConfig = global.clearConfig;

// Initialization
pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "wide string list" {
    var list = PyWideStringList.init(std.testing.allocator);
    defer list.deinit();

    try list.append("hello");
    try list.append("world");

    try std.testing.expectEqual(@as(usize, 2), list.length());
    try std.testing.expectEqualStrings("hello", list.get(0).?);
    try std.testing.expectEqualStrings("world", list.get(1).?);
    try std.testing.expect(list.get(2) == null);
}

test "pyconfig init python" {
    const cfg = PyConfig.initPython(std.testing.allocator);
    try std.testing.expect(cfg.parse_argv);
    try std.testing.expect(!cfg.isolated);
    try std.testing.expect(cfg.use_environment);
    try std.testing.expect(cfg.site_import);
    try std.testing.expectEqual(@as(i32, 0), cfg.optimization_level);
}

test "pyconfig init isolated" {
    const cfg = PyConfig.initIsolated(std.testing.allocator);
    try std.testing.expect(!cfg.parse_argv);
    try std.testing.expect(cfg.isolated);
    try std.testing.expect(!cfg.use_environment);
    try std.testing.expect(!cfg.site_import);
}

test "pyconfig copy" {
    var orig = PyConfig.initPython(std.testing.allocator);
    orig.verbose = 2;
    orig.optimization_level = 1;

    const copied = orig.copy();
    try std.testing.expectEqual(@as(i32, 2), copied.verbose);
    try std.testing.expectEqual(@as(i32, 1), copied.optimization_level);
}

test "read args basic" {
    var cfg = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-v", "-O", "-B", "-q" };
    try readArgs(&cfg, &args);

    try std.testing.expectEqual(@as(i32, 1), cfg.verbose);
    try std.testing.expectEqual(@as(i32, 1), cfg.optimization_level);
    try std.testing.expect(!cfg.write_bytecode);
    try std.testing.expect(cfg.quiet);
}

test "read args isolated" {
    var cfg = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{"-I"};
    try readArgs(&cfg, &args);

    try std.testing.expect(cfg.isolated);
    try std.testing.expect(!cfg.use_environment);
    try std.testing.expect(!cfg.site_import);
}

test "read args run command" {
    var cfg = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-c", "print('hello')" };
    try readArgs(&cfg, &args);

    try std.testing.expect(cfg.run_command != null);
    try std.testing.expectEqualStrings("print('hello')", cfg.run_command.?);
}

test "read args run module" {
    var cfg = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-m", "http.server" };
    try readArgs(&cfg, &args);

    try std.testing.expect(cfg.run_module != null);
    try std.testing.expectEqualStrings("http.server", cfg.run_module.?);
}

test "parse x option" {
    var cfg = PyConfig.initPython(std.testing.allocator);

    try parseXOption(&cfg, "faulthandler");
    try std.testing.expect(cfg.faulthandler);

    try parseXOption(&cfg, "tracemalloc=10");
    try std.testing.expectEqual(@as(i32, 10), cfg.tracemalloc);

    try parseXOption(&cfg, "importtime");
    try std.testing.expect(cfg.import_time);
}
