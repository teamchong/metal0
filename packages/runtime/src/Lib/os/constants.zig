/// Platform-specific constants for OS operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#os-file-dir
const builtin = @import("builtin");

/// Path separator for the current platform
pub const sep: []const u8 = if (builtin.os.tag == .windows) "\\" else "/";

/// Alternative path separator (Windows only)
pub const altsep: ?[]const u8 = if (builtin.os.tag == .windows) "/" else null;

/// Path list separator (PATH environment variable)
pub const pathsep: []const u8 = if (builtin.os.tag == .windows) ";" else ":";

/// Line separator
pub const linesep: []const u8 = if (builtin.os.tag == .windows) "\r\n" else "\n";

/// Current directory string
pub const curdir: []const u8 = ".";

/// Parent directory string
pub const pardir: []const u8 = "..";

/// Extension separator
pub const extsep: []const u8 = ".";

/// Device null file
pub const devnull: []const u8 = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

/// Platform name
pub const name: []const u8 = switch (builtin.os.tag) {
    .windows => "nt",
    else => "posix",
};
