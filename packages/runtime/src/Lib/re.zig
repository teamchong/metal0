//! CPython source: Lib/re.py
//!
//! Provides regular expression matching operations.
//!
//! Mirrors: CPython Lib/re.py

const std = @import("std");

// Re-export all submodules
pub const types = @import("re/types.zig");
pub const pattern = @import("re/pattern.zig");
pub const match_ops = @import("re/match_ops.zig");
pub const operations = @import("re/operations.zig");
pub const utils = @import("re/utils.zig");

// Type re-exports from types module
pub const Regex = types.Regex;
pub const Match = types.Match;
pub const Span = types.Span;
pub const PyMatch = types.PyMatch;
pub const CompiledPattern = types.CompiledPattern;

// Flag re-exports from pattern module
pub const IGNORECASE = pattern.IGNORECASE;
pub const MULTILINE = pattern.MULTILINE;
pub const DOTALL = pattern.DOTALL;
pub const VERBOSE = pattern.VERBOSE;

// Function re-exports from pattern module
pub const compile = pattern.compile;
pub const compileWithFlags = pattern.compileWithFlags;

// Function re-exports from match_ops module
pub const search = match_ops.search;
pub const match = match_ops.match;
pub const fullmatch = match_ops.fullmatch;

// Function re-exports from operations module
pub const sub = operations.sub;
pub const subn = operations.subn;
pub const findall = operations.findall;
pub const finditer = operations.finditer;
pub const split = operations.split;

// Function re-exports from utils module
pub const escape = utils.escape;
pub const purge = utils.purge;
