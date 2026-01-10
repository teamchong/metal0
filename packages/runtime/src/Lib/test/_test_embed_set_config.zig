//! test._test_embed_set_config - Embed config tests
//! CPython Reference: https://docs.python.org/3.12/c-api/init_config.html
//!
//! This module provides tests for embedded Python configuration settings,
//! including PyConfig, PyPreConfig, and various initialization options
//! used when embedding Python in applications.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Configuration Status Types
// ============================================================================

/// Configuration initialization status
pub const ConfigStatus = enum(i32) {
    /// Configuration is valid
    ok = 0,
    /// Error occurred during configuration
    err = -1,
    /// Configuration needs more setup
    incomplete = 1,
    /// Exit requested (e.g., --help)
    exit = 2,
};

/// Memory allocator type for Python
pub const AllocatorType = enum(i32) {
    /// Not set (use default)
    not_set = -1,
    /// Default allocator
    default = 0,
    /// Debug allocator
    debug = 1,
    /// Malloc allocator
    malloc = 2,
    /// Malloc with debug
    malloc_debug = 3,
    /// PyMem allocator
    pymalloc = 4,
    /// PyMem with debug
    pymalloc_debug = 5,
};

/// UTF-8 mode setting
pub const Utf8Mode = enum(i32) {
    /// Not set (auto-detect)
    not_set = -1,
    /// Disabled
    disabled = 0,
    /// Enabled
    enabled = 1,
};

// ============================================================================
// PyPreConfig Structure
// ============================================================================

/// Pre-initialization configuration (matches CPython's PyPreConfig)
pub const PyPreConfig = struct {
    /// Configure memory allocator
    allocator: AllocatorType = .not_set,
    /// If true, use isolated mode
    isolated: bool = false,
    /// Parse PYTHONMALLOC environment variable
    use_environment: bool = true,
    /// Configure locale encoding
    configure_locale: bool = true,
    /// Coerce C locale to UTF-8
    coerce_c_locale: bool = false,
    /// Warn if C locale coercion is required
    coerce_c_locale_warn: bool = false,
    /// UTF-8 mode
    utf8_mode: Utf8Mode = .not_set,
    /// Development mode
    dev_mode: bool = false,

    const Self = @This();

    /// Initialize with isolated configuration
    pub fn initIsolatedConfig() Self {
        return .{
            .isolated = true,
            .use_environment = false,
            .configure_locale = false,
        };
    }

    /// Initialize with Python configuration
    pub fn initPythonConfig() Self {
        return .{
            .isolated = false,
            .use_environment = true,
            .configure_locale = true,
        };
    }

    /// Validate configuration
    pub fn validate(self: *const Self) ConfigStatus {
        // Isolated mode should disable environment
        if (self.isolated and self.use_environment) {
            return .incomplete;
        }
        return .ok;
    }
};

// ============================================================================
// PyConfig Structure
// ============================================================================

