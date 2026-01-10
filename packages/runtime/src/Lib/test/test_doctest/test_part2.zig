//! test.test_doctest.test_part2 - Docstring Parser implementation
//! Parse docstrings to extract doctest examples (>>> lines and expected output).
const std = @import("std");

/// State machine states for parsing docstrings
pub const ParseState = enum {
    /// Looking for >>> prompt
    seeking_prompt,
    /// Reading continuation lines (... prompt)
    reading_continuation,
    /// Reading expected output
    reading_output,
    /// Finished with current example
    finished_example,
};

/// A single parsed example from a docstring
pub const ParsedExample = struct {
    source_lines: std.ArrayList([]const u8),
    output_lines: std.ArrayList([]const u8),
    start_line: usize,
    end_line: usize,
    indent: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .source_lines = std.ArrayList([]const u8).init(allocator),
            .output_lines = std.ArrayList([]const u8).init(allocator),
            .start_line = 0,
            .end_line = 0,
            .indent = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.source_lines.deinit();
        self.output_lines.deinit();
    }

    pub fn addSourceLine(self: *@This(), line: []const u8) !void {
        try self.source_lines.append(line);
    }

    pub fn addOutputLine(self: *@This(), line: []const u8) !void {
        try self.output_lines.append(line);
    }

    /// Join source lines into single string
    pub fn getSource(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        return joinLines(allocator, self.source_lines.items);
    }

    /// Join output lines into single string
    pub fn getOutput(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        return joinLines(allocator, self.output_lines.items);
    }

    fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]u8 {
        if (lines.len == 0) return try allocator.dupe(u8, "");

        var total_len: usize = 0;
        for (lines) |line| {
            total_len += line.len + 1; // +1 for newline
        }
        if (total_len > 0) total_len -= 1; // Remove trailing newline

        var result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (lines, 0..) |line, i| {
            @memcpy(result[pos .. pos + line.len], line);
            pos += line.len;
            if (i < lines.len - 1) {
                result[pos] = '\n';
                pos += 1;
            }
        }
        return result;
    }
};

