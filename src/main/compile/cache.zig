/// Compilation cache management (content-hash based)
///
/// Cache structure under .metal0/cache/:
/// - {module}.zig   - Generated Zig source
/// - {module}.o     - Compiled object file
/// - {module}.o.hash - Source hash for incremental detection
const std = @import("std");
const build_dirs = @import("../../build_dirs.zig");

/// Compute SHA256 hash of source content and compilation mode
/// Optimization from zell: Only hash first 1MB for large files (100-1000x faster)
/// For files >1MB, this provides excellent collision resistance with minimal cost
/// Mode is included to invalidate cache when switching between build/run modes
/// (build mode = module struct, run mode = main function for dlsym)
pub fn computeHash(source: []const u8) [32]u8 {
    return computeHashWithMode(source, "");
}

/// Compute hash including compilation mode
pub fn computeHashWithMode(source: []const u8, mode: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // For large files, only hash first 1MB (zell optimization)
    const hash_prefix_size = 1024 * 1024; // 1MB
    const bytes_to_hash = @min(source.len, hash_prefix_size);

    hasher.update(source[0..bytes_to_hash]);
    // Include mode in hash to invalidate when switching build/run
    hasher.update(mode);

    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}

/// Get cache file path for a binary
pub fn getCachePath(allocator: std.mem.Allocator, bin_path: []const u8) ![]const u8 {
    // Cache file in .metal0/cache/: {name}.hash
    return try std.fmt.allocPrint(allocator, "{s}.hash", .{bin_path});
}

/// Check if recompilation is needed (compare source hash with cached hash)
/// Mode is included in the hash to invalidate cache when switching build/run modes
pub fn shouldRecompile(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8) !bool {
    return shouldRecompileWithMode(allocator, source, bin_path, "");
}

/// Check if recompilation is needed with explicit mode
pub fn shouldRecompileWithMode(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8, mode: []const u8) !bool {
    // Check if binary exists
    std.fs.cwd().access(bin_path, .{}) catch return true; // Binary missing, must compile

    // Compute current source hash (including mode)
    const current_hash = computeHashWithMode(source, mode);

    // Read cached hash
    const cache_path = try getCachePath(allocator, bin_path);
    defer allocator.free(cache_path);

    const cached_hash_hex = std.fs.cwd().readFileAlloc(allocator, cache_path, 1024) catch {
        return true; // Cache missing, must compile
    };
    defer allocator.free(cached_hash_hex);

    // Convert hex string back to bytes
    if (cached_hash_hex.len != 64) return true; // Invalid cache

    var cached_hash: [32]u8 = undefined;
    for (0..32) |i| {
        cached_hash[i] = std.fmt.parseInt(u8, cached_hash_hex[i * 2 .. i * 2 + 2], 16) catch return true;
    }

    // Compare hashes
    return !std.mem.eql(u8, &current_hash, &cached_hash);
}

/// Update cache with new source hash
pub fn updateCache(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8) !void {
    return updateCacheWithMode(allocator, source, bin_path, "");
}

/// Update cache with new source hash including compilation mode
pub fn updateCacheWithMode(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8, mode: []const u8) !void {
    const hash = computeHashWithMode(source, mode);

    // Convert hash to hex string (manually)
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    // Write to cache file atomically (zell optimization)
    // 1. Write to .tmp file
    // 2. Sync to disk
    // 3. Atomic rename to final path
    // This prevents corrupted cache files if process crashes mid-write
    const cache_path = try getCachePath(allocator, bin_path);
    defer allocator.free(cache_path);

    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{cache_path});
    defer allocator.free(tmp_path);

    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();

        try file.writeAll(&hex_buf);

        // Ensure data is on disk before rename
        try file.sync();
    }

    // Atomic rename (OS guarantees atomicity)
    try std.fs.cwd().rename(tmp_path, cache_path);
}
