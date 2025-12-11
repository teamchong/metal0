/// gettext - Internationalization (i18n) services
/// Mirrors cpython/Lib/gettext.py
///
/// Provides GNU gettext-compatible message translation.
/// Used for internationalizing Python programs.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

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
    catalog: ?hashmap_helper.StringHashMap([]const u8),
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

        // Read entire file for random access to string tables
        const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(data);

        return try parseData(allocator, data);
    }

    /// Parse .mo file from reader (streaming - limited functionality)
    pub fn parse(allocator: std.mem.Allocator, reader: anytype) !Self {
        // For streaming, read header only - strings require seeking
        const magic = try reader.readInt(u32, .little);
        const is_le = magic == MO_MAGIC_LE;
        const is_be = magic == MO_MAGIC_BE;
        if (!is_le and !is_be) return error.InvalidMOFile;

        // Return empty catalog for streaming (use fromFile for full support)
        var catalog = hashmap_helper.StringHashMap([]const u8).init(allocator);
        return Self{
            .base = .{
                .catalog = catalog,
                .charset = "UTF-8",
                .fallback = null,
                .allocator = allocator,
            },
        };
    }

    /// Parse .mo file from memory buffer (full support)
    fn parseData(allocator: std.mem.Allocator, data: []const u8) !Self {
        if (data.len < 28) return error.InvalidMOFile;

        // Read magic number
        const magic = std.mem.readInt(u32, data[0..4], .little);
        const is_le = magic == MO_MAGIC_LE;
        const is_be = magic == MO_MAGIC_BE;
        if (!is_le and !is_be) return error.InvalidMOFile;

        const endian: std.builtin.Endian = if (is_le) .little else .big;

        // Read header
        const nstrings = std.mem.readInt(u32, data[8..12], endian);
        const orig_offset = std.mem.readInt(u32, data[12..16], endian);
        const trans_offset = std.mem.readInt(u32, data[16..20], endian);

        var catalog = hashmap_helper.StringHashMap([]const u8).init(allocator);

        // Read string pairs from offset tables
        var i: u32 = 0;
        while (i < nstrings) : (i += 1) {
            // Original string table entry: length, offset
            const orig_entry_off = orig_offset + i * 8;
            if (orig_entry_off + 8 > data.len) break;

            const orig_len = std.mem.readInt(u32, data[orig_entry_off..][0..4], endian);
            const orig_off = std.mem.readInt(u32, data[orig_entry_off + 4 ..][0..4], endian);

            // Translation string table entry
            const trans_entry_off = trans_offset + i * 8;
            if (trans_entry_off + 8 > data.len) break;

            const trans_len = std.mem.readInt(u32, data[trans_entry_off..][0..4], endian);
            const trans_off = std.mem.readInt(u32, data[trans_entry_off + 4 ..][0..4], endian);

            // Extract strings
            if (orig_off + orig_len <= data.len and trans_off + trans_len <= data.len) {
                const orig_str = try allocator.dupe(u8, data[orig_off..][0..orig_len]);
                const trans_str = try allocator.dupe(u8, data[trans_off..][0..trans_len]);
                try catalog.put(orig_str, trans_str);
            }
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

var translations: ?hashmap_helper.StringHashMap(*Translation) = null;
var translations_allocator: ?std.mem.Allocator = null;
var current_translation: ?*const Translation = null;
var current_domain: []const u8 = DEFAULT_DOMAIN;
var locale_dirs: ?hashmap_helper.StringHashMap([]const u8) = null;

/// Initialize the translation registry
pub fn initRegistry(allocator: std.mem.Allocator) void {
    if (translations == null) {
        translations = hashmap_helper.StringHashMap(*Translation).init(allocator);
        locale_dirs = hashmap_helper.StringHashMap([]const u8).init(allocator);
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

/// Static storage for language list results
var language_result: [16][]const u8 = undefined;
var language_count: usize = 0;

/// Get list of languages from environment
/// LANGUAGE is colon-separated, others are single values
pub fn getLanguages() []const []const u8 {
    language_count = 0;

    // LANGUAGE has highest priority and can be colon-separated
    if (std.posix.getenv("LANGUAGE")) |value| {
        if (value.len > 0 and !std.mem.eql(u8, value, "C") and !std.mem.eql(u8, value, "POSIX")) {
            // Split on ':' for multiple languages
            var iter = std.mem.splitScalar(u8, value, ':');
            while (iter.next()) |lang| {
                if (lang.len > 0 and language_count < language_result.len) {
                    // Also handle locale modifiers (strip .encoding and @modifier)
                    var clean_lang = lang;
                    if (std.mem.indexOf(u8, clean_lang, ".")) |dot_idx| {
                        clean_lang = clean_lang[0..dot_idx];
                    }
                    if (std.mem.indexOf(u8, clean_lang, "@")) |at_idx| {
                        clean_lang = clean_lang[0..at_idx];
                    }
                    if (clean_lang.len > 0) {
                        language_result[language_count] = clean_lang;
                        language_count += 1;
                    }
                }
            }
            if (language_count > 0) {
                return language_result[0..language_count];
            }
        }
    }

    // Fall back to LC_ALL, LC_MESSAGES, LANG (single values)
    const env_vars = [_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" };
    for (env_vars) |var_name| {
        if (std.posix.getenv(var_name)) |value| {
            if (value.len > 0 and !std.mem.eql(u8, value, "C") and !std.mem.eql(u8, value, "POSIX")) {
                // Strip encoding and modifier
                var clean_lang = value;
                if (std.mem.indexOf(u8, clean_lang, ".")) |dot_idx| {
                    clean_lang = clean_lang[0..dot_idx];
                }
                if (std.mem.indexOf(u8, clean_lang, "@")) |at_idx| {
                    clean_lang = clean_lang[0..at_idx];
                }
                if (clean_lang.len > 0) {
                    language_result[0] = clean_lang;
                    return language_result[0..1];
                }
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
