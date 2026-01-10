//! test.test_future_stmt.test_braces - Tests for `from __future__ import braces`
//!
//! This is Python's famous Easter egg joke. When you try to import braces
//! (to use C-style curly braces for blocks), Python raises a SyntaxError
//! with the message "not a chance".
//!
//! Python uses indentation for block structure, and this feature will
//! intentionally never be implemented.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Block Delimiter Styles
// ============================================================================

/// Different languages use different block delimiters
pub const BlockStyle = enum {
    /// Python: indentation-based blocks
    indentation,
    /// C/Java/JavaScript: curly braces {}
    braces,
    /// Ruby: begin/end keywords
    keywords,
    /// Lisp: parentheses ()
    parentheses,
    /// Haskell: layout rules (like Python) or braces
    layout,

    pub fn name(self: BlockStyle) []const u8 {
        return switch (self) {
            .indentation => "indentation",
            .braces => "braces",
            .keywords => "keywords",
            .parentheses => "parentheses",
            .layout => "layout",
        };
    }

    /// Get example syntax for each style
    pub fn example(self: BlockStyle) []const u8 {
        return switch (self) {
            .indentation =>
            \\if condition:
            \\    do_something()
            ,
            .braces =>
            \\if (condition) {
            \\    do_something();
            \\}
            ,
            .keywords =>
            \\if condition
            \\    do_something
            \\end
            ,
            .parentheses =>
            \\(if condition
            \\    (do-something))
            ,
            .layout =>
            \\if condition
            \\  do_something
            ,
        };
    }

    /// Get the block opening token
    pub fn openToken(self: BlockStyle) []const u8 {
        return switch (self) {
            .indentation => ":",
            .braces => "{",
            .keywords => "begin",
            .parentheses => "(",
            .layout => "where",
        };
    }

    /// Get the block closing token
    pub fn closeToken(self: BlockStyle) []const u8 {
        return switch (self) {
            .indentation => "", // Dedent
            .braces => "}",
            .keywords => "end",
            .parentheses => ")",
            .layout => "", // Dedent
        };
    }
};

// ============================================================================
// Braces Easter Egg
// ============================================================================

/// The famous braces easter egg
pub const BracesEasterEgg = struct {
    /// The error message when attempting to import braces
    pub const error_message = "not a chance";

    /// Additional snarky messages
    pub const messages = [_][]const u8{
        "not a chance",
        "Seriously? Braces in Python?",
        "Python prefers significant whitespace",
        "The Zen of Python: Explicit is better than implicit",
        "Indentation is not a bug, it's a feature",
    };

    /// Check if this "feature" will ever be implemented
    pub fn willBeImplemented() bool {
        return false; // Never!
    }

    /// Get a random snarky message
    pub fn getRandomMessage(index: usize) []const u8 {
        return messages[index % messages.len];
    }

    /// Simulate attempting to import braces
    pub fn attemptImport() error{SyntaxError}!void {
        return error.SyntaxError;
    }
};

// ============================================================================
// Indentation Tracker
// ============================================================================

/// Tracks indentation levels
pub const IndentTracker = struct {
    levels: std.ArrayListUnmanaged(usize),
    allocator: std.mem.Allocator,
    spaces_per_indent: usize = 4,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .levels = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.levels.deinit(self.allocator);
    }

    /// Push a new indentation level
    pub fn push(self: *Self, level: usize) !void {
        if (self.levels.items.len > 0) {
            const current = self.currentLevel();
            if (level <= current) {
                return error.IndentError;
            }
        }
        try self.levels.append(self.allocator, level);
    }

    /// Pop an indentation level
    pub fn pop(self: *Self) ?usize {
        if (self.levels.items.len == 0) return null;
        return self.levels.pop();
    }

    /// Get current indentation level
    pub fn currentLevel(self: Self) usize {
        if (self.levels.items.len == 0) return 0;
        return self.levels.items[self.levels.items.len - 1];
    }

    /// Get nesting depth
    pub fn depth(self: Self) usize {
        return self.levels.items.len;
    }

    /// Check if a new line's indent is valid
    pub fn isValidIndent(self: Self, spaces: usize) bool {
        if (spaces == 0 and self.depth() == 0) return true;
        if (spaces > self.currentLevel()) return true; // Indent
        // Check if it's a dedent to a previous level
        for (self.levels.items) |level| {
            if (spaces == level) return true;
        }
        return false;
    }
};

// ============================================================================
// Whitespace Analysis
// ============================================================================

/// Analyzes whitespace in Python code
pub const WhitespaceAnalyzer = struct {
    uses_tabs: bool = false,
    uses_spaces: bool = false,
    inconsistent_indent: bool = false,
    max_indent: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Analyze a line's leading whitespace
    pub fn analyzeLine(self: *Self, line: []const u8) usize {
        var spaces: usize = 0;

        for (line) |c| {
            switch (c) {
                ' ' => {
                    spaces += 1;
                    self.uses_spaces = true;
                },
                '\t' => {
                    spaces += 8; // Tab = 8 spaces conventionally
                    self.uses_tabs = true;
                },
                else => break,
            }
        }

        if (self.uses_tabs and self.uses_spaces) {
            self.inconsistent_indent = true;
        }

        if (spaces > self.max_indent) {
            self.max_indent = spaces;
        }

        return spaces;
    }

    /// Check if code has consistent indentation
    pub fn isConsistent(self: Self) bool {
        return !self.inconsistent_indent;
    }

    /// Get a warning message if inconsistent
    pub fn getWarning(self: Self) ?[]const u8 {
        if (self.inconsistent_indent) {
            return "TabError: inconsistent use of tabs and spaces in indentation";
        }
        return null;
    }
};

