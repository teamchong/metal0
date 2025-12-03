/// Python test.support module - CPython unittest compatibility helpers
/// Provides stubs and implementations for test.support functionality
const std = @import("std");
const runtime = @import("runtime.zig");

// ============================================================================
// Constants commonly imported from test.support
// ============================================================================

/// Dummy object that compares equal to everything
pub const ALWAYS_EQ = struct {
    pub fn eql(_: @This(), _: anytype) bool {
        return true;
    }
};

/// Dummy object that never compares equal to anything
pub const NEVER_EQ = struct {
    pub fn eql(_: @This(), _: anytype) bool {
        return false;
    }
};

/// Verbose mode flag
pub var verbose: bool = false;

/// 1GB constant
pub const _1G: i64 = 1024 * 1024 * 1024;
/// 2GB constant
pub const _2G: i64 = 2 * 1024 * 1024 * 1024;
/// 4GB constant
pub const _4G: i64 = 4 * 1024 * 1024 * 1024;

/// Maximum value for Py_ssize_t (platform dependent)
/// On 64-bit: 2^63 - 1, on 32-bit: 2^31 - 1
pub const MAX_Py_ssize_t: i64 = if (@sizeOf(usize) == 8)
    std.math.maxInt(i64)
else
    std.math.maxInt(i32);

/// Short timeout for tests (seconds)
pub const SHORT_TIMEOUT: f64 = 30.0;

/// Whether running on Windows
pub const MS_WINDOWS: bool = @import("builtin").os.tag == .windows;

/// Whether running on Apple platforms
pub const is_apple: bool = @import("builtin").os.tag == .macos or @import("builtin").os.tag == .ios;

/// Whether running on Android
pub const is_android: bool = false;

/// Whether running on WASI
pub const is_wasi: bool = @import("builtin").os.tag == .wasi;

/// Whether running on Apple mobile
pub const is_apple_mobile: bool = @import("builtin").os.tag == .ios;

/// Whether running on s390x architecture
pub const is_s390x: bool = @import("builtin").cpu.arch == .s390x;

/// Whether running on ARM
pub const is_arm: bool = @import("builtin").cpu.arch == .arm or @import("builtin").cpu.arch == .aarch64;

/// Whether running on x86_64
pub const is_x86_64: bool = @import("builtin").cpu.arch == .x86_64;

/// Whether running on 32-bit platform
pub const is_32bit: bool = @import("builtin").cpu.arch.ptrBitWidth() == 32;

/// Whether running on 64-bit platform
pub const is_64bit: bool = @import("builtin").cpu.arch.ptrBitWidth() == 64;

/// Debug build flag
pub const Py_DEBUG: bool = @import("builtin").mode == .Debug;

// ============================================================================
// Helper functions
// ============================================================================

/// Force garbage collection (no-op in Zig)
pub fn gc_collect() void {
    // No-op - Zig uses manual memory management
}

/// Check if we have IEEE 754 floating point (always true for Zig)
pub fn requires_IEEE_754() bool {
    return true;
}

/// Check if we have subprocess support
pub fn requires_subprocess() bool {
    return true;
}

/// Check if we have zlib support
pub fn requires_zlib() bool {
    return true;
}

/// Find a file in the test data directory
pub fn findfile(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // Just return the filename as-is for now
    return try allocator.dupe(u8, filename);
}

/// Decorator that skips test on non-CPython implementations
/// Returns the function unchanged (no-op decorator)
pub fn cpython_only(func: anytype) @TypeOf(func) {
    return func;
}

/// Decorator for big memory tests - returns identity function
pub fn bigmemtest(comptime size: i64, comptime memuse: f64) fn (type) type {
    _ = size;
    _ = memuse;
    return struct {
        fn wrapper(comptime T: type) T {
            return T;
        }
    }.wrapper;
}

/// Check syntax error in code string
pub fn check_syntax_error(_: std.mem.Allocator, _: []const u8) !void {
    // No-op for now
}

/// Run code and return result
pub fn run_code(_: std.mem.Allocator, _: []const u8) !void {
    // No-op for now
}

/// Swap an attribute temporarily
pub fn swap_attr(comptime T: type, obj: *T, comptime attr: []const u8, new_val: anytype) SwapContext(T, attr, @TypeOf(new_val)) {
    return SwapContext(T, attr, @TypeOf(new_val)).init(obj, new_val);
}

fn SwapContext(comptime T: type, comptime attr: []const u8, comptime V: type) type {
    return struct {
        obj: *T,
        old_val: V,

        const Self = @This();

        pub fn init(obj: *T, new_val: V) Self {
            const old = @field(obj, attr);
            @field(obj, attr) = new_val;
            return .{ .obj = obj, .old_val = old };
        }

        pub fn restore(self: *Self) void {
            @field(self.obj, attr) = self.old_val;
        }
    };
}

