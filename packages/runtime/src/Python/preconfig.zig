/// preconfig - Pre-Initialization Configuration
/// Mirrors cpython/Python/preconfig.c
///
/// This module handles pre-initialization configuration:
/// - Locale settings before Python starts
/// - UTF-8 mode detection
/// - Memory allocator selection
/// - Core configuration before Py_Initialize

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Allocator Names
// ============================================================================

/// Memory allocator identifiers
pub const AllocatorName = enum {
    default,
    debug,
    malloc,
    pymalloc,
    pymalloc_debug,
    mimalloc,
    mimalloc_debug,

    pub fn toString(self: AllocatorName) []const u8 {
        return switch (self) {
            .default => "default",
            .debug => "debug",
            .malloc => "malloc",
            .pymalloc => "pymalloc",
            .pymalloc_debug => "pymalloc_debug",
            .mimalloc => "mimalloc",
            .mimalloc_debug => "mimalloc_debug",
        };
    }

    pub fn fromString(s: []const u8) ?AllocatorName {
        if (std.mem.eql(u8, s, "default")) return .default;
        if (std.mem.eql(u8, s, "debug")) return .debug;
        if (std.mem.eql(u8, s, "malloc")) return .malloc;
        if (std.mem.eql(u8, s, "pymalloc")) return .pymalloc;
        if (std.mem.eql(u8, s, "pymalloc_debug")) return .pymalloc_debug;
        if (std.mem.eql(u8, s, "mimalloc")) return .mimalloc;
        if (std.mem.eql(u8, s, "mimalloc_debug")) return .mimalloc_debug;
        return null;
    }
};

// ============================================================================
// UTF-8 Mode
// ============================================================================

/// UTF-8 mode setting
pub const UTF8Mode = enum(i32) {
    default = -1, // Inherit from locale
    disabled = 0, // Force legacy encoding
    enabled = 1, // Force UTF-8

    pub fn isEnabled(self: UTF8Mode) bool {
        return self == .enabled;
    }
};

// ============================================================================
// Pre-Configuration
// ============================================================================

/// Pre-initialization configuration
pub const PyPreConfig = struct {
    /// Configuration version
    _config_version: i32 = 1,

    /// Parse PY* environment variables
    parse_argv: bool = true,

    /// Isolated mode (-I)
    isolated: bool = false,

    /// Use environment variables
    use_environment: bool = true,

    /// Configure C locale
    configure_locale: bool = true,

    /// Coerce C locale
    coerce_c_locale: bool = false,

    /// Warn on C locale coercion
    coerce_c_locale_warn: bool = false,

    /// UTF-8 mode
    utf8_mode: UTF8Mode = .default,

    /// Development mode (-X dev)
    dev_mode: bool = false,

    /// Memory allocator name
    allocator: AllocatorName = .default,

    const Self = @This();

    /// Create default preconfig
    pub fn initPython() Self {
        return .{
            .parse_argv = true,
            .isolated = false,
            .use_environment = true,
            .configure_locale = true,
            .utf8_mode = .default,
        };
    }

    /// Create isolated preconfig
    pub fn initIsolated() Self {
        return .{
            .parse_argv = false,
            .isolated = true,
            .use_environment = false,
            .configure_locale = false,
            .utf8_mode = .default,
        };
    }

    /// Copy from another preconfig
    pub fn copy(other: *const Self) Self {
        return other.*;
    }

    /// Set allocator by name
    pub fn setAllocator(self: *Self, name: []const u8) bool {
        if (AllocatorName.fromString(name)) |alloc| {
            self.allocator = alloc;
            return true;
        }
        return false;
    }

    /// Configure UTF-8 mode from environment
    pub fn readUtf8Mode(self: *Self) void {
        if (self.utf8_mode != .default) return;

        // Check PYTHONUTF8 environment variable
        if (self.use_environment) {
            if (std.posix.getenv("PYTHONUTF8")) |val| {
                if (std.mem.eql(u8, val, "1")) {
                    self.utf8_mode = .enabled;
                    return;
                } else if (std.mem.eql(u8, val, "0")) {
                    self.utf8_mode = .disabled;
                    return;
                }
            }
        }

        // Check locale
        if (self.configure_locale) {
            if (isUtf8Locale()) {
                self.utf8_mode = .enabled;
            }
        }
    }

    /// Read from environment variables
    pub fn readEnv(self: *Self) void {
        if (!self.use_environment) return;

        // PYTHONDEVMODE
        if (std.posix.getenv("PYTHONDEVMODE")) |val| {
            if (std.mem.eql(u8, val, "1")) {
                self.dev_mode = true;
            }
        }

        // PYTHONMALLOC
        if (std.posix.getenv("PYTHONMALLOC")) |val| {
            _ = self.setAllocator(val);
        }

        // PYTHONCOERCECLOCALE
        if (std.posix.getenv("PYTHONCOERCECLOCALE")) |val| {
            if (std.mem.eql(u8, val, "0")) {
                self.coerce_c_locale = false;
            } else if (std.mem.eql(u8, val, "warn")) {
                self.coerce_c_locale = true;
                self.coerce_c_locale_warn = true;
            } else {
                self.coerce_c_locale = true;
            }
        }

        self.readUtf8Mode();
    }
};

// ============================================================================
// Locale Utilities
// ============================================================================

/// Check if current locale uses UTF-8
pub fn isUtf8Locale() bool {
    // Check LC_ALL, LC_CTYPE, LANG environment variables
    const vars = [_][]const u8{ "LC_ALL", "LC_CTYPE", "LANG" };
    for (vars) |v| {
        if (std.posix.getenv(v)) |val| {
            // Check for UTF-8 markers
            if (std.mem.indexOf(u8, val, "UTF-8") != null or
                std.mem.indexOf(u8, val, "utf-8") != null or
                std.mem.indexOf(u8, val, "utf8") != null)
            {
                return true;
            }
            // Check for C.UTF-8
            if (std.mem.eql(u8, val, "C.UTF-8")) {
                return true;
            }
        }
    }
    return false;
}

