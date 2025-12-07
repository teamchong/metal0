/// initconfig - Initialization Configuration
/// Mirrors cpython/Python/initconfig.c
///
/// This module handles Python interpreter configuration:
/// - PyConfig structure for full initialization
/// - Path configuration
/// - Module search paths
/// - Runtime options

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Wide String List
// ============================================================================

/// List of strings (for argv, path, etc.)
pub const PyWideStringList = struct {
    items: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .items = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    pub fn append(self: *Self, item: []const u8) !void {
        try self.items.append(item);
    }

    pub fn insert(self: *Self, index: usize, item: []const u8) !void {
        try self.items.insert(index, item);
    }

    pub fn clear(self: *Self) void {
        self.items.clearRetainingCapacity();
    }

    pub fn length(self: *const Self) usize {
        return self.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) ?[]const u8 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }
};

// ============================================================================
// Python Configuration
// ============================================================================

/// Full Python configuration
pub const PyConfig = struct {
    /// Config version
    _config_version: i32 = 1,

    /// Parse command-line arguments
    parse_argv: bool = true,

    // === Isolated mode options ===
    /// Isolated mode (-I)
    isolated: bool = false,
    /// Use environment variables
    use_environment: bool = true,
    /// Import site module
    site_import: bool = true,

    // === Byte warnings ===
    /// -b: bytes/str comparison warnings
    bytes_warning: i32 = 0,

    // === Warning options ===
    /// -W options
    warn_default_encoding: bool = false,

    // === Inspection mode ===
    /// -i: inspect mode
    inspect: bool = false,
    /// -I: interactive mode
    interactive: bool = false,

    // === Optimization ===
    /// -O level (0, 1, or 2)
    optimization_level: i32 = 0,

    // === Parser options ===
    /// Write .pyc files
    write_bytecode: bool = true,

    // === Verbosity ===
    /// -v: verbose mode
    verbose: i32 = 0,
    /// -q: quiet mode
    quiet: bool = false,

    // === Buffer mode ===
    /// -u: unbuffered I/O
    buffered_stdio: bool = true,

    // === Encoding ===
    /// Standard I/O encoding
    stdio_encoding: ?[]const u8 = null,
    /// Standard I/O error handling
    stdio_errors: ?[]const u8 = null,

    // === Hash seed ===
    /// Use hash randomization
    use_hash_seed: bool = false,
    /// Hash seed value
    hash_seed: u64 = 0,

    // === Fault handler ===
    /// -X faulthandler
    faulthandler: bool = false,

    // === Tracemalloc ===
    /// -X tracemalloc=N
    tracemalloc: i32 = 0,

    // === Import time ===
    /// -X importtime
    import_time: bool = false,

    // === Code object generation ===
    /// -X no_debug_ranges
    code_debug_ranges: bool = true,

    // === Perf support ===
    /// -X perf
    perf_profiling: bool = false,

    // === Paths ===
    /// Program name
    program_name: ?[]const u8 = null,
    /// Python home
    home: ?[]const u8 = null,
    /// Base prefix
    base_prefix: ?[]const u8 = null,
    /// Base exec prefix
    base_exec_prefix: ?[]const u8 = null,
    /// Prefix
    prefix: ?[]const u8 = null,
    /// Exec prefix
    exec_prefix: ?[]const u8 = null,
    /// Executable path
    executable: ?[]const u8 = null,
    /// Base executable
    base_executable: ?[]const u8 = null,

    // === PYC prefix ===
    /// Directory for .pyc files
    pycache_prefix: ?[]const u8 = null,

    // === Run mode ===
    /// -c command
    run_command: ?[]const u8 = null,
    /// -m module
    run_module: ?[]const u8 = null,
    /// Script filename
    run_filename: ?[]const u8 = null,

    // === Skip source ===
    /// -b: skip first line
    skip_source_first_line: bool = false,

    // === Safety ===
    /// -P: safe path mode
    safe_path: bool = false,

    // === Frozen modules ===
    /// -X frozen_modules
    use_frozen_modules: i32 = -1,

    // === Sys overwrite ===
    /// sys._base_executable
    sys_base_executable: ?[]const u8 = null,

    // === Allocator ===
    allocator: Allocator,

    const Self = @This();

    /// Create default configuration for Python
    pub fn initPython(allocator: Allocator) Self {
        return .{
            .parse_argv = true,
            .isolated = false,
            .use_environment = true,
            .site_import = true,
            .allocator = allocator,
        };
    }

    /// Create isolated configuration
    pub fn initIsolated(allocator: Allocator) Self {
        return .{
            .parse_argv = false,
            .isolated = true,
            .use_environment = false,
            .site_import = false,
            .allocator = allocator,
        };
    }

    /// Copy configuration
    pub fn copy(self: *const Self) Self {
        return self.*;
    }

    /// Clear configuration
    pub fn clear(self: *Self) void {
        // Reset to defaults
        self.* = initPython(self.allocator);
    }

    /// Set program name
    pub fn setProgramName(self: *Self, name: []const u8) void {
        self.program_name = name;
    }

    /// Set home directory
    pub fn setHome(self: *Self, path: []const u8) void {
        self.home = path;
    }

    /// Read configuration from environment
    pub fn readEnv(self: *Self) void {
        if (!self.use_environment) return;

        // PYTHONDONTWRITEBYTECODE
        if (std.posix.getenv("PYTHONDONTWRITEBYTECODE")) |_| {
            self.write_bytecode = false;
        }

        // PYTHONOPTIMIZE
        if (std.posix.getenv("PYTHONOPTIMIZE")) |val| {
            if (val.len > 0) {
                self.optimization_level = std.fmt.parseInt(i32, val, 10) catch 1;
            } else {
                self.optimization_level = 1;
            }
        }

        // PYTHONVERBOSE
        if (std.posix.getenv("PYTHONVERBOSE")) |val| {
            if (val.len > 0) {
                self.verbose = std.fmt.parseInt(i32, val, 10) catch 1;
            } else {
                self.verbose = 1;
            }
        }

        // PYTHONDEBUG
        if (std.posix.getenv("PYTHONDEBUG")) |_| {
            // Debug mode
        }

        // PYTHONHOME
        if (std.posix.getenv("PYTHONHOME")) |val| {
            self.home = val;
        }

        // PYTHONFAULTHANDLER
        if (std.posix.getenv("PYTHONFAULTHANDLER")) |_| {
            self.faulthandler = true;
        }

        // PYTHONTRACEMALLOC
        if (std.posix.getenv("PYTHONTRACEMALLOC")) |val| {
            self.tracemalloc = std.fmt.parseInt(i32, val, 10) catch 1;
        }

        // PYTHONHASHSEED
        if (std.posix.getenv("PYTHONHASHSEED")) |val| {
            if (std.mem.eql(u8, val, "random")) {
                self.use_hash_seed = false;
            } else {
                self.use_hash_seed = true;
                self.hash_seed = std.fmt.parseInt(u64, val, 10) catch 0;
            }
        }
    }

    /// Validate configuration
    pub fn validate(self: *const Self) !void {
        // Check for conflicting options
        if (self.isolated and self.use_environment) {
            return error.ConflictingOptions;
        }

        // Validate optimization level
        if (self.optimization_level < 0 or self.optimization_level > 2) {
            return error.InvalidOptimizationLevel;
        }
    }
};

