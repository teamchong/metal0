//! CPython source: Lib/shlex.py
//!
//! Provides a class for making simple lexical analyzers (shell-like).
//!
//! Mirrors: CPython Lib/shlex.py

const std = @import("std");

// ============================================================================
// Shlex - Shell Lexical Analyzer
// ============================================================================

/// Shell-like lexical analyzer
pub const Shlex = struct {
    const Self = @This();

    // Input state
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    // Configuration
    commenters: []const u8,
    wordchars: []const u8,
    whitespace: []const u8,
    quotes: []const u8,
    escape: []const u8,
    escapedquotes: []const u8,
    whitespace_split: bool,
    posix: bool,
    punctuation_chars: []const u8,

    // State
    state: ?u8,
    pushback: std.ArrayList([]const u8),
    token: std.ArrayList(u8),

    // Source tracking
    infile: ?[]const u8,
    lineno: usize,

    // Debug
    debug: u8,

    pub fn init(allocator: std.mem.Allocator, input: []const u8, posix: bool, punctuation_chars: ?[]const u8) Self {
        var self = Self{
            .input = input,
            .pos = 0,
            .allocator = allocator,
            .commenters = "#",
            .wordchars = "abcdfeghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
            .whitespace = " \t\r\n",
            .quotes = "'\"",
            .escape = "\\",
            .escapedquotes = "\"",
            .whitespace_split = false,
            .posix = posix,
            .punctuation_chars = punctuation_chars orelse "",
            .state = ' ',
            .pushback = .{},
            .token = .{},
            .infile = null,
            .lineno = 1,
            .debug = 0,
        };

        // In POSIX mode, add more word characters
        if (posix) {
            self.wordchars = "abcdfeghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" ++
                "ßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ";
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.pushback.deinit(self.allocator);
        self.token.deinit(self.allocator);
    }

    /// Push a token back on the stack
    pub fn pushToken(self: *Self, tok: []const u8) !void {
        try self.pushback.append(self.allocator, tok);
    }

    /// Get the next input character
    fn nextchar(self: *Self) ?u8 {
        if (self.pos >= self.input.len) {
            return null;
        }
        const c = self.input[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.lineno += 1;
        }
        return c;
    }

    /// Check if character is in string
    fn inStr(s: []const u8, c: u8) bool {
        for (s) |ch| {
            if (ch == c) return true;
        }
        return false;
    }

    /// Read and return a token
    pub fn getToken(self: *Self) !?[]const u8 {
        // Check pushback first
        if (self.pushback.items.len > 0) {
            return self.pushback.pop();
        }

        self.token.clearRetainingCapacity();

        var quoted = false;
        var escapedstate: ?u8 = null;

        while (true) {
            const nextc = self.nextchar();

            if (nextc == null) {
                // End of input
                self.state = null;
                break;
            }

            const c = nextc.?;

            if (self.state == null) {
                // Shouldn't happen
                break;
            } else if (self.state == ' ') {
                // Whitespace state
                if (inStr(self.whitespace, c)) {
                    if (self.token.items.len > 0 or (self.posix and quoted)) {
                        break;
                    }
                    continue;
                } else if (inStr(self.commenters, c)) {
                    // Skip to end of line
                    while (self.nextchar()) |nc| {
                        if (nc == '\n') break;
                    }
                    self.lineno += 1;
                } else if (self.posix and inStr(self.escape, c)) {
                    escapedstate = 'a';
                    self.state = c;
                } else if (inStr(self.wordchars, c)) {
                    try self.token.append(self.allocator, c);
                    self.state = 'a';
                } else if (inStr(self.quotes, c)) {
                    if (!self.posix) {
                        try self.token.append(self.allocator, c);
                    }
                    self.state = c;
                } else if (self.whitespace_split) {
                    try self.token.append(self.allocator, c);
                    self.state = 'a';
                } else if (inStr(self.punctuation_chars, c)) {
                    try self.token.append(self.allocator, c);
                    self.state = 'c';
                } else {
                    try self.token.append(self.allocator, c);
                    if (self.token.items.len > 0 or (self.posix and quoted)) {
                        break;
                    }
                }
            } else if (self.state.? == 'c') {
                // Punctuation state
                if (inStr(self.punctuation_chars, c)) {
                    try self.token.append(self.allocator, c);
                } else {
                    if (!inStr(self.whitespace, c)) {
                        self.pos -= 1; // Push back
                    }
                    self.state = ' ';
                    break;
                }
            } else if (inStr(self.quotes, self.state.?)) {
                // Inside quotes
                quoted = true;
                if (c == self.state.?) {
                    if (!self.posix) {
                        try self.token.append(self.allocator, c);
                        self.state = ' ';
                        break;
                    } else {
                        self.state = 'a';
                    }
                } else if (self.posix and inStr(self.escape, c) and inStr(self.escapedquotes, self.state.?)) {
                    escapedstate = self.state;
                    self.state = c;
                } else {
                    try self.token.append(self.allocator, c);
                }
            } else if (inStr(self.escape, self.state.?)) {
                // Escape state
                if (inStr(self.quotes, escapedstate orelse 0) and c != self.state.? and c != escapedstate.?) {
                    try self.token.append(self.allocator, self.state.?);
                }
                try self.token.append(self.allocator, c);
                self.state = escapedstate;
            } else if (self.state.? == 'a') {
                // Word state
                if (inStr(self.whitespace, c)) {
                    self.state = ' ';
                    if (self.token.items.len > 0 or (self.posix and quoted)) {
                        break;
                    }
                    continue;
                } else if (inStr(self.commenters, c)) {
                    // Skip to end of line
                    while (self.nextchar()) |nc| {
                        if (nc == '\n') break;
                    }
                    self.lineno += 1;
                    self.state = ' ';
                    if (self.token.items.len > 0 or (self.posix and quoted)) {
                        break;
                    }
                } else if (self.posix and inStr(self.quotes, c)) {
                    self.state = c;
                } else if (self.posix and inStr(self.escape, c)) {
                    escapedstate = 'a';
                    self.state = c;
                } else if (inStr(self.wordchars, c) or inStr(self.quotes, c) or (self.whitespace_split and !inStr(self.punctuation_chars, c))) {
                    try self.token.append(self.allocator, c);
                } else if (inStr(self.punctuation_chars, c)) {
                    self.pos -= 1; // Push back
                    self.state = ' ';
                    if (self.token.items.len > 0 or (self.posix and quoted)) {
                        break;
                    }
                } else {
                    self.pos -= 1; // Push back
                    self.state = ' ';
                    if (self.token.items.len > 0) {
                        break;
                    }
                }
            }
        }

        if (self.token.items.len > 0) {
            return try self.allocator.dupe(u8, self.token.items);
        }
        return null;
    }

    /// Iterate over all tokens
    pub fn iterator(self: *Self) Iterator {
        return .{ .shlex = self };
    }

    pub const Iterator = struct {
        shlex: *Self,

        pub fn next(self: *Iterator) ?[]const u8 {
            return self.shlex.getToken() catch null;
        }
    };

    /// Split a string with POSIX shell rules
    pub fn split(allocator: std.mem.Allocator, s: []const u8, comments: bool, posix: bool) ![][]const u8 {
        var lex = init(allocator, s, posix, null);
        defer lex.deinit();

        if (!comments) {
            lex.commenters = "";
        }

        var result: std.ArrayList([]const u8) = .{};
        errdefer {
            for (result.items) |item| {
                allocator.free(item);
            }
            result.deinit(allocator);
        }

        while (try lex.getToken()) |tok| {
            try result.append(allocator, tok);
        }

        return result.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Split a string using shell-like syntax
pub fn split(allocator: std.mem.Allocator, s: []const u8) ![][]const u8 {
    return Shlex.split(allocator, s, false, true);
}

/// Quote a string for safe use in a shell command
pub fn quote(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) {
        return try allocator.dupe(u8, "''");
    }

    // Check if quoting is needed
    var needs_quoting = false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.' and c != '/') {
            needs_quoting = true;
            break;
        }
    }

    if (!needs_quoting) {
        return try allocator.dupe(u8, s);
    }

    // Use single quotes, escaping any existing single quotes
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    try result.append(allocator, '\'');
    for (s) |c| {
        if (c == '\'') {
            try result.appendSlice(allocator, "'\"'\"'");
        } else {
            try result.append(allocator, c);
        }
    }
    try result.append(allocator, '\'');

    return result.toOwnedSlice(allocator);
}

