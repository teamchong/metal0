//! Cross-platform process ID formatting
//!
//! On Windows: std.process.Child.Id is HANDLE (*anyopaque) - use {any}
//! On POSIX: std.process.Child.Id is integer (i32/pid_t) - use {d}

const builtin = @import("builtin");

/// Format specifier for process IDs
/// Use with std.debug.print or std.fmt
pub const PID_FMT = if (builtin.os.tag == .windows) "{any}" else "{d}";

/// Format specifier for optional process IDs
pub const PID_FMT_OPT = if (builtin.os.tag == .windows) "{?any}" else "{?d}";