// ============================================================================
// Configuration Status
// ============================================================================

/// Configuration read status
pub const ConfigStatus = enum {
    ok,
    error_init,
    error_read,
    error_validate,
    exit,
};

// ============================================================================
// Configuration Functions
// ============================================================================

/// Read configuration from command-line arguments
pub fn readArgs(config: *PyConfig, args: []const []const u8) !void {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-b")) {
            config.bytes_warning += 1;
        } else if (std.mem.eql(u8, arg, "-B")) {
            config.write_bytecode = false;
        } else if (std.mem.eql(u8, arg, "-c")) {
            if (i + 1 < args.len) {
                i += 1;
                config.run_command = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-E")) {
            config.use_environment = false;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            // Help requested
        } else if (std.mem.eql(u8, arg, "-i")) {
            config.inspect = true;
            config.interactive = true;
        } else if (std.mem.eql(u8, arg, "-I")) {
            config.isolated = true;
            config.use_environment = false;
            config.site_import = false;
        } else if (std.mem.eql(u8, arg, "-m")) {
            if (i + 1 < args.len) {
                i += 1;
                config.run_module = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-O")) {
            config.optimization_level = @min(config.optimization_level + 1, 2);
        } else if (std.mem.eql(u8, arg, "-OO")) {
            config.optimization_level = 2;
        } else if (std.mem.eql(u8, arg, "-P")) {
            config.safe_path = true;
        } else if (std.mem.eql(u8, arg, "-q")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "-s")) {
            // Skip user site
        } else if (std.mem.eql(u8, arg, "-S")) {
            config.site_import = false;
        } else if (std.mem.eql(u8, arg, "-u")) {
            config.buffered_stdio = false;
        } else if (std.mem.eql(u8, arg, "-v")) {
            config.verbose += 1;
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            // Version requested
        } else if (std.mem.startsWith(u8, arg, "-W")) {
            // Warning option
        } else if (std.mem.startsWith(u8, arg, "-X")) {
            // Extended option
            if (i + 1 < args.len) {
                i += 1;
                const xopt = args[i];
                try parseXOption(config, xopt);
            }
        }
    }
}

