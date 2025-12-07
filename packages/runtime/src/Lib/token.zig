//! Python 'token' module - Token constants
//!
//! Provides constants for token types used by the tokenizer.
//!
//! Mirrors: CPython Lib/token.py

const std = @import("std");

// ============================================================================
// Token Type Constants
// ============================================================================

pub const ENDMARKER = 0;
pub const NAME = 1;
pub const NUMBER = 2;
pub const STRING = 3;
pub const NEWLINE = 4;
pub const INDENT = 5;
pub const DEDENT = 6;
pub const LPAR = 7;
pub const RPAR = 8;
pub const LSQB = 9;
pub const RSQB = 10;
pub const COLON = 11;
pub const COMMA = 12;
pub const SEMI = 13;
pub const PLUS = 14;
pub const MINUS = 15;
pub const STAR = 16;
pub const SLASH = 17;
pub const VBAR = 18;
pub const AMPER = 19;
pub const LESS = 20;
pub const GREATER = 21;
pub const EQUAL = 22;
pub const DOT = 23;
pub const PERCENT = 24;
pub const LBRACE = 25;
pub const RBRACE = 26;
pub const EQEQUAL = 27;
pub const NOTEQUAL = 28;
pub const LESSEQUAL = 29;
pub const GREATEREQUAL = 30;
pub const TILDE = 31;
pub const CIRCUMFLEX = 32;
pub const LEFTSHIFT = 33;
pub const RIGHTSHIFT = 34;
pub const DOUBLESTAR = 35;
pub const PLUSEQUAL = 36;
pub const MINEQUAL = 37;
pub const STAREQUAL = 38;
pub const SLASHEQUAL = 39;
pub const PERCENTEQUAL = 40;
pub const AMPEREQUAL = 41;
pub const VBAREQUAL = 42;
pub const CIRCUMFLEXEQUAL = 43;
pub const LEFTSHIFTEQUAL = 44;
pub const RIGHTSHIFTEQUAL = 45;
pub const DOUBLESTAREQUAL = 46;
pub const DOUBLESLASH = 47;
pub const DOUBLESLASHEQUAL = 48;
pub const AT = 49;
pub const ATEQUAL = 50;
pub const RARROW = 51;
pub const ELLIPSIS = 52;
pub const COLONEQUAL = 53;
pub const EXCLAMATION = 54;
pub const OP = 55;
pub const AWAIT = 56;
pub const ASYNC = 57;
pub const TYPE_IGNORE = 58;
pub const TYPE_COMMENT = 59;
pub const SOFT_KEYWORD = 60;
pub const FSTRING_START = 61;
pub const FSTRING_MIDDLE = 62;
pub const FSTRING_END = 63;
pub const COMMENT = 64;
pub const NL = 65;
pub const ERRORTOKEN = 66;
pub const ENCODING = 67;
pub const N_TOKENS = 68;
pub const NT_OFFSET = 256;

// ============================================================================
// Token Names
// ============================================================================

pub const tok_name = [_][]const u8{
    "ENDMARKER",
    "NAME",
    "NUMBER",
    "STRING",
    "NEWLINE",
    "INDENT",
    "DEDENT",
    "LPAR",
    "RPAR",
    "LSQB",
    "RSQB",
    "COLON",
    "COMMA",
    "SEMI",
    "PLUS",
    "MINUS",
    "STAR",
    "SLASH",
    "VBAR",
    "AMPER",
    "LESS",
    "GREATER",
    "EQUAL",
    "DOT",
    "PERCENT",
    "LBRACE",
    "RBRACE",
    "EQEQUAL",
    "NOTEQUAL",
    "LESSEQUAL",
    "GREATEREQUAL",
    "TILDE",
    "CIRCUMFLEX",
    "LEFTSHIFT",
    "RIGHTSHIFT",
    "DOUBLESTAR",
    "PLUSEQUAL",
    "MINEQUAL",
    "STAREQUAL",
    "SLASHEQUAL",
    "PERCENTEQUAL",
    "AMPEREQUAL",
    "VBAREQUAL",
    "CIRCUMFLEXEQUAL",
    "LEFTSHIFTEQUAL",
    "RIGHTSHIFTEQUAL",
    "DOUBLESTAREQUAL",
    "DOUBLESLASH",
    "DOUBLESLASHEQUAL",
    "AT",
    "ATEQUAL",
    "RARROW",
    "ELLIPSIS",
    "COLONEQUAL",
    "EXCLAMATION",
    "OP",
    "AWAIT",
    "ASYNC",
    "TYPE_IGNORE",
    "TYPE_COMMENT",
    "SOFT_KEYWORD",
    "FSTRING_START",
    "FSTRING_MIDDLE",
    "FSTRING_END",
    "COMMENT",
    "NL",
    "ERRORTOKEN",
    "ENCODING",
};

