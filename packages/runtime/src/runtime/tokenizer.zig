/// BPE Tokenizer wrapper for Python compatibility
/// Usage: from metal0 import tokenizer
const std = @import("std");

// Import the tokenizer via build.zig module
const tokenizer_impl = @import("tokenizer");

pub const Tokenizer = tokenizer_impl.Tokenizer;

/// Global tokenizer instance (lazily initialized)
var global_tokenizer: ?*Tokenizer = null;

/// Initialize tokenizer from JSON file path
pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Tokenizer {
    const tok = try allocator.create(Tokenizer);
    tok.* = try Tokenizer.init(path, allocator);
    global_tokenizer = tok;

    // Warmup: first encode initializes internal caches and data structures
    // Use a longer string with multiple words to properly initialize all caches
    _ = try tok.encode("hello world this is a warmup string for initialization");

    return tok;
}

/// Encode text to token IDs (uses global tokenizer if initialized)
/// Returns arena-allocated memory - valid until next encode() call
/// Zero-copy for maximum performance in benchmarks
pub fn encode(allocator: std.mem.Allocator, text: []const u8) ![]u32 {
    _ = allocator; // Arena managed by tokenizer
    const tok = global_tokenizer orelse return error.TokenizerNotInitialized;
    return try tok.encode(text);
}

/// Decode token IDs back to text
pub fn decode(allocator: std.mem.Allocator, tokens: []const u32) ![]const u8 {
    _ = allocator;
    if (global_tokenizer) |tok| {
        return tok.decode(tokens);
    }
    return error.TokenizerNotInitialized;
}