/// Main Python configuration structure (matches CPython's PyConfig)
pub const PyConfig = struct {
    // Basic settings
    /// Configuration status
    status: ConfigStatus = .incomplete,
    /// Use isolated mode
    isolated: bool = false,
    /// Use environment variables
    use_environment: bool = true,
    /// Development mode
    dev_mode: bool = false,
    /// Install signal handlers
    install_signal_handlers: bool = true,
    /// Use hash randomization
    use_hash_seed: bool = false,
    /// Hash seed value (if use_hash_seed is true)
    hash_seed: u64 = 0,
    /// Fault handler enabled
    faulthandler: bool = false,

    // Memory settings
    /// Tracemalloc allocation tracing
    tracemalloc: i32 = 0,
    /// Import time profiling
    import_time: bool = false,
    /// Code object allocation limit
    code_debug_ranges: bool = true,
    /// Show reference counts at exit
    show_ref_count: bool = false,
    /// Dump references at exit
    dump_refs: bool = false,

    // Path settings
    /// Python home directory
    home: ?[]const u8 = null,
    /// Module search paths
    module_search_paths: ?[]const []const u8 = null,
    /// Module search paths configured flag
    module_search_paths_set: bool = false,
    /// Executable path
    executable: ?[]const u8 = null,
    /// Base executable path
    base_executable: ?[]const u8 = null,
    /// Prefix path
    prefix: ?[]const u8 = null,
    /// Base prefix path
    base_prefix: ?[]const u8 = null,
    /// Exec prefix path
    exec_prefix: ?[]const u8 = null,
    /// Base exec prefix path
    base_exec_prefix: ?[]const u8 = null,
    /// Pycache prefix
    pycache_prefix: ?[]const u8 = null,

    // Interpreter settings
    /// Interactive mode
    interactive: bool = false,
    /// Optimization level (0-2)
    optimization_level: u8 = 0,
    /// Parser debug mode
    parser_debug: bool = false,
    /// Write bytecode files
    write_bytecode: bool = true,
    /// Verbose import messages
    verbose: i32 = 0,
    /// Quiet mode
    quiet: bool = false,
    /// User site directory enabled
    user_site_directory: bool = true,
    /// Configure C stdio streams
    configure_c_stdio: bool = true,
    /// Buffered stdio mode
    buffered_stdio: bool = true,

    // Encoding settings
    /// Standard stream encoding
    stdio_encoding: ?[]const u8 = null,
    /// Standard stream error handler
    stdio_errors: ?[]const u8 = null,
    /// Filesystem encoding
    filesystem_encoding: ?[]const u8 = null,
    /// Filesystem error handler
    filesystem_errors: ?[]const u8 = null,

    // Warning settings
    /// Warning options
    warnoptions: ?[]const []const u8 = null,
    /// Warning default filter
    warn_default_encoding: bool = false,

    // Safety settings
    /// Bytes warning level (0-2)
    bytes_warning: u8 = 0,
    /// Int max string digits (0 = no limit)
    int_max_str_digits: i32 = 4300,
    /// Safe path mode
    safe_path: bool = false,

    // Run settings
    /// Path to run as script
    run_filename: ?[]const u8 = null,
    /// Command to run (-c)
    run_command: ?[]const u8 = null,
    /// Module to run (-m)
    run_module: ?[]const u8 = null,

    // Startup settings
    /// Don't add user site directory
    no_user_site: bool = false,
    /// Don't run site.py
    no_site: bool = false,
    /// Ignore PYTHON* environment variables
    ignore_environment: bool = false,

    /// Command line arguments
    argv: ?[]const []const u8 = null,
    /// Original command line arguments
    orig_argv: ?[]const []const u8 = null,

    // Extended settings
    /// Import site module
    site_import: bool = true,
    /// Path configuration enabled
    pathconfig_warnings: bool = true,
    /// Python path environment variable
    pythonpath_env: ?[]const u8 = null,
    /// Stdlib directory
    stdlib_dir: ?[]const u8 = null,

    const Self = @This();

    /// Initialize with isolated configuration
    pub fn initIsolatedConfig() Self {
        return .{
            .isolated = true,
            .use_environment = false,
            .user_site_directory = false,
            .dev_mode = false,
            .install_signal_handlers = false,
            .site_import = false,
        };
    }

    /// Initialize with Python configuration
    pub fn initPythonConfig() Self {
        return .{
            .isolated = false,
            .use_environment = true,
            .user_site_directory = true,
            .dev_mode = false,
            .install_signal_handlers = true,
            .site_import = true,
        };
    }

    /// Validate configuration
    pub fn validate(self: *Self) ConfigStatus {
        // Check for conflicting settings
        if (self.isolated) {
            if (self.use_environment) return .incomplete;
            if (self.user_site_directory) return .incomplete;
        }

        // Check optimization level
        if (self.optimization_level > 2) {
            return .err;
        }

        // Check bytes warning level
        if (self.bytes_warning > 2) {
            return .err;
        }

        // Check int max str digits
        if (self.int_max_str_digits < 0 and self.int_max_str_digits != -1) {
            return .err;
        }
        if (self.int_max_str_digits > 0 and self.int_max_str_digits < 640) {
            return .err;
        }

        self.status = .ok;
        return .ok;
    }

    /// Apply pre-configuration settings
    pub fn applyPreConfig(self: *Self, preconfig: *const PyPreConfig) void {
        self.isolated = preconfig.isolated;
        self.use_environment = preconfig.use_environment;
        self.dev_mode = preconfig.dev_mode;

        if (preconfig.utf8_mode == .enabled) {
            self.filesystem_encoding = "utf-8";
            self.filesystem_errors = "surrogateescape";
        }
    }

    /// Set path configuration
    pub fn setPath(self: *Self, allocator: std.mem.Allocator, paths: []const []const u8) !void {
        self.module_search_paths = try allocator.dupe([]const u8, paths);
        self.module_search_paths_set = true;
    }

    /// Clear path configuration
    pub fn clearPath(self: *Self, allocator: std.mem.Allocator) void {
        if (self.module_search_paths) |paths| {
            allocator.free(paths);
            self.module_search_paths = null;
        }
        self.module_search_paths_set = false;
    }

    /// Get effective optimization level
    pub fn effectiveOptLevel(self: *const Self) u8 {
        if (self.dev_mode) return 0;
        return self.optimization_level;
    }

    /// Check if running in restricted mode
    pub fn isRestricted(self: *const Self) bool {
        return self.isolated or self.safe_path or !self.user_site_directory;
    }
};

