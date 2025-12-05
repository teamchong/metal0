/// Debug Info Reader for Runtime Stack Traces
///
/// Reads .metal0.dbg files to translate Zig line numbers to Python line numbers.
/// Used for generating Python-friendly stack traces at runtime.
///
const std = @import("std");

/// Code mapping from Python line to Zig line
pub const CodeMapping = struct {
    py_line: u32,
    zig_line: u32,
};

/// Debug info for a compiled module
pub const DebugInfo = struct {
    source_file: []const u8,
    mappings: []const CodeMapping,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DebugInfo) void {
        self.allocator.free(self.source_file);
        self.allocator.free(self.mappings);
    }

    /// Look up Python line number from Zig line number
    /// Returns null if no mapping found
    pub fn zigToPythonLine(self: *const DebugInfo, zig_line: u32) ?u32 {
        // Find the closest mapping <= zig_line
        var best_match: ?u32 = null;
        var best_zig_line: u32 = 0;

        for (self.mappings) |mapping| {
            if (mapping.zig_line <= zig_line and mapping.zig_line > best_zig_line) {
                best_match = mapping.py_line;
                best_zig_line = mapping.zig_line;
            }
        }

        return best_match;
    }
};

/// Load debug info from a .metal0.dbg.json file
/// Returns null if file doesn't exist or is invalid
pub fn loadDebugInfo(allocator: std.mem.Allocator, dbg_path: []const u8) ?DebugInfo {
    // Try to read the JSON debug file
    const file = std.fs.cwd().openFile(dbg_path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(content);

    return parseDebugJson(allocator, content);
}

/// Load debug info by guessing the path from executable
pub fn loadDebugInfoForExecutable(allocator: std.mem.Allocator) ?DebugInfo {
    // Get the executable path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = std.fs.selfExePath(&path_buf) catch return null;

    // Try .metal0.dbg.json first (easier to parse)
    const json_path = std.fmt.allocPrint(allocator, "{s}.metal0.dbg.json", .{exe_path}) catch return null;
    defer allocator.free(json_path);

    if (loadDebugInfo(allocator, json_path)) |info| {
        return info;
    }

    return null;
}

/// Parse debug info from JSON content
fn parseDebugJson(allocator: std.mem.Allocator, content: []const u8) ?DebugInfo {
    // Simple JSON parsing for the specific format we generate
    // Format: { "sourceFile": "...", "mappings": [{"pyLine": N, "zigLine": M}, ...] }

    var source_file: ?[]const u8 = null;
    var mappings = std.ArrayList(CodeMapping){};
    errdefer mappings.deinit(allocator);
    errdefer if (source_file) |sf| allocator.free(sf);

    // Find sourceFile - format: "sourceFile": "/path/to/file.py"
    if (std.mem.indexOf(u8, content, "\"sourceFile\":")) |idx| {
        // Skip past "sourceFile": to find the value
        const after_key = idx + 13; // len of "sourceFile":
        // Find opening quote of value (may have whitespace)
        const value_start = std.mem.indexOfPos(u8, content, after_key, "\"") orelse return null;
        // Find closing quote of value
        const value_end = std.mem.indexOfPos(u8, content, value_start + 1, "\"") orelse return null;
        source_file = allocator.dupe(u8, content[value_start + 1 .. value_end]) catch return null;
    }

    // Find mappings array
    if (std.mem.indexOf(u8, content, "\"mappings\":")) |mappings_start| {
        const arr_start = std.mem.indexOfPos(u8, content, mappings_start, "[") orelse return null;
        const arr_end = std.mem.indexOfPos(u8, content, arr_start, "]") orelse return null;
        const mappings_content = content[arr_start + 1 .. arr_end];

        // Parse each mapping object
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, mappings_content, pos, "{")) |obj_start| {
            const obj_end = std.mem.indexOfPos(u8, mappings_content, obj_start, "}") orelse break;
            const obj = mappings_content[obj_start .. obj_end + 1];

            // Parse pyLine
            var py_line: u32 = 0;
            if (std.mem.indexOf(u8, obj, "\"pyLine\":")) |py_idx| {
                const num_start = py_idx + 9; // len of "pyLine":
                var num_end = num_start;
                while (num_end < obj.len and (obj[num_end] >= '0' and obj[num_end] <= '9')) : (num_end += 1) {}
                py_line = std.fmt.parseInt(u32, obj[num_start..num_end], 10) catch 0;
            }

            // Parse zigLine
            var zig_line: u32 = 0;
            if (std.mem.indexOf(u8, obj, "\"zigLine\":")) |zig_idx| {
                const num_start = zig_idx + 10; // len of "zigLine":
                var num_end = num_start;
                while (num_end < obj.len and (obj[num_end] >= '0' and obj[num_end] <= '9')) : (num_end += 1) {}
                zig_line = std.fmt.parseInt(u32, obj[num_start..num_end], 10) catch 0;
            }

            if (py_line > 0 and zig_line > 0) {
                mappings.append(allocator, CodeMapping{ .py_line = py_line, .zig_line = zig_line }) catch {};
            }

            pos = obj_end + 1;
        }
    }

    if (source_file == null) return null;

    return DebugInfo{
        .source_file = source_file.?,
        .mappings = mappings.toOwnedSlice(allocator) catch return null,
        .allocator = allocator,
    };
}

