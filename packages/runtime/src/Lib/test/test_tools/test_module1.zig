//! test.test_tools.test_i18n - Internationalization tools testing
//! Tests for Python's i18n/l10n utilities including message catalogs,
//! locale handling, and translation infrastructure.

const std = @import("std");

/// Represents a locale identifier with language and optional country/variant
pub const Locale = struct {
    language: []const u8,
    country: ?[]const u8 = null,
    variant: ?[]const u8 = null,
    encoding: ?[]const u8 = null,

    pub fn format(self: Locale, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice(self.language);
        if (self.country) |c| {
            try result.append('_');
            try result.appendSlice(c);
        }
        if (self.variant) |v| {
            try result.append('@');
            try result.appendSlice(v);
        }
        if (self.encoding) |e| {
            try result.append('.');
            try result.appendSlice(e);
        }
        return result.toOwnedSlice();
    }

    pub fn parse(locale_str: []const u8) Locale {
        var result = Locale{ .language = locale_str };

        // Parse language_COUNTRY@variant.encoding format
        var remaining = locale_str;

        // Check for encoding
        if (std.mem.lastIndexOf(u8, remaining, ".")) |dot_idx| {
            result.encoding = remaining[dot_idx + 1 ..];
            remaining = remaining[0..dot_idx];
        }

        // Check for variant
        if (std.mem.indexOf(u8, remaining, "@")) |at_idx| {
            result.variant = remaining[at_idx + 1 ..];
            remaining = remaining[0..at_idx];
        }

        // Check for country
        if (std.mem.indexOf(u8, remaining, "_")) |underscore_idx| {
            result.language = remaining[0..underscore_idx];
            result.country = remaining[underscore_idx + 1 ..];
        } else {
            result.language = remaining;
        }

        return result;
    }

    pub fn isCompatible(self: Locale, other: Locale) bool {
        if (!std.mem.eql(u8, self.language, other.language)) {
            return false;
        }
        if (self.country != null and other.country != null) {
            if (!std.mem.eql(u8, self.country.?, other.country.?)) {
                return false;
            }
        }
        return true;
    }
};

/// Message catalog for storing translations
pub const MessageCatalog = struct {
    allocator: std.mem.Allocator,
    messages: std.StringHashMap([]const u8),
    plural_forms: ?PluralForms = null,
    metadata: CatalogMetadata,

    pub const CatalogMetadata = struct {
        domain: []const u8 = "messages",
        locale: Locale = .{ .language = "en" },
        charset: []const u8 = "UTF-8",
        plural_forms_expr: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, metadata: CatalogMetadata) MessageCatalog {
        return .{
            .allocator = allocator,
            .messages = std.StringHashMap([]const u8).init(allocator),
            .metadata = metadata,
        };
    }

    pub fn deinit(self: *MessageCatalog) void {
        self.messages.deinit();
    }

    pub fn addMessage(self: *MessageCatalog, msgid: []const u8, msgstr: []const u8) !void {
        try self.messages.put(msgid, msgstr);
    }

    pub fn getMessage(self: MessageCatalog, msgid: []const u8) ?[]const u8 {
        return self.messages.get(msgid);
    }

    pub fn translate(self: MessageCatalog, msgid: []const u8) []const u8 {
        return self.getMessage(msgid) orelse msgid;
    }

    pub fn count(self: MessageCatalog) usize {
        return self.messages.count();
    }
};

/// Plural forms handler for languages with complex pluralization rules
pub const PluralForms = struct {
    num_plurals: u8,
    // Simplified plural form evaluation
    plural_type: PluralType,

    pub const PluralType = enum {
        // n == 1 ? 0 : 1 (English, German, etc.)
        germanic,
        // n == 0 || n == 1 ? 0 : 1 (French, Brazilian Portuguese)
        french,
        // Always 0 (Asian languages)
        none,
        // n == 1 ? 0 : n == 2 ? 1 : 2 (Welsh, etc.)
        welsh,
        // Complex Slavic rules
        slavic,
    };

    pub fn evaluate(self: PluralForms, n: usize) u8 {
        return switch (self.plural_type) {
            .germanic => if (n == 1) 0 else 1,
            .french => if (n == 0 or n == 1) 0 else 1,
            .none => 0,
            .welsh => if (n == 1) 0 else if (n == 2) 1 else 2,
            .slavic => blk: {
                const mod10 = n % 10;
                const mod100 = n % 100;
                if (mod10 == 1 and mod100 != 11) {
                    break :blk 0;
                } else if (mod10 >= 2 and mod10 <= 4 and (mod100 < 10 or mod100 >= 20)) {
                    break :blk 1;
                } else {
                    break :blk 2;
                }
            },
        };
    }
};