/// Docstring parser - extracts examples from docstrings
pub const DocstringParser = struct {
    allocator: std.mem.Allocator,
    examples: std.ArrayList(ParsedExample),
    current_example: ?ParsedExample,
    state: ParseState,
    current_line: usize,
    base_indent: usize,

    pub const PROMPT = ">>> ";
    pub const CONTINUATION = "... ";

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .examples = std.ArrayList(ParsedExample).init(allocator),
            .current_example = null,
            .state = .seeking_prompt,
            .current_line = 0,
            .base_indent = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.examples.items) |*ex| {
            ex.deinit();
        }
        self.examples.deinit();
        if (self.current_example) |*ex| {
            ex.deinit();
        }
    }

    /// Parse a complete docstring and extract all examples
    pub fn parse(self: *@This(), docstring: []const u8) !void {
        var lines = std.mem.splitScalar(u8, docstring, '\n');

        while (lines.next()) |line| {
            self.current_line += 1;
            try self.processLine(line);
        }

        // Finalize any pending example
        try self.finalizeCurrentExample();
    }

    /// Process a single line
    fn processLine(self: *@This(), line: []const u8) !void {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        const indent = line.len - trimmed.len;

        switch (self.state) {
            .seeking_prompt => {
                if (std.mem.startsWith(u8, trimmed, PROMPT)) {
                    // Start new example
                    self.current_example = ParsedExample.init(self.allocator);
                    self.current_example.?.start_line = self.current_line;
                    self.current_example.?.indent = indent;
                    self.base_indent = indent;

                    const source = trimmed[PROMPT.len..];
                    try self.current_example.?.addSourceLine(source);

                    // Check if this is a multi-line statement
                    if (needsContinuation(source)) {
                        self.state = .reading_continuation;
                    } else {
                        self.state = .reading_output;
                    }
                }
            },
            .reading_continuation => {
                if (std.mem.startsWith(u8, trimmed, CONTINUATION)) {
                    const source = trimmed[CONTINUATION.len..];
                    try self.current_example.?.addSourceLine(source);

                    if (!needsContinuation(source)) {
                        self.state = .reading_output;
                    }
                } else {
                    // Unexpected end of continuation
                    self.state = .reading_output;
                    try self.processLine(line);
                }
            },
            .reading_output => {
                if (std.mem.startsWith(u8, trimmed, PROMPT)) {
                    // New example starts - finalize current
                    try self.finalizeCurrentExample();
                    self.state = .seeking_prompt;
                    try self.processLine(line);
                } else if (std.mem.startsWith(u8, trimmed, CONTINUATION)) {
                    // Continuation in output section - treat as output
                    try self.current_example.?.addOutputLine(trimmed);
                } else if (trimmed.len == 0) {
                    // Empty line - might end example
                    try self.finalizeCurrentExample();
                    self.state = .seeking_prompt;
                } else if (indent >= self.base_indent) {
                    // Output line
                    try self.current_example.?.addOutputLine(trimmed);
                } else {
                    // Dedented - end of example
                    try self.finalizeCurrentExample();
                    self.state = .seeking_prompt;
                }
            },
            .finished_example => {
                self.state = .seeking_prompt;
                try self.processLine(line);
            },
        }
    }

    /// Finalize and store the current example
    fn finalizeCurrentExample(self: *@This()) !void {
        if (self.current_example) |*example| {
            example.end_line = self.current_line;
            if (example.source_lines.items.len > 0) {
                try self.examples.append(example.*);
            } else {
                example.deinit();
            }
            self.current_example = null;
        }
    }

    /// Get count of parsed examples
    pub fn exampleCount(self: @This()) usize {
        return self.examples.items.len;
    }

    /// Check if source needs continuation (ends with :, \, or open brackets)
    fn needsContinuation(source: []const u8) bool {
        const trimmed = std.mem.trimRight(u8, source, " \t");
        if (trimmed.len == 0) return false;

        const last = trimmed[trimmed.len - 1];
        return last == ':' or last == '\\' or last == '(' or last == '[' or last == '{';
    }
};

/// Extract directive comments from example lines
pub const DirectiveParser = struct {
    pub const Directive = struct {
        name: []const u8,
        value: ?[]const u8,
        on: bool, // +DIRECTIVE vs -DIRECTIVE
    };

    /// Parse directive from comment: # doctest: +ELLIPSIS
    pub fn parseDirective(line: []const u8) ?Directive {
        const marker = "# doctest:";
        if (std.mem.indexOf(u8, line, marker)) |idx| {
            const after = std.mem.trim(u8, line[idx + marker.len ..], " \t");

            if (after.len < 2) return null;

            const on = after[0] == '+';
            if (after[0] != '+' and after[0] != '-') return null;

            const name = std.mem.trim(u8, after[1..], " \t");
            return .{
                .name = name,
                .value = null,
                .on = on,
            };
        }
        return null;
    }
};

/// Dedent a block of text - remove common leading whitespace
pub fn dedent(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var min_indent: ?usize = null;

    // Find minimum indent (ignoring empty lines)
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var indent: usize = 0;
        for (line) |c| {
            if (c == ' ' or c == '\t') {
                indent += 1;
            } else {
                break;
            }
        }
        if (indent < line.len) { // Line has content
            if (min_indent == null or indent < min_indent.?) {
                min_indent = indent;
            }
        }
    }

    const strip = min_indent orelse 0;
    if (strip == 0) return try allocator.dupe(u8, text);

    // Build dedented result
    var result = std.ArrayList(u8).init(allocator);
    lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;

    while (lines.next()) |line| {
        if (!first) try result.append('\n');
        first = false;

        if (line.len > strip) {
            try result.appendSlice(line[strip..]);
        } else if (line.len > 0) {
            // Line shorter than strip - keep what we have
            try result.appendSlice(std.mem.trimLeft(u8, line, " \t"));
        }
    }

    return try result.toOwnedSlice();
}

/// Count leading whitespace
pub fn getIndent(line: []const u8) usize {
    var count: usize = 0;
    for (line) |c| {
        if (c == ' ') {
            count += 1;
        } else if (c == '\t') {
            count += 4; // Treat tab as 4 spaces
        } else {
            break;
        }
    }
    return count;
}

