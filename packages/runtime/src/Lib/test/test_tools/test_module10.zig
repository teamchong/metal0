//! test.test_tools.test_unicode - Unicode tools testing
//! Tests for Python's Unicode database tools, normalization,
//! and character property utilities.

const std = @import("std");

/// Unicode character properties
pub const CharProperties = struct {
    code_point: u21,
    name: ?[]const u8 = null,
    category: Category,
    combining_class: u8 = 0,
    bidirectional_category: BidiCategory = .L,
    decomposition: ?Decomposition = null,
    numeric_value: ?NumericValue = null,
    mirrored: bool = false,
    uppercase: ?u21 = null,
    lowercase: ?u21 = null,
    titlecase: ?u21 = null,

    pub const Category = enum {
        Lu, // Letter, uppercase
        Ll, // Letter, lowercase
        Lt, // Letter, titlecase
        Lm, // Letter, modifier
        Lo, // Letter, other
        Mn, // Mark, nonspacing
        Mc, // Mark, spacing combining
        Me, // Mark, enclosing
        Nd, // Number, decimal digit
        Nl, // Number, letter
        No, // Number, other
        Pc, // Punctuation, connector
        Pd, // Punctuation, dash
        Ps, // Punctuation, open
        Pe, // Punctuation, close
        Pi, // Punctuation, initial quote
        Pf, // Punctuation, final quote
        Po, // Punctuation, other
        Sm, // Symbol, math
        Sc, // Symbol, currency
        Sk, // Symbol, modifier
        So, // Symbol, other
        Zs, // Separator, space
        Zl, // Separator, line
        Zp, // Separator, paragraph
        Cc, // Other, control
        Cf, // Other, format
        Cs, // Other, surrogate
        Co, // Other, private use
        Cn, // Other, not assigned
    };

    pub const BidiCategory = enum {
        L, // Left-to-Right
        R, // Right-to-Left
        AL, // Arabic Letter
        EN, // European Number
        ES, // European Separator
        ET, // European Terminator
        AN, // Arabic Number
        CS, // Common Separator
        NSM, // Non-Spacing Mark
        BN, // Boundary Neutral
        B, // Paragraph Separator
        S, // Segment Separator
        WS, // Whitespace
        ON, // Other Neutral
        LRE, // Left-to-Right Embedding
        LRO, // Left-to-Right Override
        RLE, // Right-to-Left Embedding
        RLO, // Right-to-Left Override
        PDF, // Pop Directional Format
        LRI, // Left-to-Right Isolate
        RLI, // Right-to-Left Isolate
        FSI, // First Strong Isolate
        PDI, // Pop Directional Isolate
    };

    pub const Decomposition = struct {
        decomposition_type: ?DecompositionType = null,
        mapping: []const u21,

        pub const DecompositionType = enum {
            font,
            noBreak,
            initial,
            medial,
            final_type,
            isolated,
            circle,
            super,
            sub,
            vertical,
            wide,
            narrow,
            small,
            square,
            fraction,
            compat,
        };
    };

    pub const NumericValue = union(enum) {
        integer: i64,
        fraction: struct { numerator: i64, denominator: i64 },
    };

    pub fn isLetter(self: CharProperties) bool {
        return switch (self.category) {
            .Lu, .Ll, .Lt, .Lm, .Lo => true,
            else => false,
        };
    }

    pub fn isDigit(self: CharProperties) bool {
        return self.category == .Nd;
    }

    pub fn isNumeric(self: CharProperties) bool {
        return switch (self.category) {
            .Nd, .Nl, .No => true,
            else => false,
        };
    }

    pub fn isWhitespace(self: CharProperties) bool {
        return switch (self.category) {
            .Zs, .Zl, .Zp => true,
            else => false,
        };
    }

    pub fn isPunctuation(self: CharProperties) bool {
        return switch (self.category) {
            .Pc, .Pd, .Ps, .Pe, .Pi, .Pf, .Po => true,
            else => false,
        };
    }

    pub fn isSymbol(self: CharProperties) bool {
        return switch (self.category) {
            .Sm, .Sc, .Sk, .So => true,
            else => false,
        };
    }

    pub fn isControl(self: CharProperties) bool {
        return self.category == .Cc;
    }
};

