/// config - Interpreter Configuration
/// Mirrors cpython/Python/interpconfig.c (config section)
///
/// Configuration for creating sub-interpreters:
/// - Memory allocation (use main interpreter's allocator or own)
/// - Security settings (fork, exec permissions)
/// - Threading configuration
/// - GIL mode selection
/// - Extension compatibility checking

const gil = @import("gil.zig");

/// Configuration for creating a sub-interpreter
pub const PyInterpreterConfig = struct {
    /// Use main interpreter's __main__ dict
    use_main_obmalloc: bool = false,

    /// Allow fork
    allow_fork: bool = true,

    /// Allow exec
    allow_exec: bool = true,

    /// Allow threads
    allow_threads: bool = true,

    /// Allow daemon threads
    allow_daemon_threads: bool = true,

    /// Check multi-interp extension compatibility
    check_multi_interp_extensions: gil.CheckMultiInterpExtensions = .default,

    /// GIL mode
    gil: gil.GILMode = .default,

    const Self = @This();

    /// Default configuration for sub-interpreter
    pub fn initDefault() Self {
        return .{};
    }

    /// Configuration for isolated sub-interpreter
    pub fn initIsolated() Self {
        return .{
            .use_main_obmalloc = false,
            .allow_fork = false,
            .allow_exec = false,
            .allow_threads = true,
            .allow_daemon_threads = false,
            .check_multi_interp_extensions = .high,
            .gil = .own,
        };
    }

    /// Configuration for legacy sub-interpreter (shared GIL)
    pub fn initLegacy() Self {
        return .{
            .use_main_obmalloc = true,
            .allow_fork = true,
            .allow_exec = true,
            .allow_threads = true,
            .allow_daemon_threads = true,
            .check_multi_interp_extensions = .low,
            .gil = .shared,
        };
    }

    /// Copy configuration
    pub fn copy(self: *const Self) Self {
        return self.*;
    }

    /// Validate configuration
    pub fn validate(self: *const Self) !void {
        // Can't have daemon threads without threads
        if (self.allow_daemon_threads and !self.allow_threads) {
            return error.InvalidConfig;
        }

        // Own GIL requires not using main obmalloc
        if (self.gil == .own and self.use_main_obmalloc) {
            return error.InvalidConfig;
        }
    }
};
