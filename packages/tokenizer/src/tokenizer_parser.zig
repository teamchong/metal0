/// JSON parsing for tokenizer initialization
/// Part of tokenizer.zig split (was lines 490-695, inside Tokenizer struct)

const std = @import("std");
const Allocator = std.mem.Allocator;
const helpers = @import("tokenizer_helpers.zig");
const Pair = helpers.Pair;
const PairContext = helpers.PairContext;
const StringHashContext = helpers.StringHashContext;
const TrieNode = helpers.TrieNode;
const builder = @import("tokenizer_builder.zig");
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;

/// Tokenizer structure (forward declaration for parser)
pub const TokenizerData = struct {
    vocab: std.StringHashMap(u32),
    vocab_r: std.AutoHashMap(u32, []const u8),
    merges: std.ArrayList(Pair),
    merges_map: std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    split_table: std.AutoHashMap(u32, Pair),
    pattern_str: []const u8,
    trie: ?*TrieNode,
    aho_corasick: ?AhoCorasick,
    next_prefix_match: []u32,
    allocator: Allocator,
};

/// Parse tokenizer from raw JSON data (manual parser for WASM/freestanding)
pub fn initFromData(json_data: []const u8, allocator: Allocator) !TokenizerData {
    // Manual JSON parser (std.json doesn't work in WASM freestanding)
    var vocab = std.StringHashMap(u32).init(allocator);
    errdefer vocab.deinit();

    var vocab_r = std.AutoHashMap(u32, []const u8).init(allocator);
    errdefer vocab_r.deinit();

    // Find "vocab" key
    var i: usize = 0;
    var found = false;
    while (i < json_data.len) : (i += 1) {
        if (i + 7 <= json_data.len and
            json_data[i] == '"' and
            json_data[i+1] == 'v' and
            json_data[i+2] == 'o' and
            json_data[i+3] == 'c' and
            json_data[i+4] == 'a' and
            json_data[i+5] == 'b' and
            json_data[i+6] == '"') {
            i += 7;
            found = true;
            break;
        }
    }
    if (!found) return error.InvalidJson;

    // Skip whitespace and ':'
    while (i < json_data.len and (json_data[i] == ' ' or json_data[i] == '\t' or json_data[i] == '\n' or json_data[i] == '\r' or json_data[i] == ':')) : (i += 1) {}

    // Expect '{'
    if (i >= json_data.len or json_data[i] != '{') return error.InvalidJson;
    i += 1;

    // Parse entries
    while (i < json_data.len) {
        // Skip whitespace
        while (i < json_data.len and (json_data[i] == ' ' or json_data[i] == '\t' or json_data[i] == '\n' or json_data[i] == '\r' or json_data[i] == ',')) : (i += 1) {}

        if (i >= json_data.len) break;
        if (json_data[i] == '}') break;

        // Parse key
        if (json_data[i] != '"') return error.InvalidJson;
        i += 1;

        const key_start = i;
        while (i < json_data.len and json_data[i] != '"') : (i += 1) {}
        if (i >= json_data.len) return error.InvalidJson;

        const key = json_data[key_start..i];
        i += 1;

        // Decode base64
        const decoder = std.base64.standard.Decoder;
        const decoded_size = try decoder.calcSizeForSlice(key);  // Exact size, not max
        const token_bytes = try allocator.alloc(u8, decoded_size);
        try decoder.decode(token_bytes, key);
        const token = token_bytes[0..decoded_size];

        // Skip whitespace and ':'
        while (i < json_data.len and (json_data[i] == ' ' or json_data[i] == '\t' or json_data[i] == '\n' or json_data[i] == '\r' or json_data[i] == ':')) : (i += 1) {}

        // Parse value
        if (i >= json_data.len) return error.InvalidJson;

        var rank: u32 = 0;
        while (i < json_data.len and json_data[i] >= '0' and json_data[i] <= '9') : (i += 1) {
            rank = rank * 10 + (json_data[i] - '0');
        }

        try vocab.put(token, rank);
        try vocab_r.put(rank, token);
    }

    const merges = std.ArrayList(Pair){};

    // Build split_table by reverse-engineering vocab (rs-bpe algorithm)
    var split_table = std.AutoHashMap(u32, Pair).init(allocator);
    errdefer split_table.deinit();
    var merges_map = std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage).initContext(allocator, PairContext{});
    errdefer merges_map.deinit();

    try builder.buildSplitTable(&vocab_r, &vocab, &split_table, &merges_map, allocator);

    const trie: ?*TrieNode = null;

    // Build Aho-Corasick automaton for fast vocab lookup
    const aho_corasick = try builder.buildAhoCorasick(&vocab_r, allocator);

    // Build next_prefix_match table (rs-bpe optimization)
    const next_prefix_match = try builder.buildNextPrefixMatch(&vocab_r, aho_corasick.?, allocator);

    const pattern_str = try allocator.dupe(u8,
        "'s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +"
    );

    return TokenizerData{
        .vocab = vocab,
        .vocab_r = vocab_r,
        .merges = merges,
        .merges_map = merges_map,
        .split_table = split_table,
        .pattern_str = pattern_str,
        .trie = trie,
        .aho_corasick = aho_corasick,
        .next_prefix_match = next_prefix_match,
        .allocator = allocator,
    };
}