// ============================================================================
// Configuration Initialization Functions
// ============================================================================

/// Initialize pre-configuration
pub fn preConfigInit(preconfig: *PyPreConfig) ConfigStatus {
    preconfig.* = PyPreConfig{};
    return .ok;
}

/// Initialize pre-configuration for isolated mode
pub fn preConfigInitIsolated(preconfig: *PyPreConfig) ConfigStatus {
    preconfig.* = PyPreConfig.initIsolatedConfig();
    return .ok;
}

/// Initialize pre-configuration for Python mode
pub fn preConfigInitPython(preconfig: *PyPreConfig) ConfigStatus {
    preconfig.* = PyPreConfig.initPythonConfig();
    return .ok;
}

/// Initialize configuration
pub fn configInit(config: *PyConfig) ConfigStatus {
    config.* = PyConfig{};
    return .ok;
}

/// Initialize configuration for isolated mode
pub fn configInitIsolated(config: *PyConfig) ConfigStatus {
    config.* = PyConfig.initIsolatedConfig();
    return .ok;
}

/// Initialize configuration for Python mode
pub fn configInitPython(config: *PyConfig) ConfigStatus {
    config.* = PyConfig.initPythonConfig();
    return .ok;
}

// ============================================================================
// Configuration Read/Write
// ============================================================================

