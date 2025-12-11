/// Token Types and Structures
/// Core types for Python tokenization

const std = @import("std");

// ============================================================================
// Token Types
// ============================================================================

/// Token type enumeration
pub const TokenType = enum(u8) {
    ENDMARKER = 0,
    NAME = 1,
    NUMBER = 2,
    STRING = 3,
    NEWLINE = 4,
    INDENT = 5,
    DEDENT = 6,
    LPAR = 7, // (
    RPAR = 8, // )
    LSQB = 9, // [
    RSQB = 10, // ]
    COLON = 11, // :
    COMMA = 12, // ,
    SEMI = 13, // ;
    PLUS = 14, // +
    MINUS = 15, // -
    STAR = 16, // *
    SLASH = 17, // /
    VBAR = 18, // |
    AMPER = 19, // &
    LESS = 20, // <
    GREATER = 21, // >
    EQUAL = 22, // =
    DOT = 23, // .
    PERCENT = 24, // %
    LBRACE = 25, // {
    RBRACE = 26, // }
    EQEQUAL = 27, // ==
    NOTEQUAL = 28, // !=
    LESSEQUAL = 29, // <=
    GREATEREQUAL = 30, // >=
    TILDE = 31, // ~
    CIRCUMFLEX = 32, // ^
    LEFTSHIFT = 33, // <<
    RIGHTSHIFT = 34, // >>
    DOUBLESTAR = 35, // **
    PLUSEQUAL = 36, // +=
    MINEQUAL = 37, // -=
    STAREQUAL = 38, // *=
    SLASHEQUAL = 39, // /=
    PERCENTEQUAL = 40, // %=
    AMPEREQUAL = 41, // &=
    VBAREQUAL = 42, // |=
    CIRCUMFLEXEQUAL = 43, // ^=
    LEFTSHIFTEQUAL = 44, // <<=
    RIGHTSHIFTEQUAL = 45, // >>=
    DOUBLESTAREQUAL = 46, // **=
    DOUBLESLASH = 47, // //
    DOUBLESLASHEQUAL = 48, // //=
    AT = 49, // @
    ATEQUAL = 50, // @=
    RARROW = 51, // ->
    ELLIPSIS = 52, // ...
    COLONEQUAL = 53, // :=
    EXCLAMATION = 54, // !
    OP = 55,
    AWAIT = 56,
    ASYNC = 57,
    TYPE_IGNORE = 58,
    TYPE_COMMENT = 59,
    SOFT_KEYWORD = 60,
    FSTRING_START = 61,
    FSTRING_MIDDLE = 62,
    FSTRING_END = 63,
    TSTRING_START = 64, // template string
    TSTRING_MIDDLE = 65,
    TSTRING_END = 66,
    COMMENT = 67,
    NL = 68, // non-terminating newline
    ERRORTOKEN = 69,
    ENCODING = 70,
    N_TOKENS = 71,
};

/// Token structure
pub const Token = struct {
    type_: TokenType,
    start: Position,
    end: Position,
    string: []const u8,
    /// For string/fstring tokens, the string prefix
    prefix: []const u8 = "",
};

/// Source position
pub const Position = struct {
    line: u32 = 1,
    column: u32 = 0,
    offset: usize = 0,
};