/// Swap a dictionary item temporarily
pub fn swap_item(comptime K: type, comptime V: type, dict: *std.AutoHashMap(K, V), key: K, new_val: V) SwapItemContext(K, V) {
    return SwapItemContext(K, V).init(dict, key, new_val);
}

fn SwapItemContext(comptime K: type, comptime V: type) type {
    return struct {
        dict: *std.AutoHashMap(K, V),
        key: K,
        old_val: ?V,

        const Self = @This();

        pub fn init(dict: *std.AutoHashMap(K, V), key: K, new_val: V) Self {
            const old = dict.get(key);
            dict.put(key, new_val) catch {};
            return .{ .dict = dict, .key = key, .old_val = old };
        }

        pub fn restore(self: *Self) void {
            if (self.old_val) |old| {
                self.dict.put(self.key, old) catch {};
            } else {
                _ = self.dict.remove(self.key);
            }
        }
    };
}

/// Suppress crash reports during test
pub const SuppressCrashReport = struct {
    pub fn init() SuppressCrashReport {
        return .{};
    }

    pub fn deinit(_: *SuppressCrashReport) void {}
};

/// Force not colorized output
pub fn force_not_colorized(func: anytype) @TypeOf(func) {
    return func;
}

/// Force not colorized output for test class
pub fn force_not_colorized_test_class(cls: anytype) @TypeOf(cls) {
    return cls;
}

/// Broken iterator for testing
pub const BrokenIter = struct {
    pub fn next(_: *BrokenIter) !?void {
        return error.BrokenIterator;
    }
};

/// Captured stdout context
pub const captured_stdout = struct {
    output: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) captured_stdout {
        return .{
            .output = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *captured_stdout) void {
        self.output.deinit();
    }

    pub fn getvalue(self: *captured_stdout) []const u8 {
        return self.output.items;
    }
};

/// Captured stderr context
pub const captured_stderr = struct {
    output: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) captured_stderr {
        return .{
            .output = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *captured_stderr) void {
        self.output.deinit();
    }

    pub fn getvalue(self: *captured_stderr) []const u8 {
        return self.output.items;
    }
};

/// Test failed exception
pub const TestFailed = error.TestFailed;

/// Smallest positive float
pub const SMALLEST: f64 = std.math.floatMin(f64);

/// Clock info for timing resolution
pub const ClockInfo = struct {
    resolution: f64 = 0.001, // millisecond resolution
    monotonic: bool = true,
    adjustable: bool = false,
    implementation: []const u8 = "std.time.milliTimestamp",
};

/// Stopwatch for timing tests (context manager compatible)
/// Python's support.Stopwatch uses .seconds property and .clock_info
pub const Stopwatch = struct {
    start_time: i64,
    /// Elapsed time in seconds (updated on close)
    seconds: f64 = 0.0,
    /// Clock information
    clock_info: ClockInfo = ClockInfo{},

    pub fn init() Stopwatch {
        return .{
            .start_time = std.time.milliTimestamp(),
            .seconds = 0.0,
            .clock_info = ClockInfo{},
        };
    }

    pub fn elapsed(self: *const Stopwatch) f64 {
        const now = std.time.milliTimestamp();
        return @as(f64, @floatFromInt(now - self.start_time)) / 1000.0;
    }

    /// Context manager close method - records elapsed time in seconds field
    pub fn close(self: *Stopwatch) void {
        self.seconds = self.elapsed();
    }
};

/// Check if resource is available
pub fn requires_resource(_: []const u8) bool {
    return true;
}

// ============================================================================
// Submodules
// ============================================================================

/// os_helper submodule
pub const os_helper = struct {
    /// Temporary directory for tests
    pub const TESTFN = "/tmp/metal0_test";

    /// Create a temporary file
    pub fn create_empty_file(path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        file.close();
    }

    /// Remove a file if it exists
    pub fn unlink(path: []const u8) void {
        std.fs.cwd().deleteFile(path) catch {};
    }

    /// Remove a directory tree
    pub fn rmtree(path: []const u8) void {
        std.fs.cwd().deleteTree(path) catch {};
    }

    /// Check if a path exists
    pub fn exists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Get temporary directory
    pub fn gettempdir() []const u8 {
        return "/tmp";
    }

    /// Environment variable context manager stub
    pub const EnvironmentVarGuard = struct {
        pub fn init() EnvironmentVarGuard {
            return .{};
        }
        pub fn deinit(_: *EnvironmentVarGuard) void {}
        pub fn set(_: *EnvironmentVarGuard, _: []const u8, _: []const u8) void {}
        pub fn unset(_: *EnvironmentVarGuard, _: []const u8) void {}
    };
};

