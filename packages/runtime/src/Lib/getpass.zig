/// getpass - Portable password input
/// Mirrors cpython/Lib/getpass.py
///
/// Provides functions for getting passwords and current user info
/// from terminal without echoing.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Errors
// ============================================================================

pub const GetPassError = error{
    NoTTY,
    InputError,
    PasswordTooLong,
    Interrupted,
};

// ============================================================================
// Configuration
// ============================================================================

/// Maximum password length
pub const MAX_PASSWORD_LENGTH: usize = 4096;

/// Default prompt
pub const DEFAULT_PROMPT: []const u8 = "Password: ";

// ============================================================================
// getpass - Get password without echoing
// ============================================================================

/// Get a password from the terminal without echoing.
/// Falls back to standard input if no TTY is available.
pub fn getpass(allocator: std.mem.Allocator, prompt: ?[]const u8) ![]u8 {
    const actual_prompt = prompt orelse DEFAULT_PROMPT;

    // Try to open /dev/tty first (Unix), fall back to stdin
    if (builtin.os.tag != .windows) {
        return getpassUnix(allocator, actual_prompt);
    } else {
        return getpassWindows(allocator, actual_prompt);
    }
}

/// Unix implementation using termios
fn getpassUnix(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    // Try /dev/tty first
    const tty_file = std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write }) catch {
        // Fall back to stdin/stderr
        return getpassFallback(allocator, prompt);
    };
    defer tty_file.close();

    // Write prompt
    _ = tty_file.write(prompt) catch {};

    // Save terminal settings
    const fd = tty_file.handle;
    var old_termios: std.posix.termios = undefined;
    std.posix.tcgetattr(fd, &old_termios) catch {
        return getpassFallback(allocator, prompt);
    };

    // Disable echo
    var new_termios = old_termios;
    new_termios.lflag.ECHO = false;

    std.posix.tcsetattr(fd, .FLUSH, new_termios) catch {
        return getpassFallback(allocator, prompt);
    };

    // Read password
    defer {
        // Restore terminal settings
        std.posix.tcsetattr(fd, .FLUSH, old_termios) catch {};
        // Write newline
        _ = tty_file.write("\n") catch {};
    }

    var password = std.ArrayList(u8).init(allocator);
    errdefer password.deinit();

    var buf: [1]u8 = undefined;
    while (true) {
        const n = tty_file.read(&buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return GetPassError.InputError,
        };

        if (n == 0) break;

        if (buf[0] == '\n' or buf[0] == '\r') break;

        if (password.items.len >= MAX_PASSWORD_LENGTH) {
            return GetPassError.PasswordTooLong;
        }

        try password.append(buf[0]);
    }

    return password.toOwnedSlice();
}

/// Windows implementation using kernel32 console APIs for echo-less input
fn getpassWindows(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    // Write prompt to stderr
    std.io.getStdErr().writer().writeAll(prompt) catch {};

    var password = std.ArrayList(u8).init(allocator);
    errdefer password.deinit();

    if (comptime builtin.os.tag == .windows) {
        // Use Windows Console API to disable echo
        const windows = std.os.windows;
        const kernel32 = windows.kernel32;

        const stdin_handle = kernel32.GetStdHandle(windows.STD_INPUT_HANDLE);
        if (stdin_handle == windows.INVALID_HANDLE_VALUE) {
            return GetPassError.NoTTY;
        }

        // Save original console mode
        var original_mode: windows.DWORD = 0;
        if (kernel32.GetConsoleMode(stdin_handle, &original_mode) == 0) {
            // Not a console - fall back to regular stdin read
            return getpassFallback(allocator, prompt);
        }

        // Disable echo (ENABLE_ECHO_INPUT) and line input (read char by char)
        const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
        const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
        const new_mode = original_mode & ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT);
        _ = kernel32.SetConsoleMode(stdin_handle, new_mode);
        defer _ = kernel32.SetConsoleMode(stdin_handle, original_mode);

        // Read character by character
        var buf: [1]u8 = undefined;
        var bytes_read: windows.DWORD = 0;
        while (true) {
            if (kernel32.ReadFile(stdin_handle, &buf, 1, &bytes_read, null) == 0 or bytes_read == 0) {
                break;
            }

            const c = buf[0];
            if (c == '\n' or c == '\r') break;
            if (c == 0x03) return GetPassError.Interrupted; // Ctrl+C
            if (c == 0x08 or c == 0x7f) { // Backspace
                if (password.items.len > 0) {
                    _ = password.pop();
                }
                continue;
            }

            if (password.items.len >= MAX_PASSWORD_LENGTH) {
                return GetPassError.PasswordTooLong;
            }

            try password.append(c);
        }
    } else {
        // Non-Windows: just read from stdin (shouldn't be called)
        const stdin = std.io.getStdIn().reader();
        while (true) {
            const c = stdin.readByte() catch break;
            if (c == '\n' or c == '\r') break;
            if (c == 0x03) return GetPassError.Interrupted;
            if (c == 0x08 or c == 0x7f) {
                if (password.items.len > 0) _ = password.pop();
                continue;
            }
            if (password.items.len >= MAX_PASSWORD_LENGTH) return GetPassError.PasswordTooLong;
            try password.append(c);
        }
    }

    // Print newline
    std.io.getStdErr().writer().writeAll("\n") catch {};

    return password.toOwnedSlice();
}

