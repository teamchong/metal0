//! CPython source: Lib/keyword.py
//!
//! Provides functions to check if strings are Python keywords or soft keywords.
//!
//! Mirrors: CPython Lib/keyword.py

const std = @import("std");

// ============================================================================
// Python Keywords
// ============================================================================

/// List of all Python keywords
pub const kwlist = [_][]const u8{
    "False",
    "None",
    "True",
    "and",
    "as",
    "assert",
    "async",
    "await",
    "break",
    "class",
    "continue",
    "def",
    "del",
    "elif",
    "else",
    "except",
    "finally",
    "for",
    "from",
    "global",
    "if",
    "import",
    "in",
    "is",
    "lambda",
    "nonlocal",
    "not",
    "or",
    "pass",
    "raise",
    "return",
    "try",
    "while",
    "with",
    "yield",
};

/// Soft keywords (context-dependent keywords)
pub const softkwlist = [_][]const u8{
    "match",
    "case",
    "type",
    "_",
};

// ============================================================================
// Keyword Lookup
// ============================================================================

const KeywordSet = std.StaticStringMap(void);

const KEYWORDS = KeywordSet.initComptime(.{
    .{ "False", {} },
    .{ "None", {} },
    .{ "True", {} },
    .{ "and", {} },
    .{ "as", {} },
    .{ "assert", {} },
    .{ "async", {} },
    .{ "await", {} },
    .{ "break", {} },
    .{ "class", {} },
    .{ "continue", {} },
    .{ "def", {} },
    .{ "del", {} },
    .{ "elif", {} },
    .{ "else", {} },
    .{ "except", {} },
    .{ "finally", {} },
    .{ "for", {} },
    .{ "from", {} },
    .{ "global", {} },
    .{ "if", {} },
    .{ "import", {} },
    .{ "in", {} },
    .{ "is", {} },
    .{ "lambda", {} },
    .{ "nonlocal", {} },
    .{ "not", {} },
    .{ "or", {} },
    .{ "pass", {} },
    .{ "raise", {} },
    .{ "return", {} },
    .{ "try", {} },
    .{ "while", {} },
    .{ "with", {} },
    .{ "yield", {} },
});

const SOFT_KEYWORDS = KeywordSet.initComptime(.{
    .{ "match", {} },
    .{ "case", {} },
    .{ "type", {} },
    .{ "_", {} },
});

// ============================================================================
// Public API
// ============================================================================

/// Check if a string is a Python keyword
pub fn iskeyword(s: []const u8) bool {
    return KEYWORDS.has(s);
}

/// Check if a string is a soft keyword
pub fn issoftkeyword(s: []const u8) bool {
    return SOFT_KEYWORDS.has(s);
}

/// Get all keywords as a list
pub fn getKeywords() []const []const u8 {
    return &kwlist;
}

/// Get all soft keywords as a list
pub fn getSoftKeywords() []const []const u8 {
    return &softkwlist;
}

/// Count of keywords
pub fn keywordCount() usize {
    return kwlist.len;
}

/// Count of soft keywords
pub fn softKeywordCount() usize {
    return softkwlist.len;
}

// ============================================================================
// Python Version Info
// ============================================================================

/// Python version this keyword list corresponds to
pub const python_version = struct {
    pub const major: u8 = 3;
    pub const minor: u8 = 12;
    pub const micro: u8 = 0;

    pub fn string() []const u8 {
        return "3.12.0";
    }
};

// ============================================================================
// Categorized Keywords
// ============================================================================

/// Keywords that are boolean/None literals
pub const literal_keywords = [_][]const u8{
    "False",
    "None",
    "True",
};

/// Keywords that are control flow statements
pub const control_flow_keywords = [_][]const u8{
    "break",
    "continue",
    "if",
    "elif",
    "else",
    "for",
    "while",
    "try",
    "except",
    "finally",
    "raise",
    "return",
    "yield",
    "pass",
};

/// Keywords that are logical operators
pub const logical_keywords = [_][]const u8{
    "and",
    "or",
    "not",
    "in",
    "is",
};

/// Keywords related to definitions
pub const definition_keywords = [_][]const u8{
    "class",
    "def",
    "lambda",
    "async",
    "await",
};

/// Keywords related to imports
pub const import_keywords = [_][]const u8{
    "import",
    "from",
    "as",
};

