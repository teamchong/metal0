/// Binary serialization for Aho-Corasick automaton
/// Enables instant loading (43s → <0.1s) by caching pre-built automaton
const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;
const State = @import("aho_corasick.zig").State;

/// Magic number to identify cache file format
const MAGIC: [4]u8 = .{ 'A', 'C', 'Z', '1' }; // AhoCorasick Zig v1
const VERSION: u32 = 1;

/// Save automaton to binary file
pub fn save(ac: *const AhoCorasick, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Calculate total size needed
    const header_size = 4 + 4 + 4 + 4; // magic + version + states_len + outputs_len
    const state_size = 4 + 1 + 4 + 4; // base + check + fail + output_pos = 13 bytes
    const total_size = header_size + (ac.states.len * state_size) + (ac.outputs.len * 4);

    // Allocate buffer and write
    var buffer = try std.heap.page_allocator.alloc(u8, total_size);
    defer std.heap.page_allocator.free(buffer);

    var pos: usize = 0;

    // Header
    @memcpy(buffer[pos..][0..4], &MAGIC);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], VERSION, .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.states.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.outputs.len), .little);
    pos += 4;

    // States
    for (ac.states) |state| {
        std.mem.writeInt(u32, buffer[pos..][0..4], state.base, .little);
        pos += 4;
        buffer[pos] = state.check;
        pos += 1;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.fail, .little);
        pos += 4;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.output_pos, .little);
        pos += 4;
    }

    // Outputs
    for (ac.outputs) |output| {
        std.mem.writeInt(u32, buffer[pos..][0..4], output, .little);
        pos += 4;
    }

    _ = try file.writeAll(buffer[0..pos]);
}

/// Load automaton from binary file
pub fn load(allocator: Allocator, path: []const u8) ?AhoCorasick {
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    // Get file size
    const stat = file.stat() catch return null;
    if (stat.size < 16) return null; // Minimum header size

    // Read entire file into buffer
    const buffer = std.heap.page_allocator.alloc(u8, stat.size) catch return null;
    defer std.heap.page_allocator.free(buffer);

    const bytes_read = file.readAll(buffer) catch return null;
    if (bytes_read != stat.size) return null;

    var pos: usize = 0;

    // Verify header
    if (!std.mem.eql(u8, buffer[pos..][0..4], &MAGIC)) return null;
    pos += 4;

    const version = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    if (version != VERSION) return null;

    const states_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const outputs_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;

    // Allocate arrays
    const states = allocator.alloc(State, states_len) catch return null;
    errdefer allocator.free(states);

    const outputs = allocator.alloc(u32, outputs_len) catch return null;
    errdefer allocator.free(outputs);

    // Read states
    for (states) |*state| {
        state.base = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.check = buffer[pos];
        pos += 1;
        state.fail = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.output_pos = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read outputs
    for (outputs) |*output| {
        output.* = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    return AhoCorasick{
        .states = states,
        .outputs = outputs,
        .allocator = allocator,
    };
}

/// Get cache file path for a vocab file
pub fn getCachePath(allocator: Allocator, vocab_path: []const u8) ![]u8 {
    // Use hash of vocab path to generate cache filename
    const hash = std.hash.Wyhash.hash(0, vocab_path);
    return std.fmt.allocPrint(allocator, "/tmp/ac_cache_{x}.bin", .{hash});
}

// ============================================================================
// Ultra-fast full tokenizer cache (includes vocab bytes - no JSON/base64!)
// ============================================================================

const ULTRA_MAGIC: [4]u8 = .{ 'T', 'K', 'F', '1' }; // ToKenizer Full v1
const ULTRA_VERSION: u32 = 1;

pub const UltraCache = struct {
    /// Token bytes indexed by token ID (token_id -> bytes)
    vocab_bytes: [][]const u8,
    ac: AhoCorasick,
    split_table: []Pair,
    next_prefix_match: []u32,
};

/// Save ultra cache (vocab bytes + AC + split_table + next_prefix_match)
/// This caches EVERYTHING including the vocab strings, eliminating JSON parsing
pub fn saveUltra(
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    ac: *const AhoCorasick,
    split_table: []const Pair,
    next_prefix_match: []const u32,
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const vocab_size = vocab_r.count();

    // Calculate total size needed
    // Header: magic(4) + version(4) + vocab_size(4) + ac_states(4) + ac_outputs(4) + split(4) + prefix(4) = 28
    // Per token: len(2) + bytes(variable)
    // AC: states(13 each) + outputs(4 each)
    // Split: pairs(8 each)
    // Prefix: u32(4 each)

    var total_vocab_bytes: usize = 0;
    var token_id: u32 = 0;
    while (token_id < vocab_size) : (token_id += 1) {
        if (vocab_r.get(token_id)) |bytes| {
            total_vocab_bytes += 2 + bytes.len; // u16 len + bytes
        } else {
            total_vocab_bytes += 2; // Just len=0
        }
    }

    const header_size = 28;
    const state_size = 4 + 1 + 4 + 4; // base + check + fail + output_pos = 13 bytes
    const pair_size = 8; // left + right
    const total_size = header_size +
        total_vocab_bytes +
        (ac.states.len * state_size) +
        (ac.outputs.len * 4) +
        (split_table.len * pair_size) +
        (next_prefix_match.len * 4);

    var buffer = try std.heap.page_allocator.alloc(u8, total_size);
    defer std.heap.page_allocator.free(buffer);

    var pos: usize = 0;

    // Header
    @memcpy(buffer[pos..][0..4], &ULTRA_MAGIC);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], ULTRA_VERSION, .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(vocab_size), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.states.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.outputs.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(split_table.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(next_prefix_match.len), .little);
    pos += 4;

    // Vocab bytes (ordered by token ID for O(1) lookup)
    token_id = 0;
    while (token_id < vocab_size) : (token_id += 1) {
        if (vocab_r.get(token_id)) |bytes| {
            std.mem.writeInt(u16, buffer[pos..][0..2], @intCast(bytes.len), .little);
            pos += 2;
            @memcpy(buffer[pos..][0..bytes.len], bytes);
            pos += bytes.len;
        } else {
            std.mem.writeInt(u16, buffer[pos..][0..2], 0, .little);
            pos += 2;
        }
    }

    // AC States
    for (ac.states) |state| {
        std.mem.writeInt(u32, buffer[pos..][0..4], state.base, .little);
        pos += 4;
        buffer[pos] = state.check;
        pos += 1;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.fail, .little);
        pos += 4;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.output_pos, .little);
        pos += 4;
    }

    // AC Outputs
    for (ac.outputs) |output| {
        std.mem.writeInt(u32, buffer[pos..][0..4], output, .little);
        pos += 4;
    }

    // Split table
    for (split_table) |pair| {
        std.mem.writeInt(u32, buffer[pos..][0..4], pair.left, .little);
        pos += 4;
        std.mem.writeInt(u32, buffer[pos..][0..4], pair.right, .little);
        pos += 4;
    }

    // Next prefix match
    for (next_prefix_match) |prefix| {
        std.mem.writeInt(u32, buffer[pos..][0..4], prefix, .little);
        pos += 4;
    }

    _ = try file.writeAll(buffer[0..pos]);
}