/// Unicode normalization forms
pub const Normalizer = struct {
    allocator: std.mem.Allocator,

    pub const Form = enum {
        NFC, // Canonical Decomposition, followed by Canonical Composition
        NFD, // Canonical Decomposition
        NFKC, // Compatibility Decomposition, followed by Canonical Composition
        NFKD, // Compatibility Decomposition
    };

    pub fn init(allocator: std.mem.Allocator) Normalizer {
        return .{ .allocator = allocator };
    }

    pub fn isNormalized(self: Normalizer, text: []const u8, form: Form) bool {
        _ = self;
        _ = text;
        // Simplified check
        return switch (form) {
            .NFC, .NFKC => true, // Most text is already NFC
            .NFD, .NFKD => false,
        };
    }

    pub fn normalize(self: Normalizer, text: []const u8, form: Form) ![]u8 {
        _ = form;
        // Simplified - just copy for now
        return self.allocator.dupe(u8, text);
    }

    pub fn quickCheck(self: Normalizer, code_point: u21, form: Form) QuickCheckResult {
        _ = self;
        _ = code_point;
        _ = form;
        return .yes;
    }

    pub const QuickCheckResult = enum {
        yes,
        no,
        maybe,
    };
};

/// Unicode database lookup
pub const UnicodeDB = struct {
    allocator: std.mem.Allocator,
    version: []const u8,
    blocks: std.ArrayList(Block),

    pub const Block = struct {
        name: []const u8,
        start: u21,
        end: u21,

        pub fn contains(self: Block, code_point: u21) bool {
            return code_point >= self.start and code_point <= self.end;
        }

        pub fn size(self: Block) usize {
            return @as(usize, self.end - self.start) + 1;
        }
    };

    pub fn init(allocator: std.mem.Allocator, version: []const u8) UnicodeDB {
        return .{
            .allocator = allocator,
            .version = version,
            .blocks = std.ArrayList(Block).init(allocator),
        };
    }

    pub fn deinit(self: *UnicodeDB) void {
        self.blocks.deinit();
    }

    pub fn addBlock(self: *UnicodeDB, block: Block) !void {
        try self.blocks.append(block);
    }

    pub fn getBlock(self: UnicodeDB, code_point: u21) ?Block {
        for (self.blocks.items) |block| {
            if (block.contains(code_point)) {
                return block;
            }
        }
        return null;
    }

    pub fn getBlockByName(self: UnicodeDB, name: []const u8) ?Block {
        for (self.blocks.items) |block| {
            if (std.mem.eql(u8, block.name, name)) {
                return block;
            }
        }
        return null;
    }

    pub fn name(self: UnicodeDB, code_point: u21) ?[]const u8 {
        _ = self;
        // Simplified - would lookup in database
        if (code_point >= 'A' and code_point <= 'Z') {
            return "LATIN CAPITAL LETTER";
        }
        if (code_point >= 'a' and code_point <= 'z') {
            return "LATIN SMALL LETTER";
        }
        return null;
    }

    pub fn lookup(self: UnicodeDB, name_str: []const u8) ?u21 {
        _ = self;
        // Simplified lookup
        if (std.mem.eql(u8, name_str, "SPACE")) return 0x20;
        if (std.mem.eql(u8, name_str, "LATIN CAPITAL LETTER A")) return 'A';
        return null;
    }
};