/// Keywords related to scope
pub const scope_keywords = [_][]const u8{
    "global",
    "nonlocal",
    "del",
};

/// Keywords related to context managers
pub const context_keywords = [_][]const u8{
    "with",
};

/// Keywords related to assertions
pub const assertion_keywords = [_][]const u8{
    "assert",
};

// ============================================================================
// Check Functions for Categories
// ============================================================================

/// Check if keyword is a literal
pub fn isLiteralKeyword(s: []const u8) bool {
    for (literal_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

/// Check if keyword is control flow
pub fn isControlFlowKeyword(s: []const u8) bool {
    for (control_flow_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

/// Check if keyword is logical operator
pub fn isLogicalKeyword(s: []const u8) bool {
    for (logical_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

/// Check if keyword is definition-related
pub fn isDefinitionKeyword(s: []const u8) bool {
    for (definition_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

/// Check if keyword is import-related
pub fn isImportKeyword(s: []const u8) bool {
    for (import_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

/// Check if keyword is scope-related
pub fn isScopeKeyword(s: []const u8) bool {
    for (scope_keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "iskeyword" {
    try std.testing.expect(iskeyword("if"));
    try std.testing.expect(iskeyword("def"));
    try std.testing.expect(iskeyword("class"));
    try std.testing.expect(iskeyword("True"));
    try std.testing.expect(iskeyword("False"));
    try std.testing.expect(iskeyword("None"));
    try std.testing.expect(iskeyword("and"));
    try std.testing.expect(iskeyword("or"));
    try std.testing.expect(iskeyword("not"));
    try std.testing.expect(iskeyword("async"));
    try std.testing.expect(iskeyword("await"));

    try std.testing.expect(!iskeyword("hello"));
    try std.testing.expect(!iskeyword("print"));
    try std.testing.expect(!iskeyword("len"));
    try std.testing.expect(!iskeyword("match")); // soft keyword
    try std.testing.expect(!iskeyword("case")); // soft keyword
}

test "issoftkeyword" {
    try std.testing.expect(issoftkeyword("match"));
    try std.testing.expect(issoftkeyword("case"));
    try std.testing.expect(issoftkeyword("type"));
    try std.testing.expect(issoftkeyword("_"));

    try std.testing.expect(!issoftkeyword("if"));
    try std.testing.expect(!issoftkeyword("def"));
    try std.testing.expect(!issoftkeyword("hello"));
}

test "kwlist" {
    try std.testing.expectEqual(@as(usize, 35), kwlist.len);

    // Check some specific keywords are in the list
    var found_if = false;
    var found_def = false;
    var found_class = false;
    for (kwlist) |kw| {
        if (std.mem.eql(u8, kw, "if")) found_if = true;
        if (std.mem.eql(u8, kw, "def")) found_def = true;
        if (std.mem.eql(u8, kw, "class")) found_class = true;
    }
    try std.testing.expect(found_if);
    try std.testing.expect(found_def);
    try std.testing.expect(found_class);
}

test "softkwlist" {
    try std.testing.expectEqual(@as(usize, 4), softkwlist.len);
}

test "keyword categories" {
    try std.testing.expect(isLiteralKeyword("True"));
    try std.testing.expect(isLiteralKeyword("False"));
    try std.testing.expect(isLiteralKeyword("None"));

    try std.testing.expect(isControlFlowKeyword("if"));
    try std.testing.expect(isControlFlowKeyword("while"));
    try std.testing.expect(isControlFlowKeyword("for"));

    try std.testing.expect(isLogicalKeyword("and"));
    try std.testing.expect(isLogicalKeyword("or"));
    try std.testing.expect(isLogicalKeyword("not"));

    try std.testing.expect(isDefinitionKeyword("def"));
    try std.testing.expect(isDefinitionKeyword("class"));
    try std.testing.expect(isDefinitionKeyword("async"));

    try std.testing.expect(isImportKeyword("import"));
    try std.testing.expect(isImportKeyword("from"));

    try std.testing.expect(isScopeKeyword("global"));
    try std.testing.expect(isScopeKeyword("nonlocal"));
}

test "python_version" {
    try std.testing.expectEqual(@as(u8, 3), python_version.major);
    try std.testing.expectEqual(@as(u8, 12), python_version.minor);
    try std.testing.expectEqualStrings("3.12.0", python_version.string());
}
