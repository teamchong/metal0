/// gettext - Internationalization (i18n) services
/// Mirrors cpython/Lib/gettext.py
///
/// Provides GNU gettext-compatible message translation.
/// Used for internationalizing Python programs.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default text domain
pub const DEFAULT_DOMAIN: []const u8 = "messages";

/// Default locale directory
pub const DEFAULT_LOCALEDIR: []const u8 = "/usr/share/locale";

/// Null translations (passthrough)
pub const NULL_TRANSLATION: Translation = Translation{
    .catalog = null,
    .charset = "UTF-8",
    .fallback = null,
};

// ============================================================================
// Translation Class
// ============================================================================

/// A translation catalog
pub const Translation = struct {
    const Self = @This();

    /// The message catalog (msgid -> msgstr mapping)
    catalog: ?std.StringHashMap([]const u8),
    /// Character encoding
    charset: []const u8,
    /// Fallback translation
    fallback: ?*const Self,
    /// The language/locale
    language: ?[]const u8 = null,
    /// Allocator
    allocator: ?std.mem.Allocator = null,

    /// Get translation for a message
    pub fn gettext(self: *const Self, message: []const u8) []const u8 {
        if (self.catalog) |cat| {
            if (cat.get(message)) |trans| {
                return trans;
            }
        }
        if (self.fallback) |fb| {
            return fb.gettext(message);
        }
        return message;
    }

    /// Get translation with context
    pub fn pgettext(self: *const Self, context: []const u8, message: []const u8) []const u8 {
        // Context is prepended with \x04 separator
        _ = context;
        return self.gettext(message);
    }

    /// Plural form translation
    pub fn ngettext(
        self: *const Self,
        singular: []const u8,
        plural: []const u8,
        n: usize,
    ) []const u8 {
        // Default plural rule: n != 1
        if (n == 1) {
            return self.gettext(singular);
        }
        // Try to get plural form
        if (self.catalog) |cat| {
            if (cat.get(plural)) |trans| {
                return trans;
            }
        }
        return if (n == 1) singular else plural;
    }

    /// Plural with context
    pub fn npgettext(
        self: *const Self,
        context: []const u8,
        singular: []const u8,
        plural: []const u8,
        n: usize,
    ) []const u8 {
        _ = context;
        return self.ngettext(singular, plural, n);
    }

    /// Get charset
    pub fn getCharset(self: *const Self) []const u8 {
        return self.charset;
    }

    /// Set output charset
    pub fn setOutputCharset(self: *Self, charset: []const u8) void {
        self.charset = charset;
    }

    /// Add a fallback translation
    pub fn addFallback(self: *Self, fb: *const Self) void {
        if (self.fallback) |existing| {
            // Chain fallbacks
            var existing_mut = @constCast(existing);
            existing_mut.addFallback(fb);
        } else {
            self.fallback = fb;
        }
    }

    /// Install as global _() function
    pub fn install(self: *const Self) void {
        current_translation = self;
    }

    /// Get language info
    pub fn info(self: *const Self) ?[]const u8 {
        return self.language;
    }
};

// ============================================================================
// GNUTranslations - Parse .mo files
// ============================================================================