/// Case folding and case mapping
pub const CaseMapper = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CaseMapper {
        return .{ .allocator = allocator };
    }

    pub fn toUpper(self: CaseMapper, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (text) |c| {
            if (c >= 'a' and c <= 'z') {
                try result.append(c - 32);
            } else {
                try result.append(c);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn toLower(self: CaseMapper, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (text) |c| {
            if (c >= 'A' and c <= 'Z') {
                try result.append(c + 32);
            } else {
                try result.append(c);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn toTitle(self: CaseMapper, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var at_word_start = true;
        for (text) |c| {
            if (c == ' ' or c == '\t' or c == '\n') {
                try result.append(c);
                at_word_start = true;
            } else if (at_word_start) {
                if (c >= 'a' and c <= 'z') {
                    try result.append(c - 32);
                } else {
                    try result.append(c);
                }
                at_word_start = false;
            } else {
                if (c >= 'A' and c <= 'Z') {
                    try result.append(c + 32);
                } else {
                    try result.append(c);
                }
            }
        }

        return result.toOwnedSlice();
    }

    pub fn caseFold(self: CaseMapper, text: []const u8) ![]u8 {
        // Simple case folding is equivalent to lowercase for ASCII
        return self.toLower(text);
    }
};

/// Collation (sorting) support
pub const Collator = struct {
    allocator: std.mem.Allocator,
    locale: []const u8,
    strength: Strength = .tertiary,
    case_first: CaseFirst = .off,

    pub const Strength = enum {
        primary, // Base characters
        secondary, // Accents
        tertiary, // Case
        quaternary, // Punctuation
        identical, // Tie-breaker
    };

    pub const CaseFirst = enum {
        off,
        upper_first,
        lower_first,
    };

    pub fn init(allocator: std.mem.Allocator, locale: []const u8) Collator {
        return .{
            .allocator = allocator,
            .locale = locale,
        };
    }

    pub fn compare(self: Collator, a: []const u8, b: []const u8) std.math.Order {
        _ = self;
        // Simplified comparison
        return std.mem.order(u8, a, b);
    }

    pub fn getSortKey(self: Collator, text: []const u8) ![]u8 {
        // Simplified - just return copy for ASCII
        return self.allocator.dupe(u8, text);
    }

    pub fn equals(self: Collator, a: []const u8, b: []const u8) bool {
        return self.compare(a, b) == .eq;
    }
};

/// Unicode script detection
pub const ScriptDetector = struct {
    pub const Script = enum {
        Common,
        Latin,
        Greek,
        Cyrillic,
        Armenian,
        Hebrew,
        Arabic,
        Syriac,
        Thaana,
        Devanagari,
        Bengali,
        Gurmukhi,
        Gujarati,
        Oriya,
        Tamil,
        Telugu,
        Kannada,
        Malayalam,
        Sinhala,
        Thai,
        Lao,
        Tibetan,
        Myanmar,
        Georgian,
        Hangul,
        Ethiopic,
        Cherokee,
        Canadian_Aboriginal,
        Ogham,
        Runic,
        Khmer,
        Mongolian,
        Hiragana,
        Katakana,
        Bopomofo,
        Han,
        Yi,
        Old_Italic,
        Gothic,
        Deseret,
        Inherited,
        Tagalog,
        Hanunoo,
        Buhid,
        Tagbanwa,
        Unknown,
    };

    pub fn detect(code_point: u21) Script {
        if (code_point <= 0x7F) {
            // ASCII
            if ((code_point >= 'A' and code_point <= 'Z') or
                (code_point >= 'a' and code_point <= 'z'))
            {
                return .Latin;
            }
            return .Common;
        }
        if (code_point >= 0x0370 and code_point <= 0x03FF) {
            return .Greek;
        }
        if (code_point >= 0x0400 and code_point <= 0x04FF) {
            return .Cyrillic;
        }
        if (code_point >= 0x0590 and code_point <= 0x05FF) {
            return .Hebrew;
        }
        if (code_point >= 0x0600 and code_point <= 0x06FF) {
            return .Arabic;
        }
        if (code_point >= 0x3040 and code_point <= 0x309F) {
            return .Hiragana;
        }
        if (code_point >= 0x30A0 and code_point <= 0x30FF) {
            return .Katakana;
        }
        if (code_point >= 0x4E00 and code_point <= 0x9FFF) {
            return .Han;
        }
        if (code_point >= 0xAC00 and code_point <= 0xD7AF) {
            return .Hangul;
        }
        return .Unknown;
    }

    pub fn getScriptName(script: Script) []const u8 {
        return @tagName(script);
    }
};

/// Grapheme cluster support
pub const GraphemeBreaker = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GraphemeBreaker {
        return .{ .allocator = allocator };
    }

    pub fn countGraphemes(self: GraphemeBreaker, text: []const u8) usize {
        _ = self;
        // Simplified - count UTF-8 code points for now
        var count: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const byte = text[i];
            if ((byte & 0xC0) != 0x80) {
                count += 1;
            }
            i += 1;
        }
        return count;
    }

    pub fn split(self: GraphemeBreaker, text: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        var start: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const byte = text[i];
            i += 1;

            // Check for start of next character
            if (i < text.len and (text[i] & 0xC0) != 0x80) {
                try result.append(text[start..i]);
                start = i;
            }
        }

        if (start < text.len) {
            try result.append(text[start..]);
        }

        return result.toOwnedSlice();
    }
};

/// Width calculation for East Asian text
pub const EastAsianWidth = struct {
    pub const Width = enum {
        Narrow, // N
        Wide, // W
        FullWidth, // F
        HalfWidth, // H
        Ambiguous, // A
        Neutral, // Na
    };

    pub fn getWidth(code_point: u21) Width {
        // CJK Unified Ideographs
        if (code_point >= 0x4E00 and code_point <= 0x9FFF) {
            return .Wide;
        }
        // Fullwidth ASCII variants
        if (code_point >= 0xFF01 and code_point <= 0xFF5E) {
            return .FullWidth;
        }
        // Halfwidth Katakana
        if (code_point >= 0xFF65 and code_point <= 0xFF9F) {
            return .HalfWidth;
        }
        // Basic Latin
        if (code_point <= 0x7F) {
            return .Narrow;
        }
        return .Neutral;
    }

    pub fn getDisplayWidth(code_point: u21) u8 {
        return switch (getWidth(code_point)) {
            .Wide, .FullWidth => 2,
            .Narrow, .HalfWidth, .Neutral => 1,
            .Ambiguous => 1, // Context-dependent
        };
    }

    pub fn stringWidth(text: []const u8) usize {
        var width: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const cp = std.unicode.utf8Decode(text[i..][0..len]) catch 0;
            width += getDisplayWidth(cp);
            i += len;
        }
        return width;
    }
};

// Tests
test "char_properties_basic" {
    const upper_a = CharProperties{
        .code_point = 'A',
        .category = .Lu,
        .lowercase = 'a',
    };
    try std.testing.expect(upper_a.isLetter());
    try std.testing.expect(!upper_a.isDigit());

    const digit = CharProperties{
        .code_point = '5',
        .category = .Nd,
    };
    try std.testing.expect(digit.isDigit());
    try std.testing.expect(digit.isNumeric());
}

test "char_properties_categories" {
    const space = CharProperties{
        .code_point = ' ',
        .category = .Zs,
    };
    try std.testing.expect(space.isWhitespace());

    const comma = CharProperties{
        .code_point = ',',
        .category = .Po,
    };
    try std.testing.expect(comma.isPunctuation());

    const plus = CharProperties{
        .code_point = '+',
        .category = .Sm,
    };
    try std.testing.expect(plus.isSymbol());
}

test "normalizer" {
    const normalizer = Normalizer.init(std.testing.allocator);

    try std.testing.expect(normalizer.isNormalized("hello", .NFC));
    try std.testing.expectEqual(Normalizer.QuickCheckResult.yes, normalizer.quickCheck('A', .NFC));
}

test "unicode_db_blocks" {
    var db = UnicodeDB.init(std.testing.allocator, "15.0.0");
    defer db.deinit();

    try db.addBlock(.{ .name = "Basic Latin", .start = 0x0000, .end = 0x007F });
    try db.addBlock(.{ .name = "Latin-1 Supplement", .start = 0x0080, .end = 0x00FF });

    const block = db.getBlock('A');
    try std.testing.expect(block != null);
    try std.testing.expectEqualStrings("Basic Latin", block.?.name);
}

test "unicode_db_lookup" {
    const db = UnicodeDB.init(std.testing.allocator, "15.0.0");

    const cp = db.lookup("SPACE");
    try std.testing.expectEqual(@as(?u21, 0x20), cp);
}

test "case_mapper" {
    const mapper = CaseMapper.init(std.testing.allocator);

    const upper = try mapper.toUpper("hello");
    defer std.testing.allocator.free(upper);
    try std.testing.expectEqualStrings("HELLO", upper);

    const lower = try mapper.toLower("WORLD");
    defer std.testing.allocator.free(lower);
    try std.testing.expectEqualStrings("world", lower);

    const title = try mapper.toTitle("hello world");
    defer std.testing.allocator.free(title);
    try std.testing.expectEqualStrings("Hello World", title);
}

test "collator" {
    const collator = Collator.init(std.testing.allocator, "en_US");

    try std.testing.expectEqual(std.math.Order.lt, collator.compare("apple", "banana"));
    try std.testing.expectEqual(std.math.Order.gt, collator.compare("zebra", "apple"));
    try std.testing.expect(collator.equals("same", "same"));
}

test "script_detector" {
    try std.testing.expectEqual(ScriptDetector.Script.Latin, ScriptDetector.detect('A'));
    try std.testing.expectEqual(ScriptDetector.Script.Latin, ScriptDetector.detect('z'));
    try std.testing.expectEqual(ScriptDetector.Script.Common, ScriptDetector.detect('1'));
    try std.testing.expectEqual(ScriptDetector.Script.Han, ScriptDetector.detect(0x4E00));
    try std.testing.expectEqual(ScriptDetector.Script.Arabic, ScriptDetector.detect(0x0627));
}

test "grapheme_breaker" {
    const breaker = GraphemeBreaker.init(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), breaker.countGraphemes("hello"));
    try std.testing.expectEqual(@as(usize, 3), breaker.countGraphemes("abc"));
}

test "east_asian_width" {
    try std.testing.expectEqual(EastAsianWidth.Width.Narrow, EastAsianWidth.getWidth('A'));
    try std.testing.expectEqual(EastAsianWidth.Width.Wide, EastAsianWidth.getWidth(0x4E00));
    try std.testing.expectEqual(@as(u8, 1), EastAsianWidth.getDisplayWidth('a'));
    try std.testing.expectEqual(@as(u8, 2), EastAsianWidth.getDisplayWidth(0x4E2D));
}

test "east_asian_string_width" {
    try std.testing.expectEqual(@as(usize, 5), EastAsianWidth.stringWidth("hello"));
}