/// Configuration writer for serialization
pub const ConfigWriter = struct {
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn writeBool(self: *Self, name: []const u8, value: bool) !void {
        const writer = self.buffer.writer();
        try writer.print("{s}={s}\n", .{ name, if (value) "true" else "false" });
    }

    pub fn writeInt(self: *Self, name: []const u8, value: anytype) !void {
        const writer = self.buffer.writer();
        try writer.print("{s}={d}\n", .{ name, value });
    }

    pub fn writeString(self: *Self, name: []const u8, value: ?[]const u8) !void {
        const writer = self.buffer.writer();
        if (value) |v| {
            try writer.print("{s}={s}\n", .{ name, v });
        } else {
            try writer.print("{s}=\n", .{name});
        }
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
};

/// Serialize PyConfig to string
pub fn serializeConfig(allocator: std.mem.Allocator, config: *const PyConfig) ![]u8 {
    var writer = ConfigWriter.init(allocator);
    defer writer.deinit();

    try writer.writeBool("isolated", config.isolated);
    try writer.writeBool("use_environment", config.use_environment);
    try writer.writeBool("dev_mode", config.dev_mode);
    try writer.writeBool("install_signal_handlers", config.install_signal_handlers);
    try writer.writeBool("use_hash_seed", config.use_hash_seed);
    try writer.writeInt("hash_seed", config.hash_seed);
    try writer.writeBool("faulthandler", config.faulthandler);
    try writer.writeInt("tracemalloc", config.tracemalloc);
    try writer.writeBool("import_time", config.import_time);
    try writer.writeBool("interactive", config.interactive);
    try writer.writeInt("optimization_level", config.optimization_level);
    try writer.writeBool("parser_debug", config.parser_debug);
    try writer.writeBool("write_bytecode", config.write_bytecode);
    try writer.writeInt("verbose", config.verbose);
    try writer.writeBool("quiet", config.quiet);
    try writer.writeBool("user_site_directory", config.user_site_directory);
    try writer.writeBool("site_import", config.site_import);
    try writer.writeInt("bytes_warning", config.bytes_warning);
    try writer.writeInt("int_max_str_digits", config.int_max_str_digits);
    try writer.writeBool("safe_path", config.safe_path);
    try writer.writeString("home", config.home);
    try writer.writeString("executable", config.executable);
    try writer.writeString("prefix", config.prefix);
    try writer.writeString("run_filename", config.run_filename);
    try writer.writeString("run_command", config.run_command);
    try writer.writeString("run_module", config.run_module);

    return writer.toOwnedSlice();
}

// ============================================================================
// Test Cases
// ============================================================================

/// Test case for configuration validation
pub const ConfigTestCase = struct {
    name: []const u8,
    config: PyConfig,
    expected_status: ConfigStatus,
    expected_restricted: bool = false,
};

/// Standard test cases
pub const standard_test_cases = [_]ConfigTestCase{
    .{
        .name = "default_config",
        .config = PyConfig{},
        .expected_status = .ok,
    },
    .{
        .name = "isolated_config",
        .config = PyConfig.initIsolatedConfig(),
        .expected_status = .ok,
        .expected_restricted = true,
    },
    .{
        .name = "python_config",
        .config = PyConfig.initPythonConfig(),
        .expected_status = .ok,
    },
    .{
        .name = "invalid_opt_level",
        .config = PyConfig{ .optimization_level = 5 },
        .expected_status = .err,
    },
    .{
        .name = "invalid_bytes_warning",
        .config = PyConfig{ .bytes_warning = 5 },
        .expected_status = .err,
    },
    .{
        .name = "invalid_int_max_str_digits",
        .config = PyConfig{ .int_max_str_digits = 100 },
        .expected_status = .err,
    },
};

// ============================================================================
// Unit Tests
// ============================================================================

test "ConfigStatus values" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(ConfigStatus.ok));
    try std.testing.expectEqual(@as(i32, -1), @intFromEnum(ConfigStatus.err));
    try std.testing.expectEqual(@as(i32, 1), @intFromEnum(ConfigStatus.incomplete));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(ConfigStatus.exit));
}

test "AllocatorType values" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(AllocatorType.default));
    try std.testing.expectEqual(@as(i32, 1), @intFromEnum(AllocatorType.debug));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(AllocatorType.malloc));
}

test "PyPreConfig default initialization" {
    var preconfig = PyPreConfig{};
    try std.testing.expectEqual(AllocatorType.not_set, preconfig.allocator);
    try std.testing.expect(!preconfig.isolated);
    try std.testing.expect(preconfig.use_environment);
}

test "PyPreConfig isolated initialization" {
    const preconfig = PyPreConfig.initIsolatedConfig();
    try std.testing.expect(preconfig.isolated);
    try std.testing.expect(!preconfig.use_environment);
    try std.testing.expect(!preconfig.configure_locale);
}

test "PyPreConfig validation" {
    var isolated = PyPreConfig.initIsolatedConfig();
    try std.testing.expectEqual(ConfigStatus.ok, isolated.validate());

    var invalid = PyPreConfig{
        .isolated = true,
        .use_environment = true, // Conflict!
    };
    try std.testing.expectEqual(ConfigStatus.incomplete, invalid.validate());
}

test "PyConfig default initialization" {
    const config = PyConfig{};
    try std.testing.expectEqual(ConfigStatus.incomplete, config.status);
    try std.testing.expect(!config.isolated);
    try std.testing.expect(config.use_environment);
    try std.testing.expectEqual(@as(u8, 0), config.optimization_level);
}