/// Translation context for managing multiple domains and locales
pub const TranslationContext = struct {
    allocator: std.mem.Allocator,
    catalogs: std.StringHashMap(MessageCatalog),
    current_domain: []const u8,
    fallback_locale: Locale,

    pub fn init(allocator: std.mem.Allocator) TranslationContext {
        return .{
            .allocator = allocator,
            .catalogs = std.StringHashMap(MessageCatalog).init(allocator),
            .current_domain = "messages",
            .fallback_locale = .{ .language = "en" },
        };
    }

    pub fn deinit(self: *TranslationContext) void {
        var iter = self.catalogs.valueIterator();
        while (iter.next()) |catalog| {
            var cat = catalog;
            cat.deinit();
        }
        self.catalogs.deinit();
    }

    pub fn addCatalog(self: *TranslationContext, domain: []const u8, catalog: MessageCatalog) !void {
        try self.catalogs.put(domain, catalog);
    }

    pub fn setDomain(self: *TranslationContext, domain: []const u8) void {
        self.current_domain = domain;
    }

    pub fn gettext(self: TranslationContext, msgid: []const u8) []const u8 {
        if (self.catalogs.get(self.current_domain)) |catalog| {
            return catalog.translate(msgid);
        }
        return msgid;
    }

    pub fn dgettext(self: TranslationContext, domain: []const u8, msgid: []const u8) []const u8 {
        if (self.catalogs.get(domain)) |catalog| {
            return catalog.translate(msgid);
        }
        return msgid;
    }
};

/// PO file format parser (simplified)
pub const POParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) POParser {
        return .{ .allocator = allocator };
    }

    pub fn parseEntry(self: POParser, content: []const u8) !POEntry {
        _ = self;
        var entry = POEntry{};

        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, "msgid ")) {
                entry.msgid = extractQuotedString(trimmed[6..]);
            } else if (std.mem.startsWith(u8, trimmed, "msgstr ")) {
                entry.msgstr = extractQuotedString(trimmed[7..]);
            } else if (std.mem.startsWith(u8, trimmed, "#: ")) {
                entry.reference = trimmed[3..];
            } else if (std.mem.startsWith(u8, trimmed, "#. ")) {
                entry.extracted_comment = trimmed[3..];
            }
        }

        return entry;
    }

    fn extractQuotedString(s: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, s, " \t");
        if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
            return trimmed[1 .. trimmed.len - 1];
        }
        return trimmed;
    }
};

pub const POEntry = struct {
    msgid: []const u8 = "",
    msgstr: []const u8 = "",
    msgctxt: ?[]const u8 = null,
    reference: ?[]const u8 = null,
    extracted_comment: ?[]const u8 = null,
    translator_comment: ?[]const u8 = null,
    flags: Flags = .{},

    pub const Flags = struct {
        fuzzy: bool = false,
        python_format: bool = false,
        python_brace_format: bool = false,
    };

    pub fn isTranslated(self: POEntry) bool {
        return self.msgstr.len > 0 and !self.flags.fuzzy;
    }

    pub fn isEmpty(self: POEntry) bool {
        return self.msgid.len == 0;
    }
};

/// MO file format handler (binary message catalog)
pub const MOFile = struct {
    magic: u32 = 0x950412de,
    revision: u32 = 0,
    num_strings: u32 = 0,

    pub const MAGIC_LE: u32 = 0x950412de;
    pub const MAGIC_BE: u32 = 0xde120495;

    pub fn isValid(magic: u32) bool {
        return magic == MAGIC_LE or magic == MAGIC_BE;
    }

    pub fn needsByteSwap(magic: u32) bool {
        return magic == MAGIC_BE;
    }
};

/// Locale category constants (matching Python's locale module)
pub const LocaleCategory = enum(u8) {
    LC_CTYPE = 0,
    LC_NUMERIC = 1,
    LC_TIME = 2,
    LC_COLLATE = 3,
    LC_MONETARY = 4,
    LC_MESSAGES = 5,
    LC_ALL = 6,
};

/// Number formatting according to locale
pub const NumberFormatter = struct {
    decimal_point: []const u8 = ".",
    thousands_sep: []const u8 = ",",
    grouping: []const u8 = "\x03",

    pub fn formatInt(self: NumberFormatter, allocator: std.mem.Allocator, value: i64) ![]u8 {
        var buf: [32]u8 = undefined;
        const abs_value = if (value < 0) @as(u64, @intCast(-value)) else @as(u64, @intCast(value));
        const digits = std.fmt.formatInt(&buf, abs_value, 10, .lower, .{});

        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        if (value < 0) {
            try result.append('-');
        }

        var pos: usize = 0;
        const group_size = if (self.grouping.len > 0) self.grouping[0] else 3;
        const first_group = digits.len % group_size;
        if (first_group == 0 and digits.len > 0) {
            // First group is full size
            try result.appendSlice(digits[0..group_size]);
            pos = group_size;
        } else {
            try result.appendSlice(digits[0..first_group]);
            pos = first_group;
        }

        while (pos < digits.len) {
            try result.appendSlice(self.thousands_sep);
            try result.appendSlice(digits[pos .. pos + group_size]);
            pos += group_size;
        }

        return result.toOwnedSlice();
    }
};

