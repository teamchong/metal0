//! Core types for argparse module
//!
//! Defines Action, Nargs, ArgValue, and ArgumentOptions types.

const std = @import("std");

/// Argument action types
pub const Action = enum {
    store, // Store the value (default)
    store_const, // Store a constant value
    store_true, // Store true
    store_false, // Store false
    append, // Append to a list
    append_const, // Append a constant to a list
    count, // Count occurrences
    help, // Print help and exit
    version, // Print version and exit
};

/// Argument nargs specification
pub const Nargs = union(enum) {
    exact: u32, // Exact number of arguments
    optional, // ? - zero or one
    zero_or_more, // * - zero or more
    one_or_more, // + - one or more
    remainder, // Remaining arguments
};

/// Parsed argument value
pub const ArgValue = union(enum) {
    string: []const u8,
    strings: []const []const u8,
    boolean: bool,
    integer: i64,
    float: f64,
    count: u32,
    none,
};

/// Options for adding an argument
pub const ArgumentOptions = struct {
    action: Action = .store,
    nargs: ?Nargs = null,
    const_value: ?[]const u8 = null,
    default: ?[]const u8 = null,
    type_name: []const u8 = "string",
    choices: ?[]const []const u8 = null,
    required: bool = false,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    dest: ?[]const u8 = null,
};

/// Type conversion error
pub const ArgumentTypeError = error{
    InvalidValue,
    OutOfRange,
};
