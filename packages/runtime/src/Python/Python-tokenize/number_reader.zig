/// Number Tokenization
/// Handles reading numeric literals (integers, floats, complex, hex, octal, binary)

const std = @import("std");
const types = @import("types.zig");

const Token = types.Token;
const Position = types.Position;
const TokenType = types.TokenType;

/// Read a numeric literal starting at current position
pub fn readNumber(
    source: []const u8,
    pos: *usize,
    line: *u32,
    col: *u32,
    start: Position,
) Token {
    const num_start = pos.*;

    // Check for hex, octal, binary
    if (source[pos.*] == '0' and pos.* + 1 < source.len) {
        const next = source[pos.* + 1];
        if (next == 'x' or next == 'X') {
            advance(source, pos, line, col);
            advance(source, pos, line, col);
            while (pos.* < source.len and std.ascii.isHex(source[pos.*])) {
                advance(source, pos, line, col);
            }
            return Token{
                .type_ = .NUMBER,
                .start = start,
                .end = currentPos(pos.*, line.*, col.*),
                .string = source[num_start..pos.*],
            };
        }
        if (next == 'o' or next == 'O') {
            advance(source, pos, line, col);
            advance(source, pos, line, col);
            while (pos.* < source.len and source[pos.*] >= '0' and source[pos.*] <= '7') {
                advance(source, pos, line, col);
            }
            return Token{
                .type_ = .NUMBER,
                .start = start,
                .end = currentPos(pos.*, line.*, col.*),
                .string = source[num_start..pos.*],
            };
        }
        if (next == 'b' or next == 'B') {
            advance(source, pos, line, col);
            advance(source, pos, line, col);
            while (pos.* < source.len and (source[pos.*] == '0' or source[pos.*] == '1')) {
                advance(source, pos, line, col);
            }
            return Token{
                .type_ = .NUMBER,
                .start = start,
                .end = currentPos(pos.*, line.*, col.*),
                .string = source[num_start..pos.*],
            };
        }
    }

    // Integer part
    while (pos.* < source.len and (std.ascii.isDigit(source[pos.*]) or source[pos.*] == '_')) {
        advance(source, pos, line, col);
    }

    // Decimal part
    if (pos.* < source.len and source[pos.*] == '.') {
        if (pos.* + 1 < source.len and std.ascii.isDigit(source[pos.* + 1])) {
            advance(source, pos, line, col);
            while (pos.* < source.len and (std.ascii.isDigit(source[pos.*]) or source[pos.*] == '_')) {
                advance(source, pos, line, col);
            }
        }
    }

    // Exponent
    if (pos.* < source.len and (source[pos.*] == 'e' or source[pos.*] == 'E')) {
        advance(source, pos, line, col);
        if (pos.* < source.len and (source[pos.*] == '+' or source[pos.*] == '-')) {
            advance(source, pos, line, col);
        }
        while (pos.* < source.len and std.ascii.isDigit(source[pos.*])) {
            advance(source, pos, line, col);
        }
    }

    // Complex suffix
    if (pos.* < source.len and (source[pos.*] == 'j' or source[pos.*] == 'J')) {
        advance(source, pos, line, col);
    }

    return Token{
        .type_ = .NUMBER,
        .start = start,
        .end = currentPos(pos.*, line.*, col.*),
        .string = source[num_start..pos.*],
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

fn currentPos(pos: usize, line: u32, col: u32) Position {
    return Position{
        .line = line,
        .column = col,
        .offset = pos,
    };
}