/// Fallback when no TTY available
fn getpassFallback(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    // Warning: password will be visible!
    std.io.getStdErr().writer().writeAll("Warning: Password input may be echoed.\n") catch {};
    std.io.getStdErr().writer().writeAll(prompt) catch {};

    const stdin = std.io.getStdIn().reader();
    const line = stdin.readUntilDelimiterAlloc(allocator, '\n', MAX_PASSWORD_LENGTH) catch |err| {
        return switch (err) {
            error.StreamTooLong => GetPassError.PasswordTooLong,
            else => GetPassError.InputError,
        };
    };

    // Strip trailing \r if present (Windows line endings)
    if (line.len > 0 and line[line.len - 1] == '\r') {
        const trimmed = line[0 .. line.len - 1];
        allocator.free(line);
        return try allocator.dupe(u8, trimmed);
    }

    return line;
}

// ============================================================================
// getuser - Get current user name
// ============================================================================

/// Return the "login name" of the user.
/// Checks LOGNAME, USER, LNAME, USERNAME environment variables.
pub fn getuser() []const u8 {
    // Try environment variables in order
    const env_vars = [_][]const u8{
        "LOGNAME",
        "USER",
        "LNAME",
        "USERNAME",
    };

    for (env_vars) |var_name| {
        if (std.posix.getenv(var_name)) |value| {
            if (value.len > 0) {
                return value;
            }
        }
    }

    // Could also try getpwuid(getuid()) on Unix
    return "";
}

/// Get user with fallback
pub fn getuserWithFallback(fallback: []const u8) []const u8 {
    const user = getuser();
    return if (user.len > 0) user else fallback;
}

// ============================================================================
// Unix-specific helpers
// ============================================================================

/// Check if stdin is a TTY
pub fn isatty() bool {
    if (builtin.os.tag == .windows) {
        // Would use GetConsoleMode
        return true;
    }
    return std.posix.isatty(std.posix.STDIN_FILENO);
}

/// Get the terminal device name
pub fn ttyname() ?[]const u8 {
    if (builtin.os.tag == .windows) {
        return "CON";
    }
    // Would use ttyname_r on Unix
    return "/dev/tty";
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the getpass module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "getuser returns something" {
    const user = getuser();
    // May be empty if no env vars set, but shouldn't crash
    _ = user;
}

test "getuserWithFallback" {
    const user = getuserWithFallback("default");
    try std.testing.expect(user.len > 0);
}

test "isatty" {
    // Just verify it doesn't crash
    _ = isatty();
}

test "ttyname" {
    const name = ttyname();
    if (name) |n| {
        try std.testing.expect(n.len > 0);
    }
}

test "MAX_PASSWORD_LENGTH" {
    try std.testing.expect(MAX_PASSWORD_LENGTH > 0);
    try std.testing.expect(MAX_PASSWORD_LENGTH >= 1024);
}

test "DEFAULT_PROMPT" {
    try std.testing.expectEqualStrings("Password: ", DEFAULT_PROMPT);
}