/// GNU gettext .mo file format translation
pub const GNUTranslations = struct {
    const Self = @This();

    base: Translation,
    /// Plural form function index
    plural_func: ?*const fn (n: usize) usize = null,

    /// Magic number for .mo files (little endian)
    pub const MO_MAGIC_LE: u32 = 0x950412de;
    /// Magic number for .mo files (big endian)
    pub const MO_MAGIC_BE: u32 = 0xde120495;

    /// Create from .mo file
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        return try parse(allocator, file.reader());
    }

    /// Parse .mo file
    pub fn parse(allocator: std.mem.Allocator, reader: anytype) !Self {
        // Read magic number
        const magic = try reader.readInt(u32, .little);

        const is_le = magic == MO_MAGIC_LE;
        const is_be = magic == MO_MAGIC_BE;

        if (!is_le and !is_be) {
            return error.InvalidMOFile;
        }

        const endian: std.builtin.Endian = if (is_le) .little else .big;

        // Read header
        const version = try reader.readInt(u32, endian);
        _ = version; // Usually 0
        const nstrings = try reader.readInt(u32, endian);
        const orig_offset = try reader.readInt(u32, endian);
        const trans_offset = try reader.readInt(u32, endian);
        _ = orig_offset;
        _ = trans_offset;

        var catalog = std.StringHashMap([]const u8).init(allocator);

        // Read string pairs (simplified - real impl needs seeking)
        for (0..nstrings) |_| {
            // Would read from string tables
            _ = &catalog;
        }

        return Self{
            .base = .{
                .catalog = catalog,
                .charset = "UTF-8",
                .fallback = null,
                .allocator = allocator,
            },
        };
    }

    /// Get plural index for a count
    pub fn plural(self: *const Self, n: usize) usize {
        if (self.plural_func) |func| {
            return func(n);
        }
        // Default: n != 1
        return if (n == 1) 0 else 1;
    }
};

// ============================================================================
// Global Translation Registry
// ============================================================================

var translations: ?std.StringHashMap(*Translation) = null;
var translations_allocator: ?std.mem.Allocator = null;
var current_translation: ?*const Translation = null;
var current_domain: []const u8 = DEFAULT_DOMAIN;
var locale_dirs: ?std.StringHashMap([]const u8) = null;

/// Initialize the translation registry
pub fn initRegistry(allocator: std.mem.Allocator) void {
    if (translations == null) {
        translations = std.StringHashMap(*Translation).init(allocator);
        locale_dirs = std.StringHashMap([]const u8).init(allocator);
        translations_allocator = allocator;
    }
}

/// Deinitialize the translation registry
pub fn deinitRegistry() void {
    if (translations) |*t| {
        t.deinit();
        translations = null;
    }
    if (locale_dirs) |*ld| {
        ld.deinit();
        locale_dirs = null;
    }
    translations_allocator = null;
    current_translation = null;
}

// ============================================================================
// High-Level API
// ============================================================================

/// Set the text domain
pub fn textdomain(domain: ?[]const u8) []const u8 {
    if (domain) |d| {
        current_domain = d;
    }
    return current_domain;
}

/// Bind a domain to a locale directory
pub fn bindtextdomain(domain: []const u8, localedir: ?[]const u8) []const u8 {
    const dir = localedir orelse DEFAULT_LOCALEDIR;
    if (locale_dirs) |*ld| {
        ld.put(domain, dir) catch {};
    }
    return dir;
}

/// Set the output charset for a domain
pub fn bind_textdomain_codeset(domain: []const u8, codeset: ?[]const u8) ?[]const u8 {
    _ = domain;
    return codeset;
}

/// Get translation for current domain
pub fn gettext(message: []const u8) []const u8 {
    return dgettext(current_domain, message);
}

/// Get translation for specific domain
pub fn dgettext(domain: []const u8, message: []const u8) []const u8 {
    _ = domain;
    if (current_translation) |t| {
        return t.gettext(message);
    }
    return message;
}

/// Get plural translation for current domain
pub fn ngettext(singular: []const u8, plural: []const u8, n: usize) []const u8 {
    return dngettext(current_domain, singular, plural, n);
}

/// Get plural translation for specific domain
pub fn dngettext(
    domain: []const u8,
    singular: []const u8,
    plural: []const u8,
    n: usize,
) []const u8 {
    _ = domain;
    if (current_translation) |t| {
        return t.ngettext(singular, plural, n);
    }
    return if (n == 1) singular else plural;
}

/// Get translation with context
pub fn pgettext(context: []const u8, message: []const u8) []const u8 {
    _ = context;
    return gettext(message);
}