// ============================================================================
// Exact Token Types
// ============================================================================

/// Map of string representation to token type
pub const EXACT_TOKEN_TYPES = std.StaticStringMap(u8).initComptime(.{
    .{ "!=", NOTEQUAL },
    .{ "%", PERCENT },
    .{ "%=", PERCENTEQUAL },
    .{ "&", AMPER },
    .{ "&=", AMPEREQUAL },
    .{ "(", LPAR },
    .{ ")", RPAR },
    .{ "*", STAR },
    .{ "**", DOUBLESTAR },
    .{ "**=", DOUBLESTAREQUAL },
    .{ "*=", STAREQUAL },
    .{ "+", PLUS },
    .{ "+=", PLUSEQUAL },
    .{ ",", COMMA },
    .{ "-", MINUS },
    .{ "-=", MINEQUAL },
    .{ "->", RARROW },
    .{ ".", DOT },
    .{ "...", ELLIPSIS },
    .{ "/", SLASH },
    .{ "//", DOUBLESLASH },
    .{ "//=", DOUBLESLASHEQUAL },
    .{ "/=", SLASHEQUAL },
    .{ ":", COLON },
    .{ ":=", COLONEQUAL },
    .{ ";", SEMI },
    .{ "<", LESS },
    .{ "<<", LEFTSHIFT },
    .{ "<<=", LEFTSHIFTEQUAL },
    .{ "<=", LESSEQUAL },
    .{ "=", EQUAL },
    .{ "==", EQEQUAL },
    .{ ">", GREATER },
    .{ ">=", GREATEREQUAL },
    .{ ">>", RIGHTSHIFT },
    .{ ">>=", RIGHTSHIFTEQUAL },
    .{ "@", AT },
    .{ "@=", ATEQUAL },
    .{ "[", LSQB },
    .{ "]", RSQB },
    .{ "^", CIRCUMFLEX },
    .{ "^=", CIRCUMFLEXEQUAL },
    .{ "{", LBRACE },
    .{ "|", VBAR },
    .{ "|=", VBAREQUAL },
    .{ "}", RBRACE },
    .{ "~", TILDE },
    .{ "!", EXCLAMATION },
});

// ============================================================================
// Functions
// ============================================================================

/// Check if token is terminal
pub fn ISTERMINAL(x: anytype) bool {
    return x < NT_OFFSET;
}

/// Check if token is non-terminal
pub fn ISNONTERMINAL(x: anytype) bool {
    return x >= NT_OFFSET;
}

/// Check if token is EOF
pub fn ISEOF(x: anytype) bool {
    return x == ENDMARKER;
}

/// Get the name of a token type
pub fn getName(token_type: u8) []const u8 {
    if (token_type < tok_name.len) {
        return tok_name[token_type];
    }
    return "UNKNOWN";
}

/// Get token type from name
pub fn getType(name: []const u8) ?u8 {
    for (tok_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) {
            return @intCast(i);
        }
    }
    return null;
}

/// Get exact token type from string representation
pub fn getExactType(string: []const u8) ?u8 {
    return EXACT_TOKEN_TYPES.get(string);
}

// ============================================================================
// Token Type Enum
// ============================================================================

