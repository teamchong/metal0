/// Operator Tokenization
/// Handles reading operators and delimiters

const std = @import("std");
const types = @import("types.zig");

const Token = types.Token;
const Position = types.Position;
const TokenType = types.TokenType;

/// Read an operator or delimiter starting at current position
pub fn readOperator(
    source: []const u8,
    pos: *usize,
    line: *u32,
    col: *u32,
    start: Position,
    bracket_level: *u32,
) Token {
    const c = source[pos.*];
    const c2 = peek(source, pos.*, 1);
    const c3 = peek(source, pos.*, 2);

    // Three-character operators
    if (c == '.' and c2 == '.' and c3 == '.') {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        return Token{ .type_ = .ELLIPSIS, .start = start, .end = currentPos(pos.*, line.*, col.*), .string = "..." };
    }
    if (c == '<' and c2 == '<' and c3 == '=') {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        return Token{ .type_ = .LEFTSHIFTEQUAL, .start = start, .end = currentPos(pos.*, line.*, col.*), .string = "<<=" };
    }
    if (c == '>' and c2 == '>' and c3 == '=') {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        return Token{ .type_ = .RIGHTSHIFTEQUAL, .start = start, .end = currentPos(pos.*, line.*, col.*), .string = ">>=" };
    }
    if (c == '*' and c2 == '*' and c3 == '=') {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        return Token{ .type_ = .DOUBLESTAREQUAL, .start = start, .end = currentPos(pos.*, line.*, col.*), .string = "**=" };
    }
    if (c == '/' and c2 == '/' and c3 == '=') {
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        advance(source, pos, line, col);
        return Token{ .type_ = .DOUBLESLASHEQUAL, .start = start, .end = currentPos(pos.*, line.*, col.*), .string = "//=" };
    }

    // Two-character operators
    const two_char_ops = [_]struct { chars: [2]u8, type_: TokenType }{
        .{ .chars = .{ '=', '=' }, .type_ = .EQEQUAL },
        .{ .chars = .{ '!', '=' }, .type_ = .NOTEQUAL },
        .{ .chars = .{ '<', '=' }, .type_ = .LESSEQUAL },
        .{ .chars = .{ '>', '=' }, .type_ = .GREATEREQUAL },
        .{ .chars = .{ '<', '<' }, .type_ = .LEFTSHIFT },
        .{ .chars = .{ '>', '>' }, .type_ = .RIGHTSHIFT },
        .{ .chars = .{ '*', '*' }, .type_ = .DOUBLESTAR },
        .{ .chars = .{ '/', '/' }, .type_ = .DOUBLESLASH },
        .{ .chars = .{ '+', '=' }, .type_ = .PLUSEQUAL },
        .{ .chars = .{ '-', '=' }, .type_ = .MINEQUAL },
        .{ .chars = .{ '*', '=' }, .type_ = .STAREQUAL },
        .{ .chars = .{ '/', '=' }, .type_ = .SLASHEQUAL },
        .{ .chars = .{ '%', '=' }, .type_ = .PERCENTEQUAL },
        .{ .chars = .{ '&', '=' }, .type_ = .AMPEREQUAL },
        .{ .chars = .{ '|', '=' }, .type_ = .VBAREQUAL },
        .{ .chars = .{ '^', '=' }, .type_ = .CIRCUMFLEXEQUAL },
        .{ .chars = .{ '@', '=' }, .type_ = .ATEQUAL },
        .{ .chars = .{ '-', '>' }, .type_ = .RARROW },
        .{ .chars = .{ ':', '=' }, .type_ = .COLONEQUAL },
    };

    if (c2) |next| {
        for (two_char_ops) |op| {
            if (c == op.chars[0] and next == op.chars[1]) {
                advance(source, pos, line, col);
                advance(source, pos, line, col);
                return Token{
                    .type_ = op.type_,
                    .start = start,
                    .end = currentPos(pos.*, line.*, col.*),
                    .string = source[start.offset..pos.*],
                };
            }
        }
    }

    // Single character operators
    advance(source, pos, line, col);
    const type_: TokenType = switch (c) {
        '(' => blk: {
            bracket_level.* += 1;
            break :blk .LPAR;
        },
        ')' => blk: {
            if (bracket_level.* > 0) bracket_level.* -= 1;
            break :blk .RPAR;
        },
        '[' => blk: {
            bracket_level.* += 1;
            break :blk .LSQB;
        },
        ']' => blk: {
            if (bracket_level.* > 0) bracket_level.* -= 1;
            break :blk .RSQB;
        },
        '{' => blk: {
            bracket_level.* += 1;
            break :blk .LBRACE;
        },
        '}' => blk: {
            if (bracket_level.* > 0) bracket_level.* -= 1;
            break :blk .RBRACE;
        },
        ':' => .COLON,
        ',' => .COMMA,
        ';' => .SEMI,
        '+' => .PLUS,
        '-' => .MINUS,
        '*' => .STAR,
        '/' => .SLASH,
        '|' => .VBAR,
        '&' => .AMPER,
        '<' => .LESS,
        '>' => .GREATER,
        '=' => .EQUAL,
        '.' => .DOT,
        '%' => .PERCENT,
        '~' => .TILDE,
        '^' => .CIRCUMFLEX,
        '@' => .AT,
        '!' => .EXCLAMATION,
        else => .ERRORTOKEN,
    };

    return Token{
        .type_ = type_,
        .start = start,
        .end = currentPos(pos.*, line.*, col.*),
        .string = source[start.offset..pos.*],
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