// ============================================================================
// Brace Converter (hypothetical)
// ============================================================================

/// Converts between brace-style and Python-style (for fun)
pub const BraceConverter = struct {
    indent_size: usize = 4,

    const Self = @This();

    pub fn init(indent_size: usize) Self {
        return .{ .indent_size = indent_size };
    }

    /// Convert braces to Python indentation (hypothetically)
    pub fn bracesToPython(self: Self, allocator: std.mem.Allocator, code: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        var d: usize = 0;
        var in_string = false;

        for (code) |c| {
            if (c == '"' or c == '\'') {
                in_string = !in_string;
                try result.append(allocator, c);
                continue;
            }

            if (in_string) {
                try result.append(allocator, c);
                continue;
            }

            switch (c) {
                '{' => {
                    try result.append(allocator, ':');
                    try result.append(allocator, '\n');
                    d += 1;
                    try self.appendIndent(allocator, &result, d);
                },
                '}' => {
                    if (d > 0) d -= 1;
                    try result.append(allocator, '\n');
                    try self.appendIndent(allocator, &result, d);
                },
                ';' => {
                    try result.append(allocator, '\n');
                    try self.appendIndent(allocator, &result, d);
                },
                else => {
                    try result.append(allocator, c);
                },
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    fn appendIndent(self: Self, allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), d: usize) !void {
        for (0..d * self.indent_size) |_| {
            try result.append(allocator, ' ');
        }
    }

    /// Count braces in code
    pub fn countBraces(code: []const u8) struct { open: usize, close: usize } {
        var open: usize = 0;
        var close: usize = 0;
        var in_string = false;

        for (code) |c| {
            if (c == '"' or c == '\'') {
                in_string = !in_string;
                continue;
            }
            if (in_string) continue;

            if (c == '{') open += 1;
            if (c == '}') close += 1;
        }

        return .{ .open = open, .close = close };
    }
};

// ============================================================================
// Zen of Python References
// ============================================================================

/// The Zen of Python principles related to whitespace
pub const ZenOfPython = struct {
    pub const principles = [_][]const u8{
        "Beautiful is better than ugly.",
        "Explicit is better than implicit.",
        "Simple is better than complex.",
        "Flat is better than nested.",
        "Sparse is better than dense.",
        "Readability counts.",
        "Special cases aren't special enough to break the rules.",
    };

    /// Why Python uses indentation
    pub fn whyIndentation() []const u8 {
        return "Indentation makes code structure visible and enforces readable formatting.";
    }

    /// Response to "why no braces?"
    pub fn whyNoBraces() []const u8 {
        return "Braces are redundant when indentation already shows structure. " ++
            "Python makes the implicit explicit - if you indent your code anyway, " ++
            "why not make it meaningful?";
    }

    /// Get a random principle
    pub fn getPrinciple(index: usize) []const u8 {
        return principles[index % principles.len];
    }
};

// ============================================================================
// Language Comparison
// ============================================================================

/// Comparison with other languages' block delimiters
pub const LanguageComparison = struct {
    /// Language info struct
    pub const LanguageInfo = struct {
        name: []const u8,
        style: BlockStyle,
        year: u16,
    };

    pub const languages = [_]LanguageInfo{
        .{ .name = "Python", .style = .indentation, .year = 1991 },
        .{ .name = "C", .style = .braces, .year = 1972 },
        .{ .name = "Ruby", .style = .keywords, .year = 1995 },
        .{ .name = "Lisp", .style = .parentheses, .year = 1958 },
        .{ .name = "Haskell", .style = .layout, .year = 1990 },
    };

    /// Find language by name
    pub fn findLanguage(name_str: []const u8) ?LanguageInfo {
        for (languages) |lang| {
            if (std.mem.eql(u8, lang.name, name_str)) {
                return lang;
            }
        }
        return null;
    }

    /// Get languages using a specific style
    pub fn languagesWithStyle(style: BlockStyle) usize {
        var count: usize = 0;
        for (languages) |lang| {
            if (lang.style == style) count += 1;
        }
        return count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "block_style_names" {
    try testing.expectEqualStrings("indentation", BlockStyle.indentation.name());
    try testing.expectEqualStrings("braces", BlockStyle.braces.name());
    try testing.expectEqualStrings("keywords", BlockStyle.keywords.name());
}

test "block_style_tokens" {
    try testing.expectEqualStrings(":", BlockStyle.indentation.openToken());
    try testing.expectEqualStrings("{", BlockStyle.braces.openToken());
    try testing.expectEqualStrings("}", BlockStyle.braces.closeToken());
}

test "braces_easter_egg_not_a_chance" {
    try testing.expectEqualStrings("not a chance", BracesEasterEgg.error_message);
    try testing.expect(!BracesEasterEgg.willBeImplemented());
}

test "braces_easter_egg_attempt_import" {
    try testing.expectError(error.SyntaxError, BracesEasterEgg.attemptImport());
}

test "braces_easter_egg_messages" {
    try testing.expectEqualStrings("not a chance", BracesEasterEgg.getRandomMessage(0));
    try testing.expect(BracesEasterEgg.messages.len > 1);
}

test "indent_tracker_push_pop" {
    var tracker = IndentTracker.init(testing.allocator);
    defer tracker.deinit();

    try tracker.push(4);
    try testing.expectEqual(@as(usize, 4), tracker.currentLevel());
    try testing.expectEqual(@as(usize, 1), tracker.depth());

    try tracker.push(8);
    try testing.expectEqual(@as(usize, 8), tracker.currentLevel());
    try testing.expectEqual(@as(usize, 2), tracker.depth());

    _ = tracker.pop();
    try testing.expectEqual(@as(usize, 4), tracker.currentLevel());
}

test "indent_tracker_invalid_indent" {
    var tracker = IndentTracker.init(testing.allocator);
    defer tracker.deinit();

    try tracker.push(4);
    // Trying to push a level <= current should fail
    try testing.expectError(error.IndentError, tracker.push(4));
    try testing.expectError(error.IndentError, tracker.push(2));
}

test "indent_tracker_valid_indent" {
    var tracker = IndentTracker.init(testing.allocator);
    defer tracker.deinit();

    try testing.expect(tracker.isValidIndent(0));
    try tracker.push(4);
    try testing.expect(tracker.isValidIndent(8)); // More indent
    try testing.expect(tracker.isValidIndent(4)); // Same level (dedent to this level)
    try testing.expect(!tracker.isValidIndent(2)); // Invalid level
}

test "whitespace_analyzer_spaces" {
    var analyzer = WhitespaceAnalyzer.init();

    _ = analyzer.analyzeLine("    code");
    try testing.expect(analyzer.uses_spaces);
    try testing.expect(!analyzer.uses_tabs);
    try testing.expectEqual(@as(usize, 4), analyzer.max_indent);
}

test "whitespace_analyzer_tabs" {
    var analyzer = WhitespaceAnalyzer.init();

    _ = analyzer.analyzeLine("\tcode");
    try testing.expect(analyzer.uses_tabs);
    try testing.expect(!analyzer.uses_spaces);
}

test "whitespace_analyzer_mixed" {
    var analyzer = WhitespaceAnalyzer.init();

    _ = analyzer.analyzeLine("    code");
    _ = analyzer.analyzeLine("\tmore");
    try testing.expect(analyzer.uses_tabs);
    try testing.expect(analyzer.uses_spaces);
    try testing.expect(analyzer.inconsistent_indent);
    try testing.expect(!analyzer.isConsistent());
}

test "whitespace_analyzer_warning" {
    var analyzer = WhitespaceAnalyzer.init();
    _ = analyzer.analyzeLine("    code");
    _ = analyzer.analyzeLine("\tmore");

    const warning = analyzer.getWarning();
    try testing.expect(warning != null);
    try testing.expect(std.mem.indexOf(u8, warning.?, "TabError") != null);
}

test "brace_converter_count" {
    const counts = BraceConverter.countBraces("if (x) { do(); }");
    try testing.expectEqual(@as(usize, 1), counts.open);
    try testing.expectEqual(@as(usize, 1), counts.close);
}

test "brace_converter_count_ignore_strings" {
    const counts = BraceConverter.countBraces("print(\"{}\")");
    // Braces inside strings should be ignored
    try testing.expectEqual(@as(usize, 0), counts.open);
    try testing.expectEqual(@as(usize, 0), counts.close);
}

test "zen_of_python" {
    try testing.expect(ZenOfPython.principles.len > 0);
    try testing.expectEqualStrings("Beautiful is better than ugly.", ZenOfPython.principles[0]);
}

test "zen_why_indentation" {
    const reason = ZenOfPython.whyIndentation();
    try testing.expect(reason.len > 0);
    try testing.expect(std.mem.indexOf(u8, reason, "visible") != null);
}

test "language_comparison_find" {
    const python = LanguageComparison.findLanguage("Python");
    try testing.expect(python != null);
    try testing.expectEqual(BlockStyle.indentation, python.?.style);
    try testing.expectEqual(@as(u16, 1991), python.?.year);
}

test "language_comparison_style_count" {
    try testing.expectEqual(@as(usize, 1), LanguageComparison.languagesWithStyle(.braces));
    try testing.expectEqual(@as(usize, 1), LanguageComparison.languagesWithStyle(.indentation));
}

test "block_style_example" {
    const py_example = BlockStyle.indentation.example();
    try testing.expect(std.mem.indexOf(u8, py_example, "if") != null);

    const c_example = BlockStyle.braces.example();
    try testing.expect(std.mem.indexOf(u8, c_example, "{") != null);
}