/// Check if a line is a blank line (only whitespace)
pub fn isBlankLine(line: []const u8) bool {
    return std.mem.trim(u8, line, " \t\n\r").len == 0;
}

/// Extract docstring from source (simplified - looks for triple quotes)
pub fn extractDocstring(source: []const u8) ?[]const u8 {
    const triple_double = "\"\"\"";
    const triple_single = "'''";

    // Try triple double quotes first
    if (std.mem.indexOf(u8, source, triple_double)) |start| {
        const after_start = start + triple_double.len;
        if (std.mem.indexOf(u8, source[after_start..], triple_double)) |end| {
            return source[after_start .. after_start + end];
        }
    }

    // Try triple single quotes
    if (std.mem.indexOf(u8, source, triple_single)) |start| {
        const after_start = start + triple_single.len;
        if (std.mem.indexOf(u8, source[after_start..], triple_single)) |end| {
            return source[after_start .. after_start + end];
        }
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "ParsedExample_init" {
    var ex = ParsedExample.init(std.testing.allocator);
    defer ex.deinit();

    try std.testing.expectEqual(@as(usize, 0), ex.source_lines.items.len);
    try std.testing.expectEqual(@as(usize, 0), ex.output_lines.items.len);
}

test "ParsedExample_addLines" {
    var ex = ParsedExample.init(std.testing.allocator);
    defer ex.deinit();

    try ex.addSourceLine("x = 1");
    try ex.addSourceLine("print(x)");
    try ex.addOutputLine("1");

    try std.testing.expectEqual(@as(usize, 2), ex.source_lines.items.len);
    try std.testing.expectEqual(@as(usize, 1), ex.output_lines.items.len);
}

test "ParsedExample_getSource" {
    var ex = ParsedExample.init(std.testing.allocator);
    defer ex.deinit();

    try ex.addSourceLine("x = 1");
    try ex.addSourceLine("print(x)");

    const source = try ex.getSource(std.testing.allocator);
    defer std.testing.allocator.free(source);

    try std.testing.expectEqualStrings("x = 1\nprint(x)", source);
}

test "DocstringParser_simple_example" {
    const docstring =
        \\>>> 1 + 1
        \\2
    ;

    var parser = DocstringParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.parse(docstring);

    try std.testing.expectEqual(@as(usize, 1), parser.exampleCount());
}

test "DocstringParser_multiple_examples" {
    const docstring =
        \\>>> 1 + 1
        \\2
        \\>>> 2 * 3
        \\6
        \\>>> 'hello'.upper()
        \\'HELLO'
    ;

    var parser = DocstringParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.parse(docstring);

    try std.testing.expectEqual(@as(usize, 3), parser.exampleCount());
}

test "DocstringParser_multiline_source" {
    const docstring =
        \\>>> for i in range(3):
        \\...     print(i)
        \\0
        \\1
        \\2
    ;

    var parser = DocstringParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.parse(docstring);

    try std.testing.expectEqual(@as(usize, 1), parser.exampleCount());
    const ex = &parser.examples.items[0];
    try std.testing.expectEqual(@as(usize, 2), ex.source_lines.items.len);
}

test "DocstringParser_with_text" {
    const docstring =
        \\This is a module docstring.
        \\
        \\Example usage:
        \\
        \\>>> import math
        \\>>> math.sqrt(4)
        \\2.0
        \\
        \\More text here.
    ;

    var parser = DocstringParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.parse(docstring);

    try std.testing.expectEqual(@as(usize, 2), parser.exampleCount());
}

test "DirectiveParser_parse_plus" {
    const line = ">>> x = 1  # doctest: +ELLIPSIS";
    const directive = DirectiveParser.parseDirective(line);

    try std.testing.expect(directive != null);
    try std.testing.expect(directive.?.on);
    try std.testing.expectEqualStrings("ELLIPSIS", directive.?.name);
}

test "DirectiveParser_parse_minus" {
    const line = ">>> x = 1  # doctest: -SKIP";
    const directive = DirectiveParser.parseDirective(line);

    try std.testing.expect(directive != null);
    try std.testing.expect(!directive.?.on);
    try std.testing.expectEqualStrings("SKIP", directive.?.name);
}

test "DirectiveParser_no_directive" {
    const line = ">>> x = 1  # just a comment";
    const directive = DirectiveParser.parseDirective(line);

    try std.testing.expect(directive == null);
}

test "dedent_basic" {
    const text =
        \\    line1
        \\    line2
        \\    line3
    ;

    const result = try dedent(std.testing.allocator, text);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("line1\nline2\nline3", result);
}

test "dedent_mixed_indent" {
    const text =
        \\    line1
        \\        line2
        \\    line3
    ;

    const result = try dedent(std.testing.allocator, text);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("line1\n    line2\nline3", result);
}

test "getIndent_spaces" {
    try std.testing.expectEqual(@as(usize, 0), getIndent("hello"));
    try std.testing.expectEqual(@as(usize, 4), getIndent("    hello"));
    try std.testing.expectEqual(@as(usize, 8), getIndent("        hello"));
}

test "getIndent_tabs" {
    try std.testing.expectEqual(@as(usize, 4), getIndent("\thello"));
    try std.testing.expectEqual(@as(usize, 8), getIndent("\t\thello"));
}

test "isBlankLine_true" {
    try std.testing.expect(isBlankLine(""));
    try std.testing.expect(isBlankLine("   "));
    try std.testing.expect(isBlankLine("\t\t"));
    try std.testing.expect(isBlankLine("  \t  "));
}

test "isBlankLine_false" {
    try std.testing.expect(!isBlankLine("hello"));
    try std.testing.expect(!isBlankLine("  x"));
    try std.testing.expect(!isBlankLine("\t."));
}

test "extractDocstring_double_quotes" {
    const source =
        \\def foo():
        \\    """This is a docstring.
        \\
        \\    >>> 1 + 1
        \\    2
        \\    """
        \\    pass
    ;

    const docstring = extractDocstring(source);
    try std.testing.expect(docstring != null);
    try std.testing.expect(std.mem.indexOf(u8, docstring.?, ">>> 1 + 1") != null);
}

test "extractDocstring_single_quotes" {
    const source =
        \\def bar():
        \\    '''Single quote docstring.'''
        \\    pass
    ;

    const docstring = extractDocstring(source);
    try std.testing.expect(docstring != null);
    try std.testing.expectEqualStrings("Single quote docstring.", docstring.?);
}

test "extractDocstring_none" {
    const source =
        \\def baz():
        \\    # No docstring
        \\    pass
    ;

    const docstring = extractDocstring(source);
    try std.testing.expect(docstring == null);
}

test "DocstringParser_no_output" {
    const docstring =
        \\>>> x = 42
        \\>>> y = 10
    ;

    var parser = DocstringParser.init(std.testing.allocator);
    defer parser.deinit();

    try parser.parse(docstring);

    // Both are examples but second has no explicit output
    try std.testing.expect(parser.exampleCount() >= 1);
}

test "needsContinuation_colon" {
    try std.testing.expect(DocstringParser.needsContinuation("for i in range(10):"));
    try std.testing.expect(DocstringParser.needsContinuation("if x > 0:"));
    try std.testing.expect(DocstringParser.needsContinuation("def foo():"));
}

test "needsContinuation_brackets" {
    try std.testing.expect(DocstringParser.needsContinuation("x = ("));
    try std.testing.expect(DocstringParser.needsContinuation("x = ["));
    try std.testing.expect(DocstringParser.needsContinuation("x = {"));
}

test "needsContinuation_backslash" {
    try std.testing.expect(DocstringParser.needsContinuation("x = 1 + \\"));
}

test "needsContinuation_false" {
    try std.testing.expect(!DocstringParser.needsContinuation("x = 1"));
    try std.testing.expect(!DocstringParser.needsContinuation("print(x)"));
    try std.testing.expect(!DocstringParser.needsContinuation(""));
}