/// Token type enum for type-safe usage
pub const TokenType = enum(u8) {
    ENDMARKER = 0,
    NAME = 1,
    NUMBER = 2,
    STRING = 3,
    NEWLINE = 4,
    INDENT = 5,
    DEDENT = 6,
    LPAR = 7,
    RPAR = 8,
    LSQB = 9,
    RSQB = 10,
    COLON = 11,
    COMMA = 12,
    SEMI = 13,
    PLUS = 14,
    MINUS = 15,
    STAR = 16,
    SLASH = 17,
    VBAR = 18,
    AMPER = 19,
    LESS = 20,
    GREATER = 21,
    EQUAL = 22,
    DOT = 23,
    PERCENT = 24,
    LBRACE = 25,
    RBRACE = 26,
    EQEQUAL = 27,
    NOTEQUAL = 28,
    LESSEQUAL = 29,
    GREATEREQUAL = 30,
    TILDE = 31,
    CIRCUMFLEX = 32,
    LEFTSHIFT = 33,
    RIGHTSHIFT = 34,
    DOUBLESTAR = 35,
    PLUSEQUAL = 36,
    MINEQUAL = 37,
    STAREQUAL = 38,
    SLASHEQUAL = 39,
    PERCENTEQUAL = 40,
    AMPEREQUAL = 41,
    VBAREQUAL = 42,
    CIRCUMFLEXEQUAL = 43,
    LEFTSHIFTEQUAL = 44,
    RIGHTSHIFTEQUAL = 45,
    DOUBLESTAREQUAL = 46,
    DOUBLESLASH = 47,
    DOUBLESLASHEQUAL = 48,
    AT = 49,
    ATEQUAL = 50,
    RARROW = 51,
    ELLIPSIS = 52,
    COLONEQUAL = 53,
    EXCLAMATION = 54,
    OP = 55,
    AWAIT = 56,
    ASYNC = 57,
    TYPE_IGNORE = 58,
    TYPE_COMMENT = 59,
    SOFT_KEYWORD = 60,
    FSTRING_START = 61,
    FSTRING_MIDDLE = 62,
    FSTRING_END = 63,
    COMMENT = 64,
    NL = 65,
    ERRORTOKEN = 66,
    ENCODING = 67,

    pub fn name(self: TokenType) []const u8 {
        return tok_name[@intFromEnum(self)];
    }

    pub fn isTerminal(self: TokenType) bool {
        return @intFromEnum(self) < NT_OFFSET;
    }

    pub fn isEof(self: TokenType) bool {
        return self == .ENDMARKER;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "token constants" {
    try std.testing.expectEqual(@as(u8, 0), ENDMARKER);
    try std.testing.expectEqual(@as(u8, 1), NAME);
    try std.testing.expectEqual(@as(u8, 2), NUMBER);
    try std.testing.expectEqual(@as(u8, 3), STRING);
    try std.testing.expectEqual(@as(u8, 4), NEWLINE);
    try std.testing.expectEqual(@as(u8, 5), INDENT);
    try std.testing.expectEqual(@as(u8, 6), DEDENT);
}

test "tok_name" {
    try std.testing.expectEqualStrings("ENDMARKER", tok_name[0]);
    try std.testing.expectEqualStrings("NAME", tok_name[1]);
    try std.testing.expectEqualStrings("NUMBER", tok_name[2]);
}

test "getName" {
    try std.testing.expectEqualStrings("ENDMARKER", getName(0));
    try std.testing.expectEqualStrings("NAME", getName(1));
    try std.testing.expectEqualStrings("UNKNOWN", getName(255));
}

test "getType" {
    try std.testing.expectEqual(@as(?u8, 0), getType("ENDMARKER"));
    try std.testing.expectEqual(@as(?u8, 1), getType("NAME"));
    try std.testing.expectEqual(@as(?u8, null), getType("INVALID"));
}

test "getExactType" {
    try std.testing.expectEqual(@as(?u8, PLUS), getExactType("+"));
    try std.testing.expectEqual(@as(?u8, MINUS), getExactType("-"));
    try std.testing.expectEqual(@as(?u8, EQEQUAL), getExactType("=="));
    try std.testing.expectEqual(@as(?u8, null), getExactType("invalid"));
}

test "ISTERMINAL" {
    try std.testing.expect(ISTERMINAL(NAME));
    try std.testing.expect(ISTERMINAL(NUMBER));
}

test "ISNONTERMINAL" {
    try std.testing.expect(ISNONTERMINAL(NT_OFFSET));
    try std.testing.expect(ISNONTERMINAL(NT_OFFSET + 1));
    try std.testing.expect(!ISNONTERMINAL(NAME));
}

test "ISEOF" {
    try std.testing.expect(ISEOF(ENDMARKER));
    try std.testing.expect(!ISEOF(NAME));
}

test "TokenType enum" {
    try std.testing.expectEqualStrings("NAME", TokenType.NAME.name());
    try std.testing.expect(TokenType.NAME.isTerminal());
    try std.testing.expect(TokenType.ENDMARKER.isEof());
}