/// Parse tokenizer from file path
pub fn initFromFile(tokenizer_path: []const u8, allocator: Allocator) !TokenizerData {
    const file = try std.fs.cwd().openFile(tokenizer_path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer = try allocator.alloc(u8, stat.size);
    defer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    _ = bytes_read;

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        buffer,
        .{},
    );
    defer parsed.deinit();

    return try parseTokenizerJSON(parsed.value, allocator);
}

/// Parse tokenizer from std.json.Value
pub fn parseTokenizerJSON(root_value: std.json.Value, allocator: Allocator) !TokenizerData {
    var vocab = std.StringHashMap(u32).init(allocator);
    errdefer vocab.deinit();

    var vocab_r = std.AutoHashMap(u32, []const u8).init(allocator);
    errdefer vocab_r.deinit();

    var merges = std.ArrayList(Pair){};
    errdefer merges.deinit(allocator);

    var merges_map = std.HashMap(
        Pair,
        u32,
        PairContext,
        std.hash_map.default_max_load_percentage,
    ).initContext(allocator, PairContext{});
    errdefer merges_map.deinit();

    var split_table = std.AutoHashMap(u32, Pair).init(allocator);
    errdefer split_table.deinit();

    const root = root_value.object;

    // Simple format: {"vocab": {"base64_token": rank, ...}}
    const vocab_json = root.get("vocab").?.object;
    var it = vocab_json.iterator();

    while (it.next()) |entry| {
        const token_b64 = entry.key_ptr.*;
        const rank = @as(u32, @intCast(entry.value_ptr.*.integer));

        // Decode base64
        const decoder = std.base64.standard.Decoder;
        const decoded_size = try decoder.calcSizeForSlice(token_b64);  // Exact size, not max
        const token_bytes = try allocator.alloc(u8, decoded_size);
        try decoder.decode(token_bytes, token_b64);
        const token = token_bytes[0..decoded_size];

        try vocab.put(token, rank);
        try vocab_r.put(rank, token);
    }

    // No explicit merges needed - we'll look up concatenated bytes in vocab
    // Skip trie (use vocab-based BPE)
    const trie: ?*TrieNode = null;

    // Build split_table for BacktrackEncoder validation
    try builder.buildSplitTable(&vocab_r, &vocab, &split_table, &merges_map, allocator);

    // Build Aho-Corasick automaton for fast vocab lookup
    const aho_corasick = try builder.buildAhoCorasick(&vocab_r, allocator);

    // Build next_prefix_match table (rs-bpe optimization)
    const next_prefix_match = try builder.buildNextPrefixMatch(&vocab_r, aho_corasick.?, allocator);

    // Default GPT-4 pattern
    const pattern_str = try allocator.dupe(u8,
        "'s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +"
    );

    return TokenizerData{
        .vocab = vocab,
        .vocab_r = vocab_r,
        .merges = merges,
        .merges_map = merges_map,
        .split_table = split_table,
        .pattern_str = pattern_str,
        .trie = trie,
        .aho_corasick = aho_corasick,
        .next_prefix_match = next_prefix_match,
        .allocator = allocator,
    };
}
