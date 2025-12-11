/// Python Configuration Structure
/// Mirrors cpython/Python/initconfig.c - PyConfig structure
///
/// This module defines the main PyConfig structure that holds all Python
/// interpreter configuration options including:
/// - Isolated mode options
/// - Parser and optimization settings
/// - Path configuration
/// - Environment variable handling
/// - Debug and profiling options

const std = @import("std");
const Allocator = std.mem.Allocator;

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
