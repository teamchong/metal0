/// config - System Configuration Variables
/// Thread-local configuration settings and limits

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Configuration Variables
// ============================================================================

/// Thread-local int_max_str_digits limit (default 4300 in CPython 3.11+)
/// Controls the maximum digits for int/str conversions to prevent DoS
pub var int_max_str_digits: i64 = 4300;

/// Recursion limit (default 1000 in CPython)
pub var recursion_limit: u32 = 1000;

/// Switch interval for thread switching (seconds)
pub var switch_interval: f64 = 0.005;

/// Interactive mode flag
pub var is_interactive: bool = false;

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