/// Join a list of words into a shell command
pub fn join(allocator: std.mem.Allocator, split_command: []const []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (split_command, 0..) |word, i| {
        if (i > 0) {
            try result.append(allocator, ' ');
        }
        const quoted = try quote(allocator, word);
        defer allocator.free(quoted);
        try result.appendSlice(allocator, quoted);
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "split basic" {
    const allocator = std.testing.allocator;
    const result = try split(allocator, "echo hello world");
    defer {
        for (result) |item| {
            allocator.free(item);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("echo", result[0]);
    try std.testing.expectEqualStrings("hello", result[1]);
    try std.testing.expectEqualStrings("world", result[2]);
}

test "split with quotes" {
    const allocator = std.testing.allocator;
    const result = try split(allocator, "echo 'hello world'");
    defer {
        for (result) |item| {
            allocator.free(item);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("echo", result[0]);
    try std.testing.expectEqualStrings("hello world", result[1]);
}

test "split with double quotes" {
    const allocator = std.testing.allocator;
    const result = try split(allocator, "echo \"hello world\"");
    defer {
        for (result) |item| {
            allocator.free(item);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("echo", result[0]);
    try std.testing.expectEqualStrings("hello world", result[1]);
}

test "quote simple" {
    const allocator = std.testing.allocator;
    const result = try quote(allocator, "hello");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello", result);
}

test "quote with spaces" {
    const allocator = std.testing.allocator;
    const result = try quote(allocator, "hello world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'hello world'", result);
}

test "quote empty string" {
    const allocator = std.testing.allocator;
    const result = try quote(allocator, "");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("''", result);
}

test "quote with single quote" {
    const allocator = std.testing.allocator;
    const result = try quote(allocator, "it's");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'it'\"'\"'s'", result);
}

test "join" {
    const allocator = std.testing.allocator;
    const words = [_][]const u8{ "echo", "hello world", "test" };
    const result = try join(allocator, &words);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("echo 'hello world' test", result);
}

test "Shlex init" {
    const allocator = std.testing.allocator;
    var lex = Shlex.init(allocator, "test input", true, null);
    defer lex.deinit();

    try std.testing.expect(lex.posix);
    try std.testing.expectEqual(@as(usize, 1), lex.lineno);
}
