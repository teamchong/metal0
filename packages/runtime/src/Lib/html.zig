//! Python 'html' module - HTML processing utilities
//!
//! Provides functions for escaping and unescaping HTML entities.
//!
//! Mirrors: CPython Lib/html/__init__.py

const std = @import("std");

// ============================================================================
// HTML Entity Maps
// ============================================================================

/// HTML5 named character references (most common subset)
pub const html5_entities = std.StaticStringMap([]const u8).initComptime(.{
    .{ "amp", "&" },
    .{ "lt", "<" },
    .{ "gt", ">" },
    .{ "quot", "\"" },
    .{ "apos", "'" },
    .{ "nbsp", "\u{00A0}" },
    .{ "copy", "\u{00A9}" },
    .{ "reg", "\u{00AE}" },
    .{ "trade", "\u{2122}" },
    .{ "euro", "\u{20AC}" },
    .{ "pound", "\u{00A3}" },
    .{ "yen", "\u{00A5}" },
    .{ "cent", "\u{00A2}" },
    .{ "deg", "\u{00B0}" },
    .{ "plusmn", "\u{00B1}" },
    .{ "times", "\u{00D7}" },
    .{ "divide", "\u{00F7}" },
    .{ "para", "\u{00B6}" },
    .{ "sect", "\u{00A7}" },
    .{ "middot", "\u{00B7}" },
    .{ "bull", "\u{2022}" },
    .{ "hellip", "\u{2026}" },
    .{ "prime", "\u{2032}" },
    .{ "Prime", "\u{2033}" },
    .{ "lsquo", "\u{2018}" },
    .{ "rsquo", "\u{2019}" },
    .{ "ldquo", "\u{201C}" },
    .{ "rdquo", "\u{201D}" },
    .{ "laquo", "\u{00AB}" },
    .{ "raquo", "\u{00BB}" },
    .{ "ndash", "\u{2013}" },
    .{ "mdash", "\u{2014}" },
    .{ "iexcl", "\u{00A1}" },
    .{ "iquest", "\u{00BF}" },
    .{ "Agrave", "\u{00C0}" },
    .{ "Aacute", "\u{00C1}" },
    .{ "Acirc", "\u{00C2}" },
    .{ "Atilde", "\u{00C3}" },
    .{ "Auml", "\u{00C4}" },
    .{ "Aring", "\u{00C5}" },
    .{ "AElig", "\u{00C6}" },
    .{ "Ccedil", "\u{00C7}" },
    .{ "Egrave", "\u{00C8}" },
    .{ "Eacute", "\u{00C9}" },
    .{ "Ecirc", "\u{00CA}" },
    .{ "Euml", "\u{00CB}" },
    .{ "Igrave", "\u{00CC}" },
    .{ "Iacute", "\u{00CD}" },
    .{ "Icirc", "\u{00CE}" },
    .{ "Iuml", "\u{00CF}" },
    .{ "Ntilde", "\u{00D1}" },
    .{ "Ograve", "\u{00D2}" },
    .{ "Oacute", "\u{00D3}" },
    .{ "Ocirc", "\u{00D4}" },
    .{ "Otilde", "\u{00D5}" },
    .{ "Ouml", "\u{00D6}" },
    .{ "Oslash", "\u{00D8}" },
    .{ "Ugrave", "\u{00D9}" },
    .{ "Uacute", "\u{00DA}" },
    .{ "Ucirc", "\u{00DB}" },
    .{ "Uuml", "\u{00DC}" },
    .{ "Yacute", "\u{00DD}" },
    .{ "szlig", "\u{00DF}" },
    .{ "agrave", "\u{00E0}" },
    .{ "aacute", "\u{00E1}" },
    .{ "acirc", "\u{00E2}" },
    .{ "atilde", "\u{00E3}" },
    .{ "auml", "\u{00E4}" },
    .{ "aring", "\u{00E5}" },
    .{ "aelig", "\u{00E6}" },
    .{ "ccedil", "\u{00E7}" },
    .{ "egrave", "\u{00E8}" },
    .{ "eacute", "\u{00E9}" },
    .{ "ecirc", "\u{00EA}" },
    .{ "euml", "\u{00EB}" },
    .{ "igrave", "\u{00EC}" },
    .{ "iacute", "\u{00ED}" },
    .{ "icirc", "\u{00EE}" },
    .{ "iuml", "\u{00EF}" },
    .{ "ntilde", "\u{00F1}" },
    .{ "ograve", "\u{00F2}" },
    .{ "oacute", "\u{00F3}" },
    .{ "ocirc", "\u{00F4}" },
    .{ "otilde", "\u{00F5}" },
    .{ "ouml", "\u{00F6}" },
    .{ "oslash", "\u{00F8}" },
    .{ "ugrave", "\u{00F9}" },
    .{ "uacute", "\u{00FA}" },
    .{ "ucirc", "\u{00FB}" },
    .{ "uuml", "\u{00FC}" },
    .{ "yacute", "\u{00FD}" },
    .{ "yuml", "\u{00FF}" },
    // Greek letters
    .{ "Alpha", "\u{0391}" },
    .{ "Beta", "\u{0392}" },
    .{ "Gamma", "\u{0393}" },
    .{ "Delta", "\u{0394}" },
    .{ "Epsilon", "\u{0395}" },
    .{ "Zeta", "\u{0396}" },
    .{ "Eta", "\u{0397}" },
    .{ "Theta", "\u{0398}" },
    .{ "Iota", "\u{0399}" },
    .{ "Kappa", "\u{039A}" },
    .{ "Lambda", "\u{039B}" },
    .{ "Mu", "\u{039C}" },
    .{ "Nu", "\u{039D}" },
    .{ "Xi", "\u{039E}" },
    .{ "Omicron", "\u{039F}" },
    .{ "Pi", "\u{03A0}" },
    .{ "Rho", "\u{03A1}" },
    .{ "Sigma", "\u{03A3}" },
    .{ "Tau", "\u{03A4}" },
    .{ "Upsilon", "\u{03A5}" },
    .{ "Phi", "\u{03A6}" },
    .{ "Chi", "\u{03A7}" },
    .{ "Psi", "\u{03A8}" },
    .{ "Omega", "\u{03A9}" },
    .{ "alpha", "\u{03B1}" },
    .{ "beta", "\u{03B2}" },
    .{ "gamma", "\u{03B3}" },
    .{ "delta", "\u{03B4}" },
    .{ "epsilon", "\u{03B5}" },
    .{ "zeta", "\u{03B6}" },
    .{ "eta", "\u{03B7}" },
    .{ "theta", "\u{03B8}" },
    .{ "iota", "\u{03B9}" },
    .{ "kappa", "\u{03BA}" },
    .{ "lambda", "\u{03BB}" },
    .{ "mu", "\u{03BC}" },
    .{ "nu", "\u{03BD}" },
    .{ "xi", "\u{03BE}" },
    .{ "omicron", "\u{03BF}" },
    .{ "pi", "\u{03C0}" },
    .{ "rho", "\u{03C1}" },
    .{ "sigmaf", "\u{03C2}" },
    .{ "sigma", "\u{03C3}" },
    .{ "tau", "\u{03C4}" },
    .{ "upsilon", "\u{03C5}" },
    .{ "phi", "\u{03C6}" },
    .{ "chi", "\u{03C7}" },
    .{ "psi", "\u{03C8}" },
    .{ "omega", "\u{03C9}" },
    // Math symbols
    .{ "forall", "\u{2200}" },
    .{ "part", "\u{2202}" },
    .{ "exist", "\u{2203}" },
    .{ "empty", "\u{2205}" },
    .{ "nabla", "\u{2207}" },
    .{ "isin", "\u{2208}" },
    .{ "notin", "\u{2209}" },
    .{ "ni", "\u{220B}" },
    .{ "prod", "\u{220F}" },
    .{ "sum", "\u{2211}" },
    .{ "minus", "\u{2212}" },
    .{ "lowast", "\u{2217}" },
    .{ "radic", "\u{221A}" },
    .{ "prop", "\u{221D}" },
    .{ "infin", "\u{221E}" },
    .{ "ang", "\u{2220}" },
    .{ "and", "\u{2227}" },
    .{ "or", "\u{2228}" },
    .{ "cap", "\u{2229}" },
    .{ "cup", "\u{222A}" },
    .{ "int", "\u{222B}" },
    .{ "there4", "\u{2234}" },
    .{ "sim", "\u{223C}" },
    .{ "cong", "\u{2245}" },
    .{ "asymp", "\u{2248}" },
    .{ "ne", "\u{2260}" },
    .{ "equiv", "\u{2261}" },
    .{ "le", "\u{2264}" },
    .{ "ge", "\u{2265}" },
    .{ "sub", "\u{2282}" },
    .{ "sup", "\u{2283}" },
    .{ "nsub", "\u{2284}" },
    .{ "sube", "\u{2286}" },
    .{ "supe", "\u{2287}" },
    .{ "oplus", "\u{2295}" },
    .{ "otimes", "\u{2297}" },
    .{ "perp", "\u{22A5}" },
    .{ "sdot", "\u{22C5}" },
    // Arrows
    .{ "larr", "\u{2190}" },
    .{ "uarr", "\u{2191}" },
    .{ "rarr", "\u{2192}" },
    .{ "darr", "\u{2193}" },
    .{ "harr", "\u{2194}" },
    .{ "lArr", "\u{21D0}" },
    .{ "uArr", "\u{21D1}" },
    .{ "rArr", "\u{21D2}" },
    .{ "dArr", "\u{21D3}" },
    .{ "hArr", "\u{21D4}" },
    // Misc
    .{ "spades", "\u{2660}" },
    .{ "clubs", "\u{2663}" },
    .{ "hearts", "\u{2665}" },
    .{ "diams", "\u{2666}" },
});