test "PyConfig isolated initialization" {
    const config = PyConfig.initIsolatedConfig();
    try std.testing.expect(config.isolated);
    try std.testing.expect(!config.use_environment);
    try std.testing.expect(!config.user_site_directory);
    try std.testing.expect(!config.install_signal_handlers);
    try std.testing.expect(!config.site_import);
}

test "PyConfig python initialization" {
    const config = PyConfig.initPythonConfig();
    try std.testing.expect(!config.isolated);
    try std.testing.expect(config.use_environment);
    try std.testing.expect(config.user_site_directory);
    try std.testing.expect(config.install_signal_handlers);
    try std.testing.expect(config.site_import);
}

test "PyConfig validation" {
    var config = PyConfig.initPythonConfig();
    try std.testing.expectEqual(ConfigStatus.ok, config.validate());
    try std.testing.expectEqual(ConfigStatus.ok, config.status);

    var invalid = PyConfig{ .optimization_level = 5 };
    try std.testing.expectEqual(ConfigStatus.err, invalid.validate());
}

test "PyConfig isRestricted" {
    const isolated = PyConfig.initIsolatedConfig();
    try std.testing.expect(isolated.isRestricted());

    const python = PyConfig.initPythonConfig();
    try std.testing.expect(!python.isRestricted());

    const safe_path = PyConfig{ .safe_path = true };
    try std.testing.expect(safe_path.isRestricted());
}

test "PyConfig effectiveOptLevel" {
    var config = PyConfig{ .optimization_level = 2 };
    try std.testing.expectEqual(@as(u8, 2), config.effectiveOptLevel());

    config.dev_mode = true;
    try std.testing.expectEqual(@as(u8, 0), config.effectiveOptLevel());
}

test "PyConfig applyPreConfig" {
    var config = PyConfig{};
    const preconfig = PyPreConfig{
        .isolated = true,
        .use_environment = false,
        .dev_mode = true,
        .utf8_mode = .enabled,
    };

    config.applyPreConfig(&preconfig);

    try std.testing.expect(config.isolated);
    try std.testing.expect(!config.use_environment);
    try std.testing.expect(config.dev_mode);
    try std.testing.expectEqualStrings("utf-8", config.filesystem_encoding.?);
}

test "configInit functions" {
    var preconfig: PyPreConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, preConfigInit(&preconfig));

    var config: PyConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, configInit(&config));
}

test "configInitIsolated functions" {
    var preconfig: PyPreConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, preConfigInitIsolated(&preconfig));
    try std.testing.expect(preconfig.isolated);

    var config: PyConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, configInitIsolated(&config));
    try std.testing.expect(config.isolated);
}

test "configInitPython functions" {
    var preconfig: PyPreConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, preConfigInitPython(&preconfig));
    try std.testing.expect(!preconfig.isolated);

    var config: PyConfig = undefined;
    try std.testing.expectEqual(ConfigStatus.ok, configInitPython(&config));
    try std.testing.expect(!config.isolated);
}

test "ConfigWriter" {
    const allocator = std.testing.allocator;
    var writer = ConfigWriter.init(allocator);
    defer writer.deinit();

    try writer.writeBool("flag", true);
    try writer.writeInt("count", 42);
    try writer.writeString("name", "test");
    try writer.writeString("empty", null);

    const output = try writer.toOwnedSlice();
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "flag=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "count=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "name=test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "empty=\n") != null);
}

test "serializeConfig" {
    const allocator = std.testing.allocator;
    const config = PyConfig.initPythonConfig();

    const serialized = try serializeConfig(allocator, &config);
    defer allocator.free(serialized);

    try std.testing.expect(serialized.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "isolated=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "use_environment=true") != null);
}

test "standard test cases" {
    for (standard_test_cases) |tc| {
        var config = tc.config;
        const status = config.validate();
        try std.testing.expectEqual(tc.expected_status, status);

        if (tc.expected_status == .ok) {
            try std.testing.expectEqual(tc.expected_restricted, config.isRestricted());
        }
    }
}
