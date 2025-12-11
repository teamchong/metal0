/// traceback/source - Source Line Extraction
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Extract source line from file by line number
/// - File validation for display
/// - Thread-local buffers to avoid allocations

const std = @import("std");

/// Extract source line from file by reading the file and extracting the specific line
/// Returns null if file cannot be read or line number is out of range
/// Uses a thread-local buffer to avoid allocations
pub fn getSourceLine(filename: []const u8, lineno: i32) ?[]const u8 {
    if (lineno <= 0) return null;
    if (!isValidFilename(filename)) return null;

    // Thread-local buffer for source line (avoids allocation per call)
    const Static = struct {
        threadlocal var line_buffer: [4096]u8 = undefined;
        threadlocal var file_buffer: [65536]u8 = undefined;
    };

    // Try to open the file
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        // Also try absolute path if relative failed
        if (err == error.FileNotFound and !std.fs.path.isAbsolute(filename)) {
            return null;
        }
        return null;
    };
    defer file.close();

    // Read file contents into buffer
    const bytes_read = file.readAll(&Static.file_buffer) catch return null;
    const content = Static.file_buffer[0..bytes_read];

    // Find the target line
    var current_line: i32 = 1;
    var line_start: usize = 0;

    for (content, 0..) |c, i| {
        if (c == '\n') {
            if (current_line == lineno) {
                // Found our line
                const line_content = content[line_start..i];
                const len = @min(line_content.len, Static.line_buffer.len - 1);
                @memcpy(Static.line_buffer[0..len], line_content[0..len]);
                return Static.line_buffer[0..len];
            }
            current_line += 1;
            line_start = i + 1;
        }
    }

    // Check last line (file may not end with newline)
    if (current_line == lineno and line_start < content.len) {
        const line_content = content[line_start..];
        const len = @min(line_content.len, Static.line_buffer.len - 1);
        @memcpy(Static.line_buffer[0..len], line_content[0..len]);
        return Static.line_buffer[0..len];
    }

    return null;
}

/// Check if filename is valid for display
pub fn isValidFilename(filename: []const u8) bool {
    return filename.len > 0 and
        filename[0] != '<' and // Skip <stdin>, <string>, etc.
        !std.mem.eql(u8, filename, "?");
}