/// Get the current locale name
pub fn getLocaleName() []const u8 {
    const vars = [_][]const u8{ "LC_ALL", "LC_CTYPE", "LANG" };
    for (vars) |v| {
        if (std.posix.getenv(v)) |val| {
            return val;
        }
    }
    return "C";
}

/// Check if locale should be coerced
pub fn shouldCoerceLocale(preconfig: *const PyPreConfig) bool {
    if (!preconfig.coerce_c_locale) return false;

    const locale = getLocaleName();
    // Coerce if using C or POSIX locale
    return std.mem.eql(u8, locale, "C") or std.mem.eql(u8, locale, "POSIX");
}

// ============================================================================
// Pre-Configuration Status
// ============================================================================

/// Status of pre-initialization
pub const PyStatus = struct {
    err_msg: ?[]const u8 = null,
    exit_code: i32 = 0,
    is_error: bool = false,
    is_exit: bool = false,

    const Self = @This();

    pub fn ok() Self {
        return .{};
    }

    pub fn err(msg: []const u8) Self {
        return .{
            .err_msg = msg,
            .is_error = true,
        };
    }

    pub fn exit(code: i32) Self {
        return .{
            .exit_code = code,
            .is_exit = true,
        };
    }

    pub fn isOk(self: *const Self) bool {
        return !self.is_error and !self.is_exit;
    }
};

// ============================================================================
// Pre-Initialization Functions
// ============================================================================

/// Pre-initialize from preconfig
pub fn preInitFromPreConfig(preconfig: *const PyPreConfig) PyStatus {
    // Validate configuration
    if (preconfig.isolated and preconfig.use_environment) {
        return PyStatus.err("isolated and use_environment are mutually exclusive");
    }

    // Configure locale if requested
    if (preconfig.configure_locale) {
        if (shouldCoerceLocale(preconfig)) {
            // Would coerce C locale to C.UTF-8
            if (preconfig.coerce_c_locale_warn) {
                // Emit warning
            }
        }
    }

    return PyStatus.ok();
}

/// Pre-initialize from PyConfig (convenience)
pub fn preInitFromConfig(config: anytype) PyStatus {
    _ = config;
    // Extract preconfig from config and call preInitFromPreConfig
    return PyStatus.ok();
}

/// Pre-initialize with given preconfig
pub fn preInit(preconfig: *const PyPreConfig) PyStatus {
    return preInitFromPreConfig(preconfig);
}

/// Pre-initialize with default settings
pub fn preInitDefault() PyStatus {
    const preconfig = PyPreConfig.initPython();
    return preInit(&preconfig);
}

// ============================================================================
// Global State
// ============================================================================

var g_preconfig: PyPreConfig = PyPreConfig.initPython();
var g_preinitialized: bool = false;

/// Get global preconfig
pub fn getPreConfig() *const PyPreConfig {
    return &g_preconfig;
}

/// Check if pre-initialized
pub fn isPreinitialized() bool {
    return g_preinitialized;
}

/// Set pre-initialized state
pub fn setPreinitialized(preconfig: *const PyPreConfig) void {
    g_preconfig = preconfig.*;
    g_preinitialized = true;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "allocator name parsing" {
    try std.testing.expectEqual(AllocatorName.default, AllocatorName.fromString("default").?);
    try std.testing.expectEqual(AllocatorName.pymalloc, AllocatorName.fromString("pymalloc").?);
    try std.testing.expect(AllocatorName.fromString("unknown") == null);

    try std.testing.expectEqualStrings("malloc", AllocatorName.malloc.toString());
}

test "utf8 mode" {
    try std.testing.expect(!UTF8Mode.default.isEnabled());
    try std.testing.expect(!UTF8Mode.disabled.isEnabled());
    try std.testing.expect(UTF8Mode.enabled.isEnabled());
}

test "preconfig init python" {
    const preconfig = PyPreConfig.initPython();
    try std.testing.expect(preconfig.parse_argv);
    try std.testing.expect(!preconfig.isolated);
    try std.testing.expect(preconfig.use_environment);
    try std.testing.expectEqual(UTF8Mode.default, preconfig.utf8_mode);
}

test "preconfig init isolated" {
    const preconfig = PyPreConfig.initIsolated();
    try std.testing.expect(!preconfig.parse_argv);
    try std.testing.expect(preconfig.isolated);
    try std.testing.expect(!preconfig.use_environment);
}

test "preconfig copy" {
    var orig = PyPreConfig.initPython();
    orig.dev_mode = true;
    orig.allocator = .pymalloc;

    const copied = PyPreConfig.copy(&orig);
    try std.testing.expect(copied.dev_mode);
    try std.testing.expectEqual(AllocatorName.pymalloc, copied.allocator);
}

test "pystatus" {
    const ok = PyStatus.ok();
    try std.testing.expect(ok.isOk());
    try std.testing.expect(!ok.is_error);

    const err_status = PyStatus.err("test error");
    try std.testing.expect(!err_status.isOk());
    try std.testing.expect(err_status.is_error);
    try std.testing.expectEqualStrings("test error", err_status.err_msg.?);

    const exit_status = PyStatus.exit(42);
    try std.testing.expect(!exit_status.isOk());
    try std.testing.expect(exit_status.is_exit);
    try std.testing.expectEqual(@as(i32, 42), exit_status.exit_code);
}

test "locale utilities" {
    // Just test the function exists and doesn't crash
    const locale = getLocaleName();
    try std.testing.expect(locale.len > 0);
}