// ============================================================================
// Main Functions
// ============================================================================

/// Escape special HTML characters: &, <, >, " and optionally '
pub fn escape(allocator: std.mem.Allocator, s: []const u8, quote: bool) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (s) |c| {
        switch (c) {
            '&' => try result.appendSlice("&amp;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => {
                if (quote) {
                    try result.appendSlice("&#x27;");
                } else {
                    try result.append(c);
                }
            },
            else => try result.append(c),
        }
    }

    return result.toOwnedSlice();
}

/// Unescape HTML entities to their character equivalents
pub fn unescape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            // Find the end of the entity
            if (std.mem.indexOfScalarPos(u8, s, i + 1, ';')) |end| {
                const entity = s[i + 1 .. end];

                // Check for numeric entity
                if (entity.len > 0 and entity[0] == '#') {
                    const codepoint = parseNumericEntity(entity[1..]);
                    if (codepoint) |cp| {
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch {
                            // Invalid codepoint, output as-is
                            try result.appendSlice(s[i .. end + 1]);
                            i = end + 1;
                            continue;
                        };
                        try result.appendSlice(buf[0..len]);
                        i = end + 1;
                        continue;
                    }
                }

                // Check for named entity
                if (html5_entities.get(entity)) |replacement| {
                    try result.appendSlice(replacement);
                    i = end + 1;
                    continue;
                }
            }
        }

        try result.append(s[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

fn parseNumericEntity(entity: []const u8) ?u21 {
    if (entity.len == 0) return null;

    if (entity[0] == 'x' or entity[0] == 'X') {
        // Hex entity
        if (entity.len < 2) return null;
        return std.fmt.parseInt(u21, entity[1..], 16) catch null;
    } else {
        // Decimal entity
        return std.fmt.parseInt(u21, entity, 10) catch null;
    }
}

// ============================================================================
// HTMLParser - Basic HTML/XHTML parser
// ============================================================================

/// Event-driven HTML parser
pub const HTMLParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    strict: bool,
    convert_charrefs: bool,

    // Handler callbacks (set by subclass/user)
    handle_starttag: ?*const fn (tag: []const u8, attrs: []const Attribute) void = null,
    handle_endtag: ?*const fn (tag: []const u8) void = null,
    handle_data: ?*const fn (data: []const u8) void = null,
    handle_comment: ?*const fn (data: []const u8) void = null,
    handle_decl: ?*const fn (decl: []const u8) void = null,
    handle_pi: ?*const fn (data: []const u8) void = null,

    pub const Attribute = struct {
        name: []const u8,
        value: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator, convert_charrefs: bool) Self {
        return .{
            .allocator = allocator,
            .strict = false,
            .convert_charrefs = convert_charrefs,
        };
    }

    /// Feed data to the parser
    pub fn feed(self: *Self, data: []const u8) !void {
        var i: usize = 0;

        while (i < data.len) {
            if (data[i] == '<') {
                // Start of tag
                if (i + 1 < data.len) {
                    if (data[i + 1] == '/') {
                        // End tag
                        const tag_end = std.mem.indexOfScalarPos(u8, data, i + 2, '>') orelse break;
                        const tag_name = std.mem.trim(u8, data[i + 2 .. tag_end], " \t\n\r");
                        if (self.handle_endtag) |handler| {
                            handler(tag_name);
                        }
                        i = tag_end + 1;
                        continue;
                    } else if (data[i + 1] == '!') {
                        // Comment or declaration
                        if (i + 4 < data.len and std.mem.eql(u8, data[i + 2 .. i + 4], "--")) {
                            // Comment
                            if (std.mem.indexOf(u8, data[i + 4 ..], "-->")) |comment_end| {
                                const comment = data[i + 4 .. i + 4 + comment_end];
                                if (self.handle_comment) |handler| {
                                    handler(comment);
                                }
                                i = i + 4 + comment_end + 3;
                                continue;
                            }
                        } else {
                            // Declaration
                            const decl_end = std.mem.indexOfScalarPos(u8, data, i + 2, '>') orelse break;
                            const decl = data[i + 2 .. decl_end];
                            if (self.handle_decl) |handler| {
                                handler(decl);
                            }
                            i = decl_end + 1;
                            continue;
                        }
                    } else if (data[i + 1] == '?') {
                        // Processing instruction
                        if (std.mem.indexOf(u8, data[i + 2 ..], "?>")) |pi_end| {
                            const pi = data[i + 2 .. i + 2 + pi_end];
                            if (self.handle_pi) |handler| {
                                handler(pi);
                            }
                            i = i + 2 + pi_end + 2;
                            continue;
                        }
                    } else {
                        // Start tag
                        const tag_end = std.mem.indexOfScalarPos(u8, data, i + 1, '>') orelse break;
                        const tag_content = data[i + 1 .. tag_end];

                        // Parse tag name and attributes
                        var parts = std.mem.tokenizeAny(u8, tag_content, " \t\n\r");
                        const tag_name = parts.next() orelse {
                            i = tag_end + 1;
                            continue;
                        };

                        // Check for self-closing
                        const is_self_closing = tag_content.len > 0 and tag_content[tag_content.len - 1] == '/';
                        const clean_tag = if (is_self_closing and tag_name.len > 0 and tag_name[tag_name.len - 1] == '/')
                            tag_name[0 .. tag_name.len - 1]
                        else
                            tag_name;

                        // TODO: Parse attributes properly
                        var attrs = [_]Attribute{};

                        if (self.handle_starttag) |handler| {
                            handler(clean_tag, &attrs);
                        }

                        if (is_self_closing) {
                            if (self.handle_endtag) |handler| {
                                handler(clean_tag);
                            }
                        }

                        i = tag_end + 1;
                        continue;
                    }
                }
            }

            // Regular text content
            const next_tag = std.mem.indexOfScalarPos(u8, data, i, '<') orelse data.len;
            if (next_tag > i) {
                var text = data[i..next_tag];
                if (self.convert_charrefs) {
                    // Would unescape entities here
                }
                if (self.handle_data) |handler| {
                    handler(text);
                }
            }
            i = next_tag;
        }
    }

    /// Reset the parser
    pub fn reset(self: *Self) void {
        _ = self;
        // Reset internal state
    }

    /// Close the parser and process any remaining data
    pub fn close(self: *Self) void {
        _ = self;
        // Process any remaining buffered data
    }

    /// Get current line number
    pub fn getPos(self: *Self) struct { lineno: usize, offset: usize } {
        _ = self;
        return .{ .lineno = 1, .offset = 0 };
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if a character is an HTML space character
pub fn isHtmlSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0c';
}

/// Normalize whitespace in HTML text
pub fn normalizeWhitespace(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_whitespace = false;
    for (s) |c| {
        if (isHtmlSpace(c)) {
            if (!in_whitespace) {
                try result.append(' ');
                in_whitespace = true;
            }
        } else {
            try result.append(c);
            in_whitespace = false;
        }
    }

    return result.toOwnedSlice();
}

/// Strip HTML tags from text
pub fn stripTags(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_tag = false;
    for (html) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            try result.append(c);
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "escape basic" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "Hello <World> & \"Friends\"", true);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello &lt;World&gt; &amp; &quot;Friends&quot;", result);
}

test "escape with quotes" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "It's a 'test'", true);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("It&#x27;s a &#x27;test&#x27;", result);
}

test "escape without quotes" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "It's a 'test'", false);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("It's a 'test'", result);
}

test "unescape basic entities" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&lt;div&gt;&amp;&quot;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("<div>&\"", result);
}

test "unescape numeric decimal" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&#65;&#66;&#67;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("ABC", result);
}

test "unescape numeric hex" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&#x41;&#x42;&#x43;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("ABC", result);
}

test "unescape named entities" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&copy; &reg; &trade;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("\u{00A9} \u{00AE} \u{2122}", result);
}

test "strip tags" {
    const allocator = std.testing.allocator;

    const result = try stripTags(allocator, "<p>Hello <b>World</b>!</p>");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "normalize whitespace" {
    const allocator = std.testing.allocator;

    const result = try normalizeWhitespace(allocator, "Hello   \n\t  World");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}
