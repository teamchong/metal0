//! CPython source: Lib/optparse.py
//!
//! A powerful, extensible, and easy-to-use option parser.
//! Note: In Python 3.2+, argparse is preferred over optparse.
//!
//! Mirrors: CPython Lib/optparse.py

// Re-export types
pub const OptionAction = @import("optparse/types.zig").OptionAction;
pub const OptionType = @import("optparse/types.zig").OptionType;
pub const ErrorBehavior = @import("optparse/types.zig").ErrorBehavior;
pub const OptionError = @import("optparse/types.zig").OptionError;
pub const OptionValueError = @import("optparse/types.zig").OptionValueError;

// Re-export main types
pub const Values = @import("optparse/values.zig").Values;
pub const Option = @import("optparse/option.zig").Option;
pub const OptionGroup = @import("optparse/option_group.zig").OptionGroup;
pub const OptionParser = @import("optparse/parser.zig").OptionParser;

// Re-export convenience functions
pub const createParser = @import("optparse/parser.zig").createParser;
