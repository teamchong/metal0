/// String Tokenization
/// Handles reading string literals including prefixed and triple-quoted strings

const std = @import("std");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

const Token = types.Token;
const Position = types.Position;
const TokenType = types.TokenType;

/// Read a string literal starting at current position
/// Expects the tokenizer to be positioned at the opening quote
pub fn readString(
    source: []const u8,
    pos: *usize,
    line: *u32,
    col: *u32,
    start: Position,
) Token {
    const quote = source[pos.*];
    advance(source, pos, line, col);

    // Check for triple quote
    const triple = peek(source, pos.*, 0) == quote and peek(source, pos.*, 1) == quote;
    if (triple) {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
    }

    const str_start = pos.*;
    while (pos.* < source.len) {
        const c = source[pos.*];
        if (c == '\\' and pos.* + 1 < source.len) {
            advance(source, pos, line, col);
            advance(source, pos, line, col);
            continue;
        }
        if (triple) {
            if (c == quote and peek(source, pos.*, 1) == quote and peek(source, pos.*, 2) == quote) {
                const str_end = pos.*;
                advance(source, pos, line, col);
                advance(source, pos, line, col);
                advance(source, pos, line, col);
                return Token{
                    .type_ = .STRING,
                    .start = start,
                    .end = currentPos(pos.*, line.*, col.*),
                    .string = source[str_start..str_end],
                };
            }
        } else {
            if (c == quote) {
                const str_end = pos.*;
                advance(source, pos, line, col);
                return Token{
                    .type_ = .STRING,
                    .start = start,
                    .end = currentPos(pos.*, line.*, col.*),
                    .string = source[str_start..str_end],
                };
            }
            if (c == '\n') {
                return Token{
                    .type_ = .ERRORTOKEN,
                    .start = start,
                    .end = currentPos(pos.*, line.*, col.*),
                    .string = "unterminated string",
                };
            }
        }
        advance(source, pos, line, col);
    }

    return Token{
        .type_ = .ERRORTOKEN,
        .start = start,
        .end = currentPos(pos.*, line.*, col.*),
        .string = "unterminated string",
    };
}

/// Read a prefixed string (r"...", b"...", f"...", etc.)
pub fn readPrefixedString(
    source: []const u8,
    pos: *usize,
    line: *u32,
    col: *u32,
    start: Position,
) Token {
    const prefix_start = pos.*;
    while (pos.* < source.len and helpers.isStringPrefix(source[pos.*])) {
        advance(source, pos, line, col);
    }
    const prefix = source[prefix_start..pos.*];

    if (pos.* < source.len and (source[pos.*] == '"' or source[pos.*] == '\'')) {
        var token = readString(source, pos, line, col, start);
        token.prefix = prefix;

        // Check for f-string
        for (prefix) |c| {
            if (c == 'f' or c == 'F') {
                token.type_ = .FSTRING_START;
                break;
            }
        }
        return token;
    }

    // Not a string, treat as name
    return Token{
        .type_ = .NAME,
        .start = start,
        .end = currentPos(pos.*, line.*, col.*),
        .string = prefix,
    };
}

// ============================================================================
// Helper Functions
// ============================================================================

fn advance(source: []const u8, pos: *usize, line: *u32, col: *u32) void {
    if (pos.* < source.len) {
        if (source[pos.*] == '\n') {
            line.* += 1;
            col.* = 0;
        } else {
            col.* += 1;
        }
        pos.* += 1;
    }
}

fn peek(source: []const u8, pos: usize, offset: usize) ?u8 {
    const idx = pos + offset;
    if (idx < source.len) {
        return source[idx];
    }
    return null;
}

fn currentPos(pos: usize, line: u32, col: u32) Position {
    return Position{
        .line = line,
        .column = col,
        .offset = pos,
    };
}
