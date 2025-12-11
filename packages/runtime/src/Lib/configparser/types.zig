//! CPython source: Lib/configparser.py
//!
//! Type definitions and constants for ConfigParser.

const std = @import("std");

/// ConfigParser options
pub const Options = struct {
    delimiters: []const u8 = "=:",
    comment_prefixes: []const u8 = "#;",
    inline_comment_prefixes: ?[]const u8 = null,
    strict: bool = true,
    empty_lines_in_values: bool = true,
    default_section: []const u8 = "DEFAULT",
    allow_no_value: bool = false,
};

/// ConfigParser errors
pub const Error = error{
    NoSection,
    DuplicateSection,
    DuplicateOption,
    NoOption,
    InterpolationError,
    InterpolationDepthError,
    InterpolationMissingOptionError,
    InterpolationSyntaxError,
    InvalidBoolean,
    ParsingError,
    MissingSectionHeader,
};

/// Constants
pub const DEFAULTSECT = "DEFAULT";
pub const MAX_INTERPOLATION_DEPTH = 10;
