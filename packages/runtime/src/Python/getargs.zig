/// getargs - Argument Parsing
/// Mirrors cpython/Python/getargs.c
///
/// This module implements Python's argument parsing system used by C extension modules.
/// It provides functions like PyArg_ParseTuple, PyArg_ParseTupleAndKeywords, etc.
/// These parse Python objects into C/Zig types based on format strings.

const std = @import("std");

// Re-export submodules
pub const types = @import("getargs/types.zig");
pub const converters = @import("getargs/converters.zig");
pub const parser = @import("getargs/parser.zig");
pub const fast_parser = @import("getargs/fast_parser.zig");
pub const helpers = @import("getargs/helpers.zig");

// Re-export commonly used types from types.zig
pub const FormatCode = types.FormatCode;
pub const ArgValue = types.ArgValue;
pub const ArgError = types.ArgError;
pub const ValidationResult = types.ValidationResult;
pub const validateArgCount = types.validateArgCount;

// Re-export from parser.zig
pub const ArgParser = parser.ArgParser;

// Re-export from fast_parser.zig
pub const FastArgParser = fast_parser.FastArgParser;
pub const FormatParser = fast_parser.FormatParser;

// Re-export from helpers.zig
pub const noKeywords = helpers.noKeywords;
pub const noPositional = helpers.noPositional;
pub const hasOnlyStringKeys = helpers.hasOnlyStringKeys;
pub const unpackTupleOnly = helpers.unpackTupleOnly;
pub const fini = helpers.fini;
pub const init = helpers.init;

// ============================================================================
// Tests
// ============================================================================

test {
    _ = types;
    _ = converters;
    _ = parser;
    _ = fast_parser;
    _ = helpers;
}
