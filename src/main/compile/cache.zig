/// Compilation cache management (content-hash based)
///
/// Cache structure under .metal0/cache/:
/// - {module}.zig   - Generated Zig source
/// - {module}.o     - Compiled object file
/// - {module}.o.hash - Source hash for incremental detection
const std = @import("std");
const build_dirs = @import("../../build_dirs.zig");

/// Compute SHA256 hash of source content
pub fn computeHash(source: []const u8) [32]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &hash, .{});
    return hash;
}

/// Get cache file path for a binary
pub fn getCachePath(allocator: std.mem.Allocator, bin_path: []const u8) ![]const u8 {
    // Cache file in .metal0/cache/: {name}.hash
    return try std.fmt.allocPrint(allocator, "{s}.hash", .{bin_path});
}

/// Check if recompilation is needed (compare source hash with cached hash)
pub fn shouldRecompile(allocator: std.mem.Allocator, source: []const u8, bin_path: []const u8) !bool {
    // Check if binary exists
    std.fs.cwd().access(bin_path, .{}) catch return true; // Binary missing, must compile

    // Compute current source hash
    const current_hash = computeHash(source);

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
    const hash = computeHash(source);

    // Convert hash to hex string (manually)
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    // Write to cache file
    const cache_path = try getCachePath(allocator, bin_path);
    defer allocator.free(cache_path);

    const file = try std.fs.cwd().createFile(cache_path, .{});
    defer file.close();

    try file.writeAll(&hex_buf);
}
