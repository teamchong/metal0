//! Source code inspection with file access
//!
//! Provides functions to get source code information from files:
//! - getfile, getsourcefile: Get the source file of an object
//! - getsourceFromFile: Read source code from a file
//! - getsourcelines_from_file: Get source lines from a file
//! - getsource, getsourcelines: Get source for runtime objects (limited in AOT)
//! - getdoc: Get docstrings
//! - getcomments: Get comments (not available in AOT)
//! - cleandoc: Clean up indentation from docstrings

const std = @import("std");

// ============================================================================
// Source code inspection with file access
// ============================================================================

/// Get the source file of an object using Zig's @src() builtin
/// For types defined in known modules, attempts to infer source location
pub fn getfile(comptime T: type) ?[]const u8 {
    // Check if type has a __file__ declaration (Python convention)
    if (@hasDecl(T, "__file__")) {
        return @field(T, "__file__");
    }
    // Check for source_location from @src()
    if (@hasDecl(T, "__source_location__")) {
        const loc = @field(T, "__source_location__");
        return loc.file;
    }
    // Use @typeName to extract module path info
    const name = @typeName(T);
    // Strip package prefix if present (e.g., "runtime.Lib.foo")
    if (std.mem.indexOf(u8, name, ".")) |_| {
        // Type is from a known module, but we can't get exact file without debug info
        return null;
    }
    return null;
}

/// Get the source file name
pub fn getsourcefile(comptime T: type) ?[]const u8 {
    return getfile(T);
}

/// Source cache for runtime file reading
const SourceCache = struct {
    const max_files = 16;
    const max_file_size = 1024 * 1024; // 1MB max per file

    var cached_files: [max_files]CachedFile = [_]CachedFile{.{}} ** max_files;
    var cache_index: usize = 0;

    const CachedFile = struct {
        path: [256]u8 = [_]u8{0} ** 256,
        path_len: usize = 0,
        content: ?[]const u8 = null,
        lines: ?[]const []const u8 = null,
    };

    fn get(path: []const u8) ?*CachedFile {
        for (&cached_files) |*cf| {
            if (cf.path_len == path.len and
                std.mem.eql(u8, cf.path[0..cf.path_len], path))
            {
                return cf;
            }
        }
        return null;
    }
};

/// Get the source code of an object from file
/// Takes a file path and returns the file contents
pub fn getsourceFromFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > SourceCache.max_file_size) {
        return error.FileTooLarge;
    }

    return try file.readToEndAlloc(allocator, SourceCache.max_file_size);
}

/// Get the source code of an object
pub fn getsource(_: anytype) ?[]const u8 {
    // For runtime values, we'd need the associated source file
    // This requires debug info that's not available at runtime
    return null;
}

/// Get the source lines from a file
pub fn getsourcelines_from_file(allocator: std.mem.Allocator, path: []const u8) !struct {
    lines: std.ArrayList([]const u8),
    content: []u8,
} {
    const content = try getsourceFromFile(allocator, path);
    errdefer allocator.free(content);

    var lines: std.ArrayList([]const u8) = .{};
    errdefer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        try lines.append(allocator, line);
    }

    return .{ .lines = lines, .content = content };
}

/// Get the source lines
pub fn getsourcelines(_: anytype) ?struct { lines: []const []const u8, lineno: usize } {
    // For runtime values without debug info, return null
    return null;
}

/// Get the docstring
pub fn getdoc(comptime T: type) ?[]const u8 {
    if (@hasDecl(T, "__doc__")) {
        return @field(T, "__doc__");
    }
    return null;
}

/// Get the comments
/// NOTE: In AOT compilation, source comments are not preserved at runtime.
/// This function always returns null. Use doc comments (__doc__) instead.
pub fn getcomments(_: anytype) ?[]const u8 {
    // AOT limitation: Source code and comments are not available at runtime.
    // The Python AST is parsed at compile time and source is not retained.
    return null;
}

// ============================================================================
// Cleandoc utility
// ============================================================================

/// Clean up indentation from docstrings
pub fn cleandoc(allocator: std.mem.Allocator, doc: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var lines = std.mem.splitScalar(u8, doc, '\n');
    var first = true;
    var min_indent: usize = std.math.maxInt(usize);

    // Find minimum indentation
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var indent: usize = 0;
        for (line) |c| {
            if (c == ' ' or c == '\t') {
                indent += 1;
            } else {
                break;
            }
        }
        if (indent < line.len) {
            min_indent = @min(min_indent, indent);
        }
    }

    if (min_indent == std.math.maxInt(usize)) {
        min_indent = 0;
    }

    // Reset and strip
    lines = std.mem.splitScalar(u8, doc, '\n');
    while (lines.next()) |line| {
        if (!first) {
            try result.append(allocator, '\n');
        }
        first = false;

        if (line.len >= min_indent) {
            try result.appendSlice(allocator, line[min_indent..]);
        }
    }

    return result.toOwnedSlice(allocator);
}