/// Load ultra cache - returns null if cache invalid/missing
/// Uses mmap for zero-copy loading (7s → <0.1s)
pub fn loadUltra(allocator: Allocator, path: []const u8) ?UltraCache {
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const stat = file.stat() catch return null;
    if (stat.size < 28) return null; // Minimum header size

    // Use mmap instead of read for zero-copy loading
    const buffer = std.posix.mmap(
        null,
        stat.size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    ) catch return null;
    // Don't unmap - we'll reference this memory directly

    var pos: usize = 0;

    // Verify header
    if (!std.mem.eql(u8, buffer[pos..][0..4], &ULTRA_MAGIC)) return null;
    pos += 4;

    const version = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    if (version != ULTRA_VERSION) return null;

    const vocab_size = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const states_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const outputs_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const split_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const prefix_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;

    // Allocate vocab_bytes array (just pointers, not data - zero copy!)
    const vocab_bytes = allocator.alloc([]const u8, vocab_size) catch return null;
    errdefer allocator.free(vocab_bytes);

    // Read vocab bytes - ZERO COPY: slice directly into mmap'd buffer
    var token_id: u32 = 0;
    while (token_id < vocab_size) : (token_id += 1) {
        const len = std.mem.readInt(u16, buffer[pos..][0..2], .little);
        pos += 2;
        if (len > 0) {
            // Direct slice into mmap'd memory - no allocation!
            vocab_bytes[token_id] = buffer[pos..][0..len];
            pos += len;
        } else {
            vocab_bytes[token_id] = "";
        }
    }

    // Allocate AC arrays
    const states = allocator.alloc(State, states_len) catch return null;
    errdefer allocator.free(states);

    const outputs = allocator.alloc(u32, outputs_len) catch return null;
    errdefer allocator.free(outputs);

    const split_table = allocator.alloc(Pair, split_len) catch return null;
    errdefer allocator.free(split_table);

    const next_prefix_match = allocator.alloc(u32, prefix_len) catch return null;
    errdefer allocator.free(next_prefix_match);

    // Read AC states
    for (states) |*state| {
        state.base = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.check = buffer[pos];
        pos += 1;
        state.fail = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.output_pos = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read AC outputs
    for (outputs) |*output| {
        output.* = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read split table
    for (split_table) |*pair| {
        pair.left = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        pair.right = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read next prefix match
    for (next_prefix_match) |*prefix| {
        prefix.* = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    return UltraCache{
        .vocab_bytes = vocab_bytes,
        .ac = AhoCorasick{
            .states = states,
            .outputs = outputs,
            .allocator = allocator,
        },
        .split_table = split_table,
        .next_prefix_match = next_prefix_match,
    };
}

/// Check if cache is valid (exists and newer than vocab file)
pub fn isCacheValid(vocab_path: []const u8, cache_path: []const u8) bool {
    const vocab_stat = std.fs.cwd().statFile(vocab_path) catch return false;
    const cache_stat = std.fs.cwd().statFile(cache_path) catch return false;

    // Cache is valid if it's newer than the vocab file
    return cache_stat.mtime >= vocab_stat.mtime;
}

// ============================================================================
// Full tokenizer cache (AC + split_table + next_prefix_match)
// ============================================================================

const helpers = @import("tokenizer_helpers.zig");
const Pair = helpers.Pair;

const FULL_MAGIC: [4]u8 = .{ 'T', 'K', 'Z', '1' }; // ToKenizer Zig v1
const FULL_VERSION: u32 = 1;

pub const FullCache = struct {
    ac: AhoCorasick,
    split_table: []Pair,
    next_prefix_match: []u32,
};

/// Save full tokenizer data (AC + split_table + next_prefix_match)
pub fn saveFull(
    ac: *const AhoCorasick,
    split_table: []const Pair,
    next_prefix_match: []const u32,
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Calculate total size
    const header_size = 4 + 4 + 4 + 4 + 4 + 4; // magic + version + ac_states + ac_outputs + split + prefix
    const state_size = 4 + 1 + 4 + 4;
    const pair_size = 4 + 4; // left + right
    const total_size = header_size +
        (ac.states.len * state_size) +
        (ac.outputs.len * 4) +
        (split_table.len * pair_size) +
        (next_prefix_match.len * 4);

    var buffer = try std.heap.page_allocator.alloc(u8, total_size);
    defer std.heap.page_allocator.free(buffer);

    var pos: usize = 0;

    // Header
    @memcpy(buffer[pos..][0..4], &FULL_MAGIC);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], FULL_VERSION, .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.states.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(ac.outputs.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(split_table.len), .little);
    pos += 4;
    std.mem.writeInt(u32, buffer[pos..][0..4], @intCast(next_prefix_match.len), .little);
    pos += 4;

    // AC States
    for (ac.states) |state| {
        std.mem.writeInt(u32, buffer[pos..][0..4], state.base, .little);
        pos += 4;
        buffer[pos] = state.check;
        pos += 1;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.fail, .little);
        pos += 4;
        std.mem.writeInt(u32, buffer[pos..][0..4], state.output_pos, .little);
        pos += 4;
    }

    // AC Outputs
    for (ac.outputs) |output| {
        std.mem.writeInt(u32, buffer[pos..][0..4], output, .little);
        pos += 4;
    }

    // Split table
    for (split_table) |pair| {
        std.mem.writeInt(u32, buffer[pos..][0..4], pair.left, .little);
        pos += 4;
        std.mem.writeInt(u32, buffer[pos..][0..4], pair.right, .little);
        pos += 4;
    }

    // Next prefix match
    for (next_prefix_match) |prefix| {
        std.mem.writeInt(u32, buffer[pos..][0..4], prefix, .little);
        pos += 4;
    }

    _ = try file.writeAll(buffer[0..pos]);
}

/// Load full tokenizer data
pub fn loadFull(allocator: Allocator, path: []const u8) ?FullCache {
    return loadFullImpl(allocator, path, false);
}

fn loadFullImpl(allocator: Allocator, path: []const u8, comptime debug: bool) ?FullCache {
    _ = debug;
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const stat = file.stat() catch return null;
    if (stat.size < 24) return null;

    const buffer = std.heap.page_allocator.alloc(u8, stat.size) catch return null;
    defer std.heap.page_allocator.free(buffer);

    const bytes_read = file.readAll(buffer) catch return null;
    if (bytes_read != stat.size) return null;

    var pos: usize = 0;

    // Verify header
    if (!std.mem.eql(u8, buffer[pos..][0..4], &FULL_MAGIC)) return null;
    pos += 4;

    const version = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    if (version != FULL_VERSION) return null;

    const states_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const outputs_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const split_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;
    const prefix_len = std.mem.readInt(u32, buffer[pos..][0..4], .little);
    pos += 4;

    // Allocate all arrays
    const states = allocator.alloc(State, states_len) catch return null;
    errdefer allocator.free(states);

    const outputs = allocator.alloc(u32, outputs_len) catch return null;
    errdefer allocator.free(outputs);

    const split_table = allocator.alloc(Pair, split_len) catch return null;
    errdefer allocator.free(split_table);

    const next_prefix_match = allocator.alloc(u32, prefix_len) catch return null;
    errdefer allocator.free(next_prefix_match);

    // Read AC states
    for (states) |*state| {
        state.base = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.check = buffer[pos];
        pos += 1;
        state.fail = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        state.output_pos = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read AC outputs
    for (outputs) |*output| {
        output.* = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read split table
    for (split_table) |*pair| {
        pair.left = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
        pair.right = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    // Read next prefix match
    for (next_prefix_match) |*prefix| {
        prefix.* = std.mem.readInt(u32, buffer[pos..][0..4], .little);
        pos += 4;
    }

    return FullCache{
        .ac = AhoCorasick{
            .states = states,
            .outputs = outputs,
            .allocator = allocator,
        },
        .split_table = split_table,
        .next_prefix_match = next_prefix_match,
    };
}
