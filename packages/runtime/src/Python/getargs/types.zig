/// types - Argument Parsing Types
/// Format codes, argument values, and error types for argument parsing.

const std = @import("std");

// ============================================================================
// Format Codes
// ============================================================================

/// Format codes for argument parsing
/// Each code specifies the expected type and how to convert it
pub const FormatCode = enum(u8) {
    // Integer types
    b = 'b', // unsigned byte (0-255)
    B = 'B', // byte sized bitfield (signed/unsigned)
    h = 'h', // signed short
    H = 'H', // unsigned short
    i = 'i', // signed int
    I = 'I', // unsigned int
    l = 'l', // signed long
    k = 'k', // unsigned long
    L = 'L', // signed long long
    K = 'K', // unsigned long long
    n = 'n', // Py_ssize_t

    // Floating point
    f = 'f', // float
    d = 'd', // double
    D = 'D', // complex double

    // Strings and buffers
    c = 'c', // char (from string of length 1)
    C = 'C', // unicode char
    s = 's', // const char* (null-terminated)
    z = 'z', // const char* or NULL (None)
    y = 'y', // bytes-like object
    u = 'u', // unicode buffer (Py_UNICODE*)
    Z = 'Z', // unicode buffer or NULL
    U = 'U', // Unicode object (PyObject*)
    S = 'S', // bytes object (PyObject*)
    Y = 'Y', // bytearray object
    w = 'w', // read-write buffer

    // Objects
    O = 'O', // any object (PyObject*)
    p = 'p', // bool (predicate)

    // Special
    e = 'e', // encoding (es, et)

    // Tuple handling
    open_paren = '(',
    close_paren = ')',

    // Optional and keyword args
    pipe = '|', // following args are optional
    dollar = '$', // following args are keyword-only
    at = '@', // use Py_CLEANUP_SUPPORTED

    // Meta
    colon = ':', // function name follows
    semicolon = ';', // custom error message follows
    ampersand = '&', // converter function
    hash = '#', // length for buffer/string
    star = '*', // buffer with length (s*, y*, w*, z*)
    bang = '!', // type check only (O!)

    _,
};

// ============================================================================
// Argument Values
// ============================================================================

/// Parsed argument value
pub const ArgValue = union(enum) {
    // Integer types
    byte: u8,
    short: i16,
    ushort: u16,
    int: i32,
    uint: u32,
    long: i64,
    ulong: u64,
    longlong: i64,
    ulonglong: u64,
    ssize: isize,

    // Floating point
    float: f32,
    double: f64,
    complex: struct { real: f64, imag: f64 },

    // Strings
    char: u8,
    unicode_char: u21,
    string: []const u8,
    string_null: ?[]const u8,
    bytes: []const u8,
    unicode: []const u8,

    // Objects
    object: *anyopaque,
    object_null: ?*anyopaque,
    bool: bool,

    // Buffer
    buffer: struct {
        ptr: [*]const u8,
        len: usize,
    },
    buffer_rw: struct {
        ptr: [*]u8,
        len: usize,
    },

    // Tuple of values
    tuple: []ArgValue,
};

// ============================================================================
// Error Types
// ============================================================================

/// Error type for argument parsing
pub const ArgError = error{
    TypeError,
    ValueError,
    OverflowError,
    UnicodeDecodeError,
    BufferError,
    InvalidFormat,
    MissingArgument,
    TooManyArguments,
    MissingKeyword,
    UnexpectedKeyword,
    OutOfMemory,
};

// ============================================================================
// Validation
// ============================================================================

/// Argument validation result
pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8,
    error_arg: ?usize,
};

/// Validate argument count
pub fn validateArgCount(
    min_args: usize,
    max_args: usize,
    got_args: usize,
    function_name: ?[]const u8,
) ValidationResult {
    if (got_args < min_args) {
        return .{
            .valid = false,
            .error_message = "too few arguments",
            .error_arg = null,
        };
    }
    if (got_args > max_args) {
        return .{
            .valid = false,
            .error_message = "too many arguments",
            .error_arg = null,
        };
    }
    _ = function_name;
    return .{ .valid = true, .error_message = null, .error_arg = null };
}

// ============================================================================
// Tests
// ============================================================================

test "format code enum" {
    const code: FormatCode = @enumFromInt('i');
    try std.testing.expectEqual(FormatCode.i, code);
}

test "validate arg count" {
    const result1 = validateArgCount(2, 4, 3, "test");
    try std.testing.expect(result1.valid);

    const result2 = validateArgCount(2, 4, 1, "test");
    try std.testing.expect(!result2.valid);

    const result3 = validateArgCount(2, 4, 5, "test");
    try std.testing.expect(!result3.valid);
}