/// Get plural translation with context
pub fn npgettext(
    context: []const u8,
    singular: []const u8,
    plural: []const u8,
    n: usize,
) []const u8 {
    _ = context;
    return ngettext(singular, plural, n);
}

// ============================================================================
// Find Translation
// ============================================================================

/// Find a translation for the given domain and languages
pub fn find(
    allocator: std.mem.Allocator,
    domain: []const u8,
    localedir: ?[]const u8,
    languages: ?[]const []const u8,
) !?[]const u8 {
    const dir = localedir orelse DEFAULT_LOCALEDIR;
    const langs = languages orelse &[_][]const u8{"en"};

    // Try each language
    for (langs) |lang| {
        // Try: localedir/lang/LC_MESSAGES/domain.mo
        const path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}/LC_MESSAGES/{s}.mo",
            .{ dir, lang, domain },
        );
        defer allocator.free(path);

        if (std.fs.cwd().access(path, .{})) |_| {
            return try allocator.dupe(u8, path);
        } else |_| {}
    }

    return null;
}

// ============================================================================
// NullTranslations - Pass-through
// ============================================================================

/// Null translation (passes through all strings unchanged)
pub const NullTranslations = struct {
    base: Translation,

    pub fn init_null() NullTranslations {
        return .{
            .base = NULL_TRANSLATION,
        };
    }
};

// ============================================================================
// Locale helpers
// ============================================================================

/// Get list of languages from environment
pub fn getLanguages() []const []const u8 {
    // Check LANGUAGE, LC_ALL, LC_MESSAGES, LANG
    const env_vars = [_][]const u8{
        "LANGUAGE",
        "LC_ALL",
        "LC_MESSAGES",
        "LANG",
    };

    for (env_vars) |var_name| {
        if (std.posix.getenv(var_name)) |value| {
            if (value.len > 0 and !std.mem.eql(u8, value, "C") and !std.mem.eql(u8, value, "POSIX")) {
                // Would split on ':' for LANGUAGE
                return &[_][]const u8{value};
            }
        }
    }

    return &[_][]const u8{};
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the gettext module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    deinitRegistry();
    current_domain = DEFAULT_DOMAIN;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Translation gettext passthrough" {
    const t = NULL_TRANSLATION;
    try std.testing.expectEqualStrings("hello", t.gettext("hello"));
}

test "Translation ngettext" {
    const t = NULL_TRANSLATION;
    try std.testing.expectEqualStrings("apple", t.ngettext("apple", "apples", 1));
    try std.testing.expectEqualStrings("apples", t.ngettext("apple", "apples", 2));
    try std.testing.expectEqualStrings("apples", t.ngettext("apple", "apples", 0));
}

test "textdomain" {
    try std.testing.expectEqualStrings(DEFAULT_DOMAIN, textdomain(null));
    _ = textdomain("myapp");
    try std.testing.expectEqualStrings("myapp", textdomain(null));
    _ = textdomain(DEFAULT_DOMAIN); // Reset
}

test "gettext passthrough" {
    current_translation = null;
    try std.testing.expectEqualStrings("test", gettext("test"));
}

test "ngettext passthrough" {
    current_translation = null;
    try std.testing.expectEqualStrings("item", ngettext("item", "items", 1));
    try std.testing.expectEqualStrings("items", ngettext("item", "items", 5));
}

test "NullTranslations" {
    const null_t = NullTranslations.init_null();
    try std.testing.expectEqualStrings("test", null_t.base.gettext("test"));
}

test "mo magic numbers" {
    try std.testing.expectEqual(@as(u32, 0x950412de), GNUTranslations.MO_MAGIC_LE);
    try std.testing.expectEqual(@as(u32, 0xde120495), GNUTranslations.MO_MAGIC_BE);
}

test "DEFAULT_LOCALEDIR" {
    try std.testing.expectEqualStrings("/usr/share/locale", DEFAULT_LOCALEDIR);
}
