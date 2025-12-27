/// Python __future__ module - future statement definitions
///
/// Provides compile-time flags for enabling future language features.
/// These constants are used by compile() builtin to modify parser behavior.
///
/// See: https://docs.python.org/3/library/__future__.html

/// Code flags for compile() builtin
pub const CO_NESTED: i64 = 16;
pub const CO_GENERATOR_ALLOWED: i64 = 0;
pub const CO_FUTURE_DIVISION: i64 = 131072;
pub const CO_FUTURE_ABSOLUTE_IMPORT: i64 = 262144;
pub const CO_FUTURE_WITH_STATEMENT: i64 = 524288;
pub const CO_FUTURE_PRINT_FUNCTION: i64 = 1048576;
pub const CO_FUTURE_UNICODE_LITERALS: i64 = 2097152;
pub const CO_FUTURE_BARRY_AS_BDFL: i64 = 4194304;
pub const CO_FUTURE_GENERATOR_STOP: i64 = 8388608;
pub const CO_FUTURE_ANNOTATIONS: i64 = 16777216;

/// Feature names list (all features)
pub const all_feature_names = [_][]const u8{
    "nested_scopes",
    "generators",
    "division",
    "absolute_import",
    "with_statement",
    "print_function",
    "unicode_literals",
    "barry_as_FLUFL",
    "generator_stop",
    "annotations",
};
