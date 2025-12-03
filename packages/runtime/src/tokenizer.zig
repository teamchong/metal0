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
    return tok;
}

/// Encode text to token IDs (uses global tokenizer if initialized)
pub fn encode(allocator: std.mem.Allocator, text: []const u8) ![]u32 {
    _ = allocator;
    if (global_tokenizer) |tok| {
        return tok.encode(text);
    }
    return error.TokenizerNotInitialized;
}

/// Decode token IDs back to text
pub fn decode(allocator: std.mem.Allocator, tokens: []const u32) ![]const u8 {
    _ = allocator;
    if (global_tokenizer) |tok| {
        return tok.decode(tokens);
    }
    return error.TokenizerNotInitialized;
}
