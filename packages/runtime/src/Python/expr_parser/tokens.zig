/// Token types and structures for expression lexer
const std = @import("std");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidNumber,
    UnclosedParen,
    UnclosedString,
    OutOfMemory,
};

/// Token types for expression lexer
pub const TokenType = enum {
    Number,
    Complex, // Complex number (e.g., 2j, 3.14j)
    String,
    Plus,
    Minus,
    Star,
    Slash,
    DoubleSlash,
    Percent,
    DoubleStar,
    Tilde, // Bitwise NOT ~
    LParen,
    RParen,
    LBracket,
    RBracket,
    Comma,
    Eq,
    NotEq,
    Lt,
    Gt,
    LtE,
    GtE,
    True,
    False,
    None,
    Name,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,
};