/// Parse -X option
fn parseXOption(config: *PyConfig, opt: []const u8) !void {
    if (std.mem.eql(u8, opt, "faulthandler")) {
        config.faulthandler = true;
    } else if (std.mem.startsWith(u8, opt, "tracemalloc")) {
        if (std.mem.indexOf(u8, opt, "=")) |eq_pos| {
            const val = opt[eq_pos + 1 ..];
            config.tracemalloc = std.fmt.parseInt(i32, val, 10) catch 1;
        } else {
            config.tracemalloc = 1;
        }
    } else if (std.mem.eql(u8, opt, "importtime")) {
        config.import_time = true;
    } else if (std.mem.eql(u8, opt, "dev")) {
        // Dev mode
        config.faulthandler = true;
    } else if (std.mem.eql(u8, opt, "utf8")) {
        // UTF-8 mode
    } else if (std.mem.eql(u8, opt, "no_debug_ranges")) {
        config.code_debug_ranges = false;
    } else if (std.mem.eql(u8, opt, "perf")) {
        config.perf_profiling = true;
    } else if (std.mem.startsWith(u8, opt, "frozen_modules")) {
        if (std.mem.indexOf(u8, opt, "=")) |eq_pos| {
            const val = opt[eq_pos + 1 ..];
            if (std.mem.eql(u8, val, "on")) {
                config.use_frozen_modules = 1;
            } else if (std.mem.eql(u8, val, "off")) {
                config.use_frozen_modules = 0;
            }
        }
    }
}

// ============================================================================
// Global Configuration
// ============================================================================

var g_config: ?PyConfig = null;

/// Get global configuration
pub fn getConfig() ?*PyConfig {
    if (g_config) |*config| {
        return config;
    }
    return null;
}

/// Set global configuration
pub fn setConfig(config: *const PyConfig) void {
    g_config = config.*;
}

/// Clear global configuration
pub fn clearConfig() void {
    g_config = null;
}

// ============================================================================
// Initialization
// ============================================================================

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
    const config = PyConfig.initPython(std.testing.allocator);
    try std.testing.expect(config.parse_argv);
    try std.testing.expect(!config.isolated);
    try std.testing.expect(config.use_environment);
    try std.testing.expect(config.site_import);
    try std.testing.expectEqual(@as(i32, 0), config.optimization_level);
}

test "pyconfig init isolated" {
    const config = PyConfig.initIsolated(std.testing.allocator);
    try std.testing.expect(!config.parse_argv);
    try std.testing.expect(config.isolated);
    try std.testing.expect(!config.use_environment);
    try std.testing.expect(!config.site_import);
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
    var config = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-v", "-O", "-B", "-q" };
    try readArgs(&config, &args);

    try std.testing.expectEqual(@as(i32, 1), config.verbose);
    try std.testing.expectEqual(@as(i32, 1), config.optimization_level);
    try std.testing.expect(!config.write_bytecode);
    try std.testing.expect(config.quiet);
}

test "read args isolated" {
    var config = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{"-I"};
    try readArgs(&config, &args);

    try std.testing.expect(config.isolated);
    try std.testing.expect(!config.use_environment);
    try std.testing.expect(!config.site_import);
}

test "read args run command" {
    var config = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-c", "print('hello')" };
    try readArgs(&config, &args);

    try std.testing.expect(config.run_command != null);
    try std.testing.expectEqualStrings("print('hello')", config.run_command.?);
}

test "read args run module" {
    var config = PyConfig.initPython(std.testing.allocator);

    const args = [_][]const u8{ "-m", "http.server" };
    try readArgs(&config, &args);

    try std.testing.expect(config.run_module != null);
    try std.testing.expectEqualStrings("http.server", config.run_module.?);
}

test "parse x option" {
    var config = PyConfig.initPython(std.testing.allocator);

    try parseXOption(&config, "faulthandler");
    try std.testing.expect(config.faulthandler);

    try parseXOption(&config, "tracemalloc=10");
    try std.testing.expectEqual(@as(i32, 10), config.tracemalloc);

    try parseXOption(&config, "importtime");
    try std.testing.expect(config.import_time);
}
