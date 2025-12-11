//! Python 'html' module - HTML processing utilities
//!
//! Provides functions for escaping and unescaping HTML entities.
//!
//! Mirrors: CPython Lib/html/__init__.py

const entities = @import("html/entities.zig");
const utils = @import("html/utils.zig");
const parser = @import("html/parser.zig");

// Re-export entities
pub const html5_entities = entities.html5_entities;

// Re-export utility functions
pub const escape = utils.escape;
pub const unescape = utils.unescape;
pub const isHtmlSpace = utils.isHtmlSpace;
pub const normalizeWhitespace = utils.normalizeWhitespace;
pub const stripTags = utils.stripTags;

// Re-export parser
pub const HTMLParser = parser.HTMLParser;

// Re-export tests
test {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(utils);
}