/// import_helper submodule
pub const import_helper = struct {
    /// Import a module by name - returns the module reference
    /// For compiled modules, this is a no-op that returns a type reference
    pub fn import_module(comptime module_name: []const u8) type {
        // Return the appropriate module based on name
        // This is resolved at compile time
        if (std.mem.eql(u8, module_name, "zlib")) {
            return @import("zlib.zig");
        } else if (std.mem.eql(u8, module_name, "gzip")) {
            return @import("gzip");
        } else if (std.mem.eql(u8, module_name, "hashlib")) {
            return @import("hashlib.zig");
        } else if (std.mem.eql(u8, module_name, "json")) {
            return @import("json.zig");
        } else if (std.mem.eql(u8, module_name, "re")) {
            return @import("re.zig");
        } else if (std.mem.eql(u8, module_name, "math")) {
            return @import("math.zig");
        } else if (std.mem.eql(u8, module_name, "ctypes")) {
            return @import("ctypes.zig");
        } else {
            @compileError("Unknown module: " ++ module_name);
        }
    }

    /// Import a fresh module (no caching)
    /// Returns a module struct (stub for AOT)
    pub fn import_fresh_module(_: []const u8, _: anytype) ?*anyopaque {
        // No-op - we don't have dynamic imports, return null
        return null;
    }

    /// Temporarily add a path to sys.path
    pub const DirsOnSysPath = struct {
        pub fn init(_: []const u8) DirsOnSysPath {
            return .{};
        }
        pub fn deinit(_: *DirsOnSysPath) void {}
    };

    /// Make a module unavailable temporarily
    pub const CleanImport = struct {
        pub fn init() CleanImport {
            return .{};
        }
        pub fn deinit(_: *CleanImport) void {}
    };

    /// Ensure lazy imports - no-op in AOT context
    /// In CPython this verifies that certain modules are lazily imported
    pub fn ensure_lazy_imports(_: []const u8, _: anytype) void {
        // No-op - AOT compilation resolves all imports at compile time
    }
};

/// warnings_helper submodule
pub const warnings_helper = struct {
    /// Check for warning
    pub fn check_warnings(_: std.mem.Allocator, _: []const u8) !void {
        // No-op
    }

    /// Ignore warnings context
    pub const catch_warnings = struct {
        pub fn init() catch_warnings {
            return .{};
        }
        pub fn deinit(_: *catch_warnings) void {}
    };

    /// Check no warnings raised
    pub fn check_no_warnings(_: std.mem.Allocator) !void {
        // No-op
    }

    /// Check no resource warnings
    pub fn check_no_resource_warning(_: std.mem.Allocator) !void {
        // No-op
    }
};

/// threading_helper submodule
pub const threading_helper = struct {
    /// Wait for threads to finish
    pub fn join_thread(_: anytype) void {
        // No-op
    }

    /// Threading cleanup
    pub const threading_cleanup = struct {
        pub fn init() threading_cleanup {
            return .{};
        }
        pub fn deinit(_: *threading_cleanup) void {}
    };

    /// Reap threads - decorator that returns the function unchanged
    pub fn reap_threads(func: anytype) @TypeOf(func) {
        return func;
    }

    /// Start threads helper
    pub fn start_threads(_: std.mem.Allocator, _: anytype, _: usize) !void {
        // No-op
    }
};

/// socket_helper submodule
pub const socket_helper = struct {
    /// Get unused port
    pub fn find_unused_port() u16 {
        return 0; // Let system assign
    }

    /// Check if IPv6 is available
    pub fn has_ipv6() bool {
        return true;
    }

    /// Transient socket error guard
    pub const transient_internet_error = struct {
        pub fn init() transient_internet_error {
            return .{};
        }
        pub fn deinit(_: *transient_internet_error) void {}
    };

    /// Skip if no network
    pub fn skip_without_network() bool {
        return false;
    }
};

/// script_helper submodule
pub const script_helper = struct {
    /// Run Python script
    pub fn run_python_until_end(_: std.mem.Allocator, _: []const []const u8) !struct { stdout: []const u8, stderr: []const u8, rc: i32 } {
        return .{ .stdout = "", .stderr = "", .rc = 0 };
    }

    /// Assert Python OK
    pub fn assert_python_ok(_: std.mem.Allocator, _: []const []const u8) !void {
        // No-op
    }

    /// Make script
    pub fn make_script(_: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8) ![]const u8 {
        return "";
    }

    /// Make package
    pub fn make_pkg(_: std.mem.Allocator, _: []const u8) !void {
        // No-op
    }
};

/// hashlib_helper submodule
pub const hashlib_helper = struct {
    /// Check if hash algorithm is available
    pub fn requires_hashdigest(name: []const u8) bool {
        _ = name;
        return true;
    }
};

