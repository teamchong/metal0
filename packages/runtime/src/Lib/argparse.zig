//! CPython source: Lib/argparse.py
//!
//! Parser for command-line options, arguments and sub-commands.
//!
//! Mirrors: CPython Lib/argparse.py
//!
//! This module provides a modular argparse implementation split into focused submodules.

// Re-export core types
pub const types = @import("argparse/types.zig");
pub const Action = types.Action;
pub const Nargs = types.Nargs;
pub const ArgValue = types.ArgValue;
pub const ArgumentOptions = types.ArgumentOptions;
pub const ArgumentTypeError = types.ArgumentTypeError;

// Re-export Argument
pub const argument = @import("argparse/argument.zig");
pub const Argument = argument.Argument;

// Re-export ParseResult
pub const parse_result = @import("argparse/parse_result.zig");
pub const ParseResult = parse_result.ParseResult;

// Re-export SubparserGroup
pub const subparsers = @import("argparse/subparsers.zig");
pub const SubparserGroup = subparsers.SubparserGroup;

// Re-export utilities
pub const utils = @import("argparse/utils.zig");
pub const getSystemArgs = utils.getSystemArgs;
pub const freeSystemArgs = utils.freeSystemArgs;
pub const intType = utils.intType;
pub const floatType = utils.floatType;
pub const FileType = utils.FileType;

// Re-export parser (main entry point)
pub const parser = @import("argparse/parser.zig");
pub const ArgumentParser = parser.ArgumentParser;

// Re-export formatter
pub const formatter = @import("argparse/formatter.zig");
