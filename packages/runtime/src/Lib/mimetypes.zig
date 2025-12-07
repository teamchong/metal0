//! CPython source: Lib/mimetypes.py
//!
//! Provides functions to map filenames to MIME types and vice versa.
//!
//! Mirrors: CPython Lib/mimetypes.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Constants
// ============================================================================

/// Default MIME type when unknown
pub const DEFAULT_TYPE = "application/octet-stream";

/// Suffix map for encoding detection
pub const SUFFIX_MAP = struct {
    pub const @".svgz" = ".svg.gz";
    pub const @".tgz" = ".tar.gz";
    pub const @".taz" = ".tar.gz";
    pub const @".tz" = ".tar.gz";
    pub const @".tbz2" = ".tar.bz2";
    pub const @".txz" = ".tar.xz";
};

/// Encodings map
pub const ENCODINGS_MAP = struct {
    pub const @".gz" = "gzip";
    pub const @".Z" = "compress";
    pub const @".bz2" = "bzip2";
    pub const @".xz" = "xz";
    pub const @".br" = "br";
};

// ============================================================================
// Built-in MIME Types
// ============================================================================

/// Common MIME types (extension -> type)
pub const TYPES_MAP = [_]struct { ext: []const u8, mime: []const u8 }{
    // Text
    .{ .ext = ".txt", .mime = "text/plain" },
    .{ .ext = ".html", .mime = "text/html" },
    .{ .ext = ".htm", .mime = "text/html" },
    .{ .ext = ".css", .mime = "text/css" },
    .{ .ext = ".js", .mime = "application/javascript" },
    .{ .ext = ".mjs", .mime = "application/javascript" },
    .{ .ext = ".json", .mime = "application/json" },
    .{ .ext = ".xml", .mime = "application/xml" },
    .{ .ext = ".csv", .mime = "text/csv" },
    .{ .ext = ".tsv", .mime = "text/tab-separated-values" },
    .{ .ext = ".md", .mime = "text/markdown" },
    .{ .ext = ".yaml", .mime = "application/x-yaml" },
    .{ .ext = ".yml", .mime = "application/x-yaml" },
    .{ .ext = ".toml", .mime = "application/toml" },

    // Images
    .{ .ext = ".jpg", .mime = "image/jpeg" },
    .{ .ext = ".jpeg", .mime = "image/jpeg" },
    .{ .ext = ".png", .mime = "image/png" },
    .{ .ext = ".gif", .mime = "image/gif" },
    .{ .ext = ".webp", .mime = "image/webp" },
    .{ .ext = ".svg", .mime = "image/svg+xml" },
    .{ .ext = ".ico", .mime = "image/x-icon" },
    .{ .ext = ".bmp", .mime = "image/bmp" },
    .{ .ext = ".tiff", .mime = "image/tiff" },
    .{ .ext = ".tif", .mime = "image/tiff" },
    .{ .ext = ".avif", .mime = "image/avif" },

    // Audio
    .{ .ext = ".mp3", .mime = "audio/mpeg" },
    .{ .ext = ".wav", .mime = "audio/wav" },
    .{ .ext = ".ogg", .mime = "audio/ogg" },
    .{ .ext = ".flac", .mime = "audio/flac" },
    .{ .ext = ".aac", .mime = "audio/aac" },
    .{ .ext = ".m4a", .mime = "audio/mp4" },
    .{ .ext = ".weba", .mime = "audio/webm" },

    // Video
    .{ .ext = ".mp4", .mime = "video/mp4" },
    .{ .ext = ".webm", .mime = "video/webm" },
    .{ .ext = ".avi", .mime = "video/x-msvideo" },
    .{ .ext = ".mov", .mime = "video/quicktime" },
    .{ .ext = ".mkv", .mime = "video/x-matroska" },
    .{ .ext = ".wmv", .mime = "video/x-ms-wmv" },
    .{ .ext = ".flv", .mime = "video/x-flv" },
    .{ .ext = ".m4v", .mime = "video/mp4" },

    // Documents
    .{ .ext = ".pdf", .mime = "application/pdf" },
    .{ .ext = ".doc", .mime = "application/msword" },
    .{ .ext = ".docx", .mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
    .{ .ext = ".xls", .mime = "application/vnd.ms-excel" },
    .{ .ext = ".xlsx", .mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
    .{ .ext = ".ppt", .mime = "application/vnd.ms-powerpoint" },
    .{ .ext = ".pptx", .mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
    .{ .ext = ".odt", .mime = "application/vnd.oasis.opendocument.text" },
    .{ .ext = ".ods", .mime = "application/vnd.oasis.opendocument.spreadsheet" },
    .{ .ext = ".odp", .mime = "application/vnd.oasis.opendocument.presentation" },
    .{ .ext = ".rtf", .mime = "application/rtf" },
    .{ .ext = ".epub", .mime = "application/epub+zip" },

    // Archives
    .{ .ext = ".zip", .mime = "application/zip" },
    .{ .ext = ".tar", .mime = "application/x-tar" },
    .{ .ext = ".gz", .mime = "application/gzip" },
    .{ .ext = ".bz2", .mime = "application/x-bzip2" },
    .{ .ext = ".xz", .mime = "application/x-xz" },
    .{ .ext = ".7z", .mime = "application/x-7z-compressed" },
    .{ .ext = ".rar", .mime = "application/vnd.rar" },

    // Programming
    .{ .ext = ".py", .mime = "text/x-python" },
    .{ .ext = ".zig", .mime = "text/x-zig" },
    .{ .ext = ".c", .mime = "text/x-c" },
    .{ .ext = ".h", .mime = "text/x-c" },
    .{ .ext = ".cpp", .mime = "text/x-c++src" },
    .{ .ext = ".hpp", .mime = "text/x-c++hdr" },
    .{ .ext = ".java", .mime = "text/x-java-source" },
    .{ .ext = ".rs", .mime = "text/x-rust" },
    .{ .ext = ".go", .mime = "text/x-go" },
    .{ .ext = ".rb", .mime = "text/x-ruby" },
    .{ .ext = ".php", .mime = "text/x-php" },
    .{ .ext = ".sh", .mime = "application/x-sh" },
    .{ .ext = ".bash", .mime = "application/x-sh" },
    .{ .ext = ".zsh", .mime = "application/x-sh" },
    .{ .ext = ".ts", .mime = "application/typescript" },
    .{ .ext = ".tsx", .mime = "text/tsx" },
    .{ .ext = ".jsx", .mime = "text/jsx" },
    .{ .ext = ".vue", .mime = "text/x-vue" },
    .{ .ext = ".svelte", .mime = "text/x-svelte" },

    // Fonts
    .{ .ext = ".ttf", .mime = "font/ttf" },
    .{ .ext = ".otf", .mime = "font/otf" },
    .{ .ext = ".woff", .mime = "font/woff" },
    .{ .ext = ".woff2", .mime = "font/woff2" },
    .{ .ext = ".eot", .mime = "application/vnd.ms-fontobject" },

    // Data
    .{ .ext = ".sql", .mime = "application/sql" },
    .{ .ext = ".db", .mime = "application/x-sqlite3" },
    .{ .ext = ".sqlite", .mime = "application/x-sqlite3" },
    .{ .ext = ".sqlite3", .mime = "application/x-sqlite3" },

    // Web
    .{ .ext = ".wasm", .mime = "application/wasm" },
    .{ .ext = ".map", .mime = "application/json" },
    .{ .ext = ".manifest", .mime = "text/cache-manifest" },

    // Other
    .{ .ext = ".exe", .mime = "application/x-msdownload" },
    .{ .ext = ".dll", .mime = "application/x-msdownload" },
    .{ .ext = ".so", .mime = "application/x-sharedlib" },
    .{ .ext = ".dylib", .mime = "application/x-mach-binary" },
    .{ .ext = ".bin", .mime = "application/octet-stream" },
    .{ .ext = ".iso", .mime = "application/x-iso9660-image" },
    .{ .ext = ".dmg", .mime = "application/x-apple-diskimage" },
    .{ .ext = ".deb", .mime = "application/vnd.debian.binary-package" },
    .{ .ext = ".rpm", .mime = "application/x-rpm" },
};

// ============================================================================
// MimeTypes Database
// ============================================================================

/// MIME types database
pub const MimeTypes = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    types_map: hashmap_helper.StringHashMap([]const u8),
    types_map_inv: hashmap_helper.StringHashMap([]const u8),
    encodings_map: hashmap_helper.StringHashMap([]const u8),
    suffix_map: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, filenames: ?[]const []const u8, strict: bool) !Self {
        _ = strict;
        var self = Self{
            .allocator = allocator,
            .types_map = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .types_map_inv = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .encodings_map = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .suffix_map = hashmap_helper.StringHashMap([]const u8).init(allocator),
        };

        // Initialize built-in types
        for (TYPES_MAP) |entry| {
            try self.types_map.put(entry.ext, entry.mime);
            try self.types_map_inv.put(entry.mime, entry.ext);
        }

        // Initialize encodings
        try self.encodings_map.put(".gz", "gzip");
        try self.encodings_map.put(".Z", "compress");
        try self.encodings_map.put(".bz2", "bzip2");
        try self.encodings_map.put(".xz", "xz");
        try self.encodings_map.put(".br", "br");

        // Initialize suffix map
        try self.suffix_map.put(".svgz", ".svg.gz");
        try self.suffix_map.put(".tgz", ".tar.gz");
        try self.suffix_map.put(".taz", ".tar.gz");
        try self.suffix_map.put(".tz", ".tar.gz");
        try self.suffix_map.put(".tbz2", ".tar.bz2");
        try self.suffix_map.put(".txz", ".tar.xz");

        // Read additional files
        if (filenames) |files| {
            for (files) |filename| {
                self.read(filename, strict) catch continue;
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.types_map.deinit();
        self.types_map_inv.deinit();
        self.encodings_map.deinit();
        self.suffix_map.deinit();
    }

    /// Read a MIME types file
    pub fn read(self: *Self, filename: []const u8, strict: bool) !void {
        _ = strict;
        const file = std.fs.openFileAbsolute(filename, .{}) catch return;
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        var line_buf: [1024]u8 = undefined;
        while (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch null) |line| {
            // Skip comments and empty lines
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse: type ext1 ext2 ...
            var it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const mime_type = it.next() orelse continue;

            while (it.next()) |ext| {
                var ext_buf: [64]u8 = undefined;
                if (ext[0] != '.') {
                    ext_buf[0] = '.';
                    @memcpy(ext_buf[1 .. ext.len + 1], ext);
                    try self.types_map.put(ext_buf[0 .. ext.len + 1], mime_type);
                } else {
                    try self.types_map.put(ext, mime_type);
                }
            }
        }
    }

    /// Read a MIME types file (fp version)
    pub fn readfp(self: *Self, fp: anytype, strict: bool) !void {
        _ = self;
        _ = fp;
        _ = strict;
        // Would read from file pointer
    }

    /// Guess MIME type from URL/filename
    pub fn guessType(self: *Self, url: []const u8, strict: bool) struct { mime: ?[]const u8, encoding: ?[]const u8 } {
        _ = strict;

        // Extract filename from URL
        var filename = url;
        if (std.mem.lastIndexOf(u8, url, "/")) |idx| {
            filename = url[idx + 1 ..];
        }

        // Check suffix map first
        const ext = std.fs.path.extension(filename);
        if (self.suffix_map.get(ext)) |mapped| {
            filename = mapped;
        }

        // Check encoding
        var encoding: ?[]const u8 = null;
        var base_ext = ext;
        if (self.encodings_map.get(ext)) |enc| {
            encoding = enc;
            // Remove encoding extension and get base extension
            if (filename.len > ext.len) {
                const without_enc = filename[0 .. filename.len - ext.len];
                base_ext = std.fs.path.extension(without_enc);
            }
        }

        // Get MIME type
        const mime = self.types_map.get(base_ext);

        return .{ .mime = mime, .encoding = encoding };
    }

    /// Guess all extensions for a MIME type
    pub fn guessAllExtensions(self: *Self, mime_type: []const u8, strict: bool) []const []const u8 {
        _ = self;
        _ = mime_type;
        _ = strict;
        // Would return all extensions for type
        return &[_][]const u8{};
    }

    /// Guess extension for a MIME type
    pub fn guessExtension(self: *Self, mime_type: []const u8, strict: bool) ?[]const u8 {
        _ = strict;
        return self.types_map_inv.get(mime_type);
    }

    /// Add a type mapping
    pub fn addType(self: *Self, mime_type: []const u8, ext: []const u8, strict: bool) !void {
        _ = strict;
        try self.types_map.put(ext, mime_type);
        try self.types_map_inv.put(mime_type, ext);
    }
};

// ============================================================================
// Module-Level Functions (use global database)
// ============================================================================

var global_db: ?MimeTypes = null;
var global_inited: bool = false;

/// Initialize the global database
pub fn init(files: ?[]const []const u8) !void {
    if (global_inited) return;
    global_db = try MimeTypes.init(std.heap.page_allocator, files, true);
    global_inited = true;
}

/// Guess type from URL
pub fn guess_type(url: []const u8) struct { mime: ?[]const u8, encoding: ?[]const u8 } {
    if (!global_inited) {
        init(null) catch return .{ .mime = null, .encoding = null };
    }
    return global_db.?.guessType(url, true);
}

/// Guess extension for type
pub fn guess_extension(mime_type: []const u8) ?[]const u8 {
    if (!global_inited) {
        init(null) catch return null;
    }
    return global_db.?.guessExtension(mime_type, true);
}

/// Guess all extensions for type
pub fn guess_all_extensions(mime_type: []const u8) []const []const u8 {
    if (!global_inited) {
        init(null) catch return &[_][]const u8{};
    }
    return global_db.?.guessAllExtensions(mime_type, true);
}

/// Add a type mapping
pub fn add_type(mime_type: []const u8, ext: []const u8, strict: bool) !void {
    if (!global_inited) {
        try init(null);
    }
    try global_db.?.addType(mime_type, ext, strict);
}

// ============================================================================
// Known Files
// ============================================================================

/// Standard MIME type file locations
pub const KNOWNFILES = [_][]const u8{
    "/etc/mime.types",
    "/etc/httpd/mime.types",
    "/etc/httpd/conf/mime.types",
    "/etc/apache/mime.types",
    "/etc/apache2/mime.types",
    "/usr/local/etc/httpd/conf/mime.types",
    "/usr/local/lib/netscape/mime.types",
    "/usr/local/etc/mime.types",
};

// ============================================================================
// Tests
// ============================================================================

test "MimeTypes init and guess" {
    const allocator = std.testing.allocator;
    var db = try MimeTypes.init(allocator, null, true);
    defer db.deinit();

    const result = db.guessType("test.html", true);
    try std.testing.expectEqualStrings("text/html", result.mime.?);
    try std.testing.expect(result.encoding == null);
}

test "guess type with encoding" {
    const allocator = std.testing.allocator;
    var db = try MimeTypes.init(allocator, null, true);
    defer db.deinit();

    const result = db.guessType("archive.tar.gz", true);
    try std.testing.expectEqualStrings("gzip", result.encoding.?);
}

test "guess extension" {
    const allocator = std.testing.allocator;
    var db = try MimeTypes.init(allocator, null, true);
    defer db.deinit();

    const ext = db.guessExtension("text/html", true);
    try std.testing.expect(ext != null);
}

test "common mime types" {
    const allocator = std.testing.allocator;
    var db = try MimeTypes.init(allocator, null, true);
    defer db.deinit();

    // Test various common types
    try std.testing.expectEqualStrings("application/json", db.guessType("data.json", true).mime.?);
    try std.testing.expectEqualStrings("image/png", db.guessType("image.png", true).mime.?);
    try std.testing.expectEqualStrings("application/pdf", db.guessType("doc.pdf", true).mime.?);
    try std.testing.expectEqualStrings("text/x-python", db.guessType("script.py", true).mime.?);
}

test "add custom type" {
    const allocator = std.testing.allocator;
    var db = try MimeTypes.init(allocator, null, true);
    defer db.deinit();

    try db.addType("application/x-custom", ".custom", true);
    const result = db.guessType("file.custom", true);
    try std.testing.expectEqualStrings("application/x-custom", result.mime.?);
}
