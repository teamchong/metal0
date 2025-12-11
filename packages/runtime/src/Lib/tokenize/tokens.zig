//! Token constants and mappings
//!
//! Maps token strings to their exact token types.

const std = @import("std");
const types = @import("types.zig");
const TokenType = types.TokenType;

// ============================================================================
// Exact Token Types Map
// ============================================================================

const ExactTokenMap = std.StaticStringMap(TokenType);

pub const EXACT_TOKEN_TYPES = ExactTokenMap.initComptime(.{
    .{ "(", .LPAR },
    .{ ")", .RPAR },
    .{ "[", .LSQB },
    .{ "]", .RSQB },
    .{ ":", .COLON },
    .{ ",", .COMMA },
    .{ ";", .SEMI },
    .{ "+", .PLUS },
    .{ "-", .MINUS },
    .{ "*", .STAR },
    .{ "/", .SLASH },
    .{ "|", .VBAR },
    .{ "&", .AMPER },
    .{ "<", .LESS },
    .{ ">", .GREATER },
    .{ "=", .EQUAL },
    .{ ".", .DOT },
    .{ "%", .PERCENT },
    .{ "{", .LBRACE },
    .{ "}", .RBRACE },
    .{ "==", .EQEQUAL },
    .{ "!=", .NOTEQUAL },
    .{ "<=", .LESSEQUAL },
    .{ ">=", .GREATEREQUAL },
    .{ "~", .TILDE },
    .{ "^", .CIRCUMFLEX },
    .{ "<<", .LEFTSHIFT },
    .{ ">>", .RIGHTSHIFT },
    .{ "**", .DOUBLESTAR },
    .{ "+=", .PLUSEQUAL },
    .{ "-=", .MINEQUAL },
    .{ "*=", .STAREQUAL },
    .{ "/=", .SLASHEQUAL },
    .{ "%=", .PERCENTEQUAL },
    .{ "&=", .AMPEREQUAL },
    .{ "|=", .VBAREQUAL },
    .{ "^=", .CIRCUMFLEXEQUAL },
    .{ "<<=", .LEFTSHIFTEQUAL },
    .{ ">>=", .RIGHTSHIFTEQUAL },
    .{ "**=", .DOUBLESTAREQUAL },
    .{ "//", .DOUBLESLASH },
    .{ "//=", .DOUBLESLASHEQUAL },
    .{ "@", .AT },
    .{ "@=", .ATEQUAL },
    .{ "->", .RARROW },
    .{ "...", .ELLIPSIS },
    .{ ":=", .COLONEQUAL },
    .{ "!", .EXCLAMATION },
});