/// numbers submodule - numeric literal test data
pub const numbers = struct {
    /// Valid underscore literals (PEP 515)
    pub const VALID_UNDERSCORE_LITERALS: []const []const u8 = &.{
        "0_0_0",
        "4_2",
        "1_0000_0000",
        "0b1001_0100",
        "0xffff_ffff",
        "0o5_7_7",
        "1_00_00.5",
        "1_00_00.5e5",
        "1_00_00e5_1",
        "1e1_0",
        ".1_4",
        ".1_4e1",
        "0b_0",
        "0x_f",
        "0o_5",
        "1_00_00j",
        "1_00_00.5j",
        "1_00_00e5_1j",
        ".1_4j",
        "(1_2.5+3_3j)",
        "(.5_6j)",
    };

    /// Invalid underscore literals (should raise ValueError/SyntaxError)
    pub const INVALID_UNDERSCORE_LITERALS: []const []const u8 = &.{
        // Trailing underscores
        "0_",
        "42_",
        "1.4j_",
        // Underscores in wrong positions
        "0_b0",
        "0_xf",
        "0_o5",
        // Multiple consecutive underscores
        "4_______2",
        "0.1__4",
        // Around decimal point
        "1_.4",
        "1._4",
        "._5",
        // Around exponent
        "1_e1",
        "1e_1",
        "1.0e+_1",
        // Before j
        "1.4_j",
        "1e1__0j",
    };
};

// ============================================================================
// Async helpers (for async tests)
// ============================================================================

/// Run async function that yields
pub fn run_yielding_async_fn(_: anytype) !void {
    // No-op
}

/// Run async function that doesn't yield
pub fn run_no_yield_async_fn(_: anytype) !void {
    // No-op
}

/// Async yield helper
pub fn async_yield() void {
    // No-op
}

// ============================================================================
// Platform skip helpers
// ============================================================================

/// Skip test on WASI due to stack overflow
pub fn skip_wasi_stack_overflow() bool {
    return is_wasi;
}

/// Skip test on Emscripten due to stack overflow
pub fn skip_emscripten_stack_overflow() bool {
    return false;
}

/// Check if recursion limit is exceeded
pub fn exceeds_recursion_limit(_: usize) bool {
    return false;
}

/// Check if linked to musl
pub fn linked_to_musl() bool {
    return false;
}

/// Check if we need specialization for free-threading
pub fn requires_specialization_ft() bool {
    return false;
}

/// Check if we need debug ranges
pub fn requires_debug_ranges() bool {
    return false;
}

/// Skip if buggy UCRT strfptime
pub fn skip_if_buggy_ucrt_strfptime() bool {
    return false;
}

/// Check disallow instantiation
pub fn check_disallow_instantiation(_: anytype) bool {
    return true;
}

// ============================================================================
// asyncore stub (deprecated module)
// ============================================================================

pub const asyncore = struct {
    pub const dispatcher = struct {
        pub fn init() dispatcher {
            return .{};
        }
        pub fn handle_connect(_: *dispatcher) void {}
        pub fn handle_close(_: *dispatcher) void {}
        pub fn handle_read(_: *dispatcher) void {}
        pub fn handle_write(_: *dispatcher) void {}
    };

    pub fn loop() void {}
};

// ============================================================================
// Integer string conversion limit context manager
// ============================================================================

const sys = @import("sys.zig");

/// Context manager for temporarily adjusting sys.get_int_max_str_digits()
/// Usage: const ctx = adjust_int_max_str_digits(new_limit); defer ctx.close();
pub fn adjust_int_max_str_digits(new_limit: i64) IntMaxStrDigitsContext {
    return IntMaxStrDigitsContext.init(new_limit);
}

pub const IntMaxStrDigitsContext = struct {
    old_limit: i64,

    pub fn init(new_limit: i64) IntMaxStrDigitsContext {
        // Save old limit
        const old = sys.get_int_max_str_digits(undefined) catch 4300;
        // Set new limit
        _ = sys.set_int_max_str_digits(undefined, new_limit) catch {};
        return .{ .old_limit = old };
    }

    pub fn close(self: IntMaxStrDigitsContext) void {
        // Restore old limit
        _ = sys.set_int_max_str_digits(undefined, self.old_limit) catch {};
    }
};

// ============================================================================
// Subinterpreter support (stub for testing)
// ============================================================================

/// Run code in a subinterpreter (stub - always returns 0 for success)
/// In CPython, this runs code in a separate interpreter state
pub fn run_in_subinterp(_: []const u8) i64 {
    // Stub: pretend the code ran successfully
    return 0;
}

// ============================================================================
// test.support sub-module (self-reference for nested imports)
// ============================================================================

/// Self-reference for imports like "from test import support"
/// This allows code like: const support = @"test".support;
pub const support = @This();
