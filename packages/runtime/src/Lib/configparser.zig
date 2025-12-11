//! CPython source: Lib/configparser.py
//!
//! Provides ConfigParser for reading and writing INI-style configuration files.
//!
//! Mirrors: CPython Lib/configparser.py

// Re-export types
pub const Options = @import("configparser/types.zig").Options;
pub const Error = @import("configparser/types.zig").Error;
pub const DEFAULTSECT = @import("configparser/types.zig").DEFAULTSECT;
pub const MAX_INTERPOLATION_DEPTH = @import("configparser/types.zig").MAX_INTERPOLATION_DEPTH;

// Re-export interpolation classes
pub const BasicInterpolation = @import("configparser/interpolation.zig").BasicInterpolation;
pub const ExtendedInterpolation = @import("configparser/interpolation.zig").ExtendedInterpolation;

// Re-export converters
pub const Converters = @import("configparser/converters.zig").Converters;

// Re-export parser
pub const ConfigParser = @import("configparser/parser.zig").ConfigParser;
pub const RawConfigParser = @import("configparser/parser.zig").RawConfigParser;
pub const SafeConfigParser = @import("configparser/parser.zig").SafeConfigParser;

// Re-export tests
test {
    _ = @import("configparser/tests.zig");
}
