//! CPython source: Lib/linecache.py
//!
//! Provides random access to individual lines from any file while optimizing
//! for reading Python source files.
//!
//! Mirrors: CPython Lib/linecache.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Cache Storage
// ============================================================================

const CacheEntry = struct {
    size: usize,
    mtime: i128,
    lines: [][]const u8,
    fullname: []const u8,
};

var cache: ?hashmap_helper.StringHashMap(CacheEntry) = null;
var cache_allocator: std.mem.Allocator = allocator_helper.fast_allocator;

fn initCache() void {
    if (cache == null) {
        cache = hashmap_helper.StringHashMap(CacheEntry).init(cache_allocator);
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Get a line from a file (1-indexed)
pub fn getline(filename: []const u8, lineno: usize, module_globals: ?*anyopaque) []const u8 {
    _ = module_globals;
    const lines = getlines(filename, null);
    if (lineno >= 1 and lineno <= lines.len) {
        return lines[lineno - 1];
    }
    return "";
}

/// Get all lines from a file
pub fn getlines(filename: []const u8, module_globals: ?*anyopaque) [][]const u8 {
    _ = module_globals;
    initCache();

    // Check cache
    if (cache.?.get(filename)) |entry| {
        return entry.lines;
    }

    // Try to read file
    return updateCache(filename, null) orelse &[_][]const u8{};
}

/// Clear the cache entirely or for a specific file
pub fn clearcache() void {
    initCache();
    var iter = cache.?.iterator();
    while (iter.next()) |entry| {
        cache_allocator.free(entry.key_ptr.*);
        for (entry.value_ptr.lines) |line| {
            cache_allocator.free(line);
        }
        cache_allocator.free(entry.value_ptr.lines);
        cache_allocator.free(entry.value_ptr.fullname);
    }
    cache.?.clearRetainingCapacity();
}

/// Check if a file in the cache needs to be reloaded
pub fn checkcache(filename: ?[]const u8) void {
    initCache();

    if (filename) |name| {
        if (cache.?.get(name)) |entry| {
            // Check if file was modified
            const file = std.fs.cwd().openFile(name, .{}) catch {
                _ = cache.?.remove(name);
                return;
            };
            defer file.close();

            const stat = file.stat() catch {
                _ = cache.?.remove(name);
                return;
            };

            if (stat.size != entry.size or stat.mtime != entry.mtime) {
                _ = cache.?.remove(name);
            }
        }
    } else {
        // Check all cached files
        var to_remove: std.ArrayList([]const u8) = .{};
        defer to_remove.deinit(cache_allocator);

        var iter = cache.?.iterator();
        while (iter.next()) |entry| {
            const file = std.fs.cwd().openFile(entry.key_ptr.*, .{}) catch {
                to_remove.append(cache_allocator, entry.key_ptr.*) catch unreachable;
                continue;
            };
            defer file.close();

            const stat = file.stat() catch {
                to_remove.append(cache_allocator, entry.key_ptr.*) catch unreachable;
                continue;
            };

            if (stat.size != entry.value_ptr.size or stat.mtime != entry.value_ptr.mtime) {
                to_remove.append(cache_allocator, entry.key_ptr.*) catch unreachable;
            }
        }

        for (to_remove.items) |name| {
            _ = cache.?.remove(name);
        }
    }
}

/// Update the cache for a file
pub fn updateCache(filename: []const u8, module_globals: ?*anyopaque) ?[][]const u8 {
    _ = module_globals;
    initCache();

    // Remove old entry if exists
    if (cache.?.get(filename)) |old_entry| {
        for (old_entry.lines) |line| {
            cache_allocator.free(line);
        }
        cache_allocator.free(old_entry.lines);
        cache_allocator.free(old_entry.fullname);
        _ = cache.?.remove(filename);
    }

    // Try to read the file
    const file = std.fs.cwd().openFile(filename, .{}) catch {
        // Try absolute path
        const abs_file = std.fs.openFileAbsolute(filename, .{}) catch return null;
        return readFileIntoCache(filename, abs_file);
    };

    return readFileIntoCache(filename, file);
}

fn readFileIntoCache(filename: []const u8, file: std.fs.File) ?[][]const u8 {
    defer file.close();

    const stat = file.stat() catch return null;
    const content = file.readToEndAlloc(cache_allocator, 10 * 1024 * 1024) catch return null;
    defer cache_allocator.free(content);

    // Split into lines
    var lines: std.ArrayList([]const u8) = .{};
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const owned_line = cache_allocator.dupe(u8, line) catch continue;
        lines.append(cache_allocator, owned_line) catch {
            cache_allocator.free(owned_line);
            continue;
        };
    }

    const lines_slice = lines.toOwnedSlice(cache_allocator) catch return null;
    const fullname = cache_allocator.dupe(u8, filename) catch {
        cache_allocator.free(lines_slice);
        return null;
    };
    const key = cache_allocator.dupe(u8, filename) catch {
        cache_allocator.free(fullname);
        cache_allocator.free(lines_slice);
        return null;
    };

    cache.?.put(key, .{
        .size = stat.size,
        .mtime = stat.mtime,
        .lines = lines_slice,
        .fullname = fullname,
    }) catch {
        cache_allocator.free(key);
        cache_allocator.free(fullname);
        for (lines_slice) |line| {
            cache_allocator.free(line);
        }
        cache_allocator.free(lines_slice);
        return null;
    };

    return lines_slice;
}

/// Lazily update the cache for a file
pub fn lazycache(filename: []const u8, module_globals: ?*anyopaque) bool {
    initCache();

    if (cache.?.contains(filename)) {
        return true;
    }

    return updateCache(filename, module_globals) != null;
}

/// Get source lines for syntax error display
pub fn getsourcelines(filename: []const u8, lineno: usize, context: usize) struct {
    lines: [][]const u8,
    start_lineno: usize,
} {
    const all_lines = getlines(filename, null);
    if (all_lines.len == 0) {
        return .{ .lines = &[_][]const u8{}, .start_lineno = lineno };
    }

    const start = if (lineno > context) lineno - context else 1;
    const end = @min(lineno + context, all_lines.len);

    if (start > all_lines.len) {
        return .{ .lines = &[_][]const u8{}, .start_lineno = lineno };
    }

    return .{
        .lines = all_lines[start - 1 .. end],
        .start_lineno = start,
    };
}

// ============================================================================
// Allocator Configuration
// ============================================================================

/// Set the allocator used for caching
pub fn setAllocator(allocator: std.mem.Allocator) void {
    clearcache();
    cache_allocator = allocator;
    cache = null;
}

// ============================================================================
// Tests
// ============================================================================

test "cache operations" {
    clearcache();

    // Test empty cache
    const lines = getlines("nonexistent_file.py", null);
    try std.testing.expectEqual(@as(usize, 0), lines.len);

    // Test getline with nonexistent file
    const line = getline("nonexistent_file.py", 1, null);
    try std.testing.expectEqualStrings("", line);
}

test "checkcache" {
    clearcache();
    checkcache(null);
    // Should not crash on empty cache
}

test "lazycache" {
    clearcache();
    const result = lazycache("nonexistent.py", null);
    try std.testing.expect(!result);
}

test "getsourcelines" {
    clearcache();
    const result = getsourcelines("nonexistent.py", 5, 2);
    try std.testing.expectEqual(@as(usize, 0), result.lines.len);
}