// Tests
test "locale_parse" {
    const locale = Locale.parse("en_US.UTF-8");
    try std.testing.expectEqualStrings("en", locale.language);
    try std.testing.expectEqualStrings("US", locale.country.?);
    try std.testing.expectEqualStrings("UTF-8", locale.encoding.?);
}

test "locale_parse_simple" {
    const locale = Locale.parse("de");
    try std.testing.expectEqualStrings("de", locale.language);
    try std.testing.expect(locale.country == null);
}

test "locale_parse_with_variant" {
    const locale = Locale.parse("sr_RS@latin");
    try std.testing.expectEqualStrings("sr", locale.language);
    try std.testing.expectEqualStrings("RS", locale.country.?);
    try std.testing.expectEqualStrings("latin", locale.variant.?);
}

test "locale_format" {
    const locale = Locale{
        .language = "en",
        .country = "US",
        .encoding = "UTF-8",
    };
    const formatted = try locale.format(std.testing.allocator);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("en_US.UTF-8", formatted);
}

test "locale_compatibility" {
    const en_us = Locale{ .language = "en", .country = "US" };
    const en_gb = Locale{ .language = "en", .country = "GB" };
    const de_de = Locale{ .language = "de", .country = "DE" };

    try std.testing.expect(!en_us.isCompatible(en_gb));
    try std.testing.expect(!en_us.isCompatible(de_de));
}

test "message_catalog" {
    var catalog = MessageCatalog.init(std.testing.allocator, .{
        .domain = "test",
        .locale = .{ .language = "de" },
    });
    defer catalog.deinit();

    try catalog.addMessage("Hello", "Hallo");
    try catalog.addMessage("World", "Welt");

    try std.testing.expectEqualStrings("Hallo", catalog.translate("Hello"));
    try std.testing.expectEqualStrings("Welt", catalog.translate("World"));
    try std.testing.expectEqualStrings("Unknown", catalog.translate("Unknown"));
    try std.testing.expectEqual(@as(usize, 2), catalog.count());
}

test "plural_forms_germanic" {
    const forms = PluralForms{ .num_plurals = 2, .plural_type = .germanic };
    try std.testing.expectEqual(@as(u8, 0), forms.evaluate(1));
    try std.testing.expectEqual(@as(u8, 1), forms.evaluate(0));
    try std.testing.expectEqual(@as(u8, 1), forms.evaluate(2));
    try std.testing.expectEqual(@as(u8, 1), forms.evaluate(100));
}

test "plural_forms_slavic" {
    const forms = PluralForms{ .num_plurals = 3, .plural_type = .slavic };
    try std.testing.expectEqual(@as(u8, 0), forms.evaluate(1));
    try std.testing.expectEqual(@as(u8, 0), forms.evaluate(21));
    try std.testing.expectEqual(@as(u8, 1), forms.evaluate(2));
    try std.testing.expectEqual(@as(u8, 1), forms.evaluate(3));
    try std.testing.expectEqual(@as(u8, 2), forms.evaluate(5));
    try std.testing.expectEqual(@as(u8, 2), forms.evaluate(11));
}

test "po_entry" {
    const entry = POEntry{
        .msgid = "Hello",
        .msgstr = "Hallo",
    };
    try std.testing.expect(entry.isTranslated());
    try std.testing.expect(!entry.isEmpty());
}

test "po_entry_fuzzy" {
    const entry = POEntry{
        .msgid = "Hello",
        .msgstr = "Hallo",
        .flags = .{ .fuzzy = true },
    };
    try std.testing.expect(!entry.isTranslated());
}

test "mo_file_magic" {
    try std.testing.expect(MOFile.isValid(0x950412de));
    try std.testing.expect(MOFile.isValid(0xde120495));
    try std.testing.expect(!MOFile.isValid(0x12345678));
    try std.testing.expect(!MOFile.needsByteSwap(0x950412de));
    try std.testing.expect(MOFile.needsByteSwap(0xde120495));
}

test "translation_context" {
    var ctx = TranslationContext.init(std.testing.allocator);
    defer ctx.deinit();

    var catalog = MessageCatalog.init(std.testing.allocator, .{
        .domain = "app",
        .locale = .{ .language = "fr" },
    });
    try catalog.addMessage("Yes", "Oui");
    try catalog.addMessage("No", "Non");

    try ctx.addCatalog("app", catalog);
    ctx.setDomain("app");

    try std.testing.expectEqualStrings("Oui", ctx.gettext("Yes"));
    try std.testing.expectEqualStrings("Non", ctx.gettext("No"));
    try std.testing.expectEqualStrings("Maybe", ctx.gettext("Maybe"));
}

test "po_parser" {
    const parser = POParser.init(std.testing.allocator);
    const content =
        \\#: src/main.py:42
        \\msgid "Hello"
        \\msgstr "Bonjour"
    ;
    const entry = try parser.parseEntry(content);
    try std.testing.expectEqualStrings("Hello", entry.msgid);
    try std.testing.expectEqualStrings("Bonjour", entry.msgstr);
    try std.testing.expectEqualStrings("src/main.py:42", entry.reference.?);
}