/// Global debug info cache (loaded once per execution)
var global_debug_info: ?DebugInfo = null;
var debug_info_loaded: bool = false;

/// Get cached debug info for current executable
pub fn getDebugInfo(allocator: std.mem.Allocator) ?*const DebugInfo {
    if (!debug_info_loaded) {
        global_debug_info = loadDebugInfoForExecutable(allocator);
        debug_info_loaded = true;
    }
    if (global_debug_info) |*info| {
        return info;
    }
    return null;
}

/// Translate a Zig line number to Python line number
/// Returns the Zig line if no mapping found
pub fn translateLine(allocator: std.mem.Allocator, zig_line: u32) u32 {
    if (getDebugInfo(allocator)) |info| {
        if (info.zigToPythonLine(zig_line)) |py_line| {
            return py_line;
        }
    }
    return zig_line;
}

/// Get the source file name (Python file)
pub fn getSourceFile(allocator: std.mem.Allocator) ?[]const u8 {
    if (getDebugInfo(allocator)) |info| {
        return info.source_file;
    }
    return null;
}

/// Print a Python-style error message with source location
/// Format: File "filename.py", line N, in <module>
///         ErrorType: message
pub fn printPythonError(
    allocator: std.mem.Allocator,
    error_type: []const u8,
    message: []const u8,
    zig_line: ?u32,
) void {
    // Use formatPythonError to build the message, then write to stderr
    const formatted = formatPythonErrorTraceback(allocator, error_type, message, zig_line);
    defer if (formatted.len > 0) allocator.free(formatted);

    _ = std.posix.write(std.posix.STDERR_FILENO, formatted) catch {};
}

/// Format a Python-style traceback (internal helper)
fn formatPythonErrorTraceback(
    allocator: std.mem.Allocator,
    error_type: []const u8,
    message: []const u8,
    zig_line: ?u32,
) []const u8 {
    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    // Try to get debug info for Python source file
    if (getDebugInfo(allocator)) |info| {
        const py_line = if (zig_line) |zl| info.zigToPythonLine(zl) else null;

        writer.print("Traceback (most recent call last):\n", .{}) catch {};
        if (py_line) |line| {
            writer.print("  File \"{s}\", line {d}\n", .{ info.source_file, line }) catch {};
        } else {
            writer.print("  File \"{s}\"\n", .{info.source_file}) catch {};
        }
    } else {
        writer.print("Traceback (most recent call last):\n", .{}) catch {};
        if (zig_line) |zl| {
            writer.print("  <compiled code>, zig line {d}\n", .{zl}) catch {};
        }
    }

    writer.print("{s}: {s}\n", .{ error_type, message }) catch {};

    return buf.toOwnedSlice(allocator) catch "";
}

/// Format error message with Python source location (returns allocated string)
pub fn formatPythonError(
    allocator: std.mem.Allocator,
    error_type: []const u8,
    message: []const u8,
    zig_line: ?u32,
) []const u8 {
    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    // Try to get debug info for Python source file
    if (getDebugInfo(allocator)) |info| {
        const py_line = if (zig_line) |zl| info.zigToPythonLine(zl) else null;

        if (py_line) |line| {
            writer.print("{s} (File \"{s}\", line {d}): {s}", .{ error_type, info.source_file, line, message }) catch {};
        } else {
            writer.print("{s} (File \"{s}\"): {s}", .{ error_type, info.source_file, message }) catch {};
        }
    } else {
        writer.print("{s}: {s}", .{ error_type, message }) catch {};
    }

    return buf.toOwnedSlice(allocator) catch error_type;
}

test "parse debug json" {
    const json =
        \\{
        \\  "version": 1,
        \\  "sourceFile": "/tmp/test.py",
        \\  "mappings": [
        \\    {"pyLine": 1, "zigLine": 12},
        \\    {"pyLine": 4, "zigLine": 16}
        \\  ]
        \\}
    ;

    const info = parseDebugJson(std.testing.allocator, json) orelse {
        try std.testing.expect(false);
        return;
    };
    defer @constCast(&info).deinit();

    try std.testing.expectEqualStrings("/tmp/test.py", info.source_file);
    try std.testing.expectEqual(@as(usize, 2), info.mappings.len);
    try std.testing.expectEqual(@as(u32, 1), info.zigToPythonLine(12).?);
    try std.testing.expectEqual(@as(u32, 4), info.zigToPythonLine(16).?);
    try std.testing.expectEqual(@as(u32, 1), info.zigToPythonLine(14).?); // Between mappings
}
