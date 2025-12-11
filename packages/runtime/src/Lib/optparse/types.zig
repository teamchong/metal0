//! CPython source: Lib/optparse.py
//!
//! Type definitions for option parsing.
//! Mirrors: CPython Lib/optparse.py

/// Action to take when option is encountered
pub const OptionAction = enum {
    store, // Store value in dest
    store_const, // Store a constant value
    store_true, // Store True
    store_false, // Store False
    append, // Append to a list
    append_const, // Append a constant to a list
    count, // Increment a counter
    callback, // Call a callback function
    help, // Print help and exit
    version, // Print version and exit
};

/// Type of option argument
pub const OptionType = enum {
    string,
    int,
    long,
    float,
    complex,
    choice,
};

/// Error handling behavior
pub const ErrorBehavior = enum {
    exit,
    raise,
};

// ============================================================================
// Errors
// ============================================================================

pub const OptionError = error{
    UnknownOption,
    MissingArgument,
    InvalidChoice,
    InvalidType,
    AmbiguousOption,
    HelpRequested,
    VersionRequested,
};

/// Exception for bad option values
pub const OptionValueError = error{
    BadValue,
};
