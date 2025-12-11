//! CPython source: Lib/tokenize.py
//!
//! Provides a lexical scanner for Python source code.
//!
//! Mirrors: CPython Lib/tokenize.py
//!
//! This module is split into:
//! - types.zig - Token types and structures (TokenType, TokenInfo, Position)
//! - tokens.zig - Token constants and exact token mappings
//! - tokenizer.zig - Tokenizer class implementation
//! - utils.zig - Module-level utility functions and tests

// Re-export types
pub const TokenType = @import("tokenize/types.zig").TokenType;
pub const Position = @import("tokenize/types.zig").Position;
pub const TokenInfo = @import("tokenize/types.zig").TokenInfo;

// Re-export token constants
pub const EXACT_TOKEN_TYPES = @import("tokenize/tokens.zig").EXACT_TOKEN_TYPES;

// Re-export tokenizer
pub const Tokenizer = @import("tokenize/tokenizer.zig").Tokenizer;

// Re-export utility functions
pub const tokenize = @import("tokenize/utils.zig").tokenize;
pub const generate_tokens = @import("tokenize/utils.zig").generate_tokens;
pub const detect_encoding = @import("tokenize/utils.zig").detect_encoding;
pub const untokenize = @import("tokenize/utils.zig").untokenize;
pub const tok_name = @import("tokenize/utils.zig").tok_name;

// Re-export tests
comptime {
    _ = @import("tokenize/utils.zig");
}
