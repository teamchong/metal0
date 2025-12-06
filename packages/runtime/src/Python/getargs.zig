/// getargs - Argument Parsing
/// Mirrors cpython/Python/getargs.c
///
/// This module implements Python's argument parsing system used by C extension modules.
/// It provides functions like PyArg_ParseTuple, PyArg_ParseTupleAndKeywords, etc.
/// These parse Python objects into C/Zig types based on format strings.

const std = @import("std");

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

/// Argument parser state
pub const ArgParser = struct {
    format: []const u8,
    pos: usize,
    args: []const *anyopaque,
    arg_pos: usize,
    kwargs: ?*anyopaque,
    keywords: ?[]const []const u8,
    function_name: ?[]const u8,
    custom_message: ?[]const u8,
    optional_start: usize,
    keyword_only_start: usize,
    min_args: usize,
    max_args: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        format: []const u8,
        args: []const *anyopaque,
        kwargs: ?*anyopaque,
        keywords: ?[]const []const u8,
    ) Self {
        var parser = Self{
            .format = format,
            .pos = 0,
            .args = args,
            .arg_pos = 0,
            .kwargs = kwargs,
            .keywords = keywords,
            .function_name = null,
            .custom_message = null,
            .optional_start = std.math.maxInt(usize),
            .keyword_only_start = std.math.maxInt(usize),
            .min_args = 0,
            .max_args = 0,
            .allocator = allocator,
        };

        // Pre-scan format to find metadata
        parser.scanFormat();
        return parser;
    }

    fn scanFormat(self: *Self) void {
        var i: usize = 0;
        var arg_count: usize = 0;
        var in_tuple: usize = 0;

        while (i < self.format.len) : (i += 1) {
            const c = self.format[i];
            switch (c) {
                '(' => in_tuple += 1,
                ')' => in_tuple -= 1,
                '|' => {
                    if (in_tuple == 0) {
                        self.optional_start = arg_count;
                    }
                },
                '$' => {
                    if (in_tuple == 0) {
                        self.keyword_only_start = arg_count;
                    }
                },
                ':' => {
                    // Function name follows
                    self.function_name = self.format[i + 1 ..];
                    break;
                },
                ';' => {
                    // Custom message follows
                    self.custom_message = self.format[i + 1 ..];
                    break;
                },
                // Skip modifiers
                '*', '#', '&', '!' => {},
                // Skip secondary format codes
                'e' => {
                    if (i + 1 < self.format.len and (self.format[i + 1] == 's' or self.format[i + 1] == 't')) {
                        i += 1;
                    }
                },
                else => {
                    // Count actual arguments
                    if (c >= 'A' and c <= 'z' and in_tuple == 0) {
                        arg_count += 1;
                    }
                },
            }
        }

        self.max_args = arg_count;
        if (self.optional_start == std.math.maxInt(usize)) {
            self.min_args = arg_count;
        } else {
            self.min_args = self.optional_start;
        }
    }

    /// Get the current format character
    fn peek(self: *const Self) ?u8 {
        if (self.pos < self.format.len) {
            return self.format[self.pos];
        }
        return null;
    }

    /// Advance to next format character
    fn advance(self: *Self) void {
        if (self.pos < self.format.len) {
            self.pos += 1;
        }
    }

    /// Get the next argument
    fn nextArg(self: *Self) ?*anyopaque {
        if (self.arg_pos < self.args.len) {
            const arg = self.args[self.arg_pos];
            self.arg_pos += 1;
            return arg;
        }
        return null;
    }

    /// Parse a single format code and convert argument
    pub fn parseOne(self: *Self) ArgError!?ArgValue {
        const c = self.peek() orelse return null;
        self.advance();

        return switch (c) {
            // Integer types
            'b' => self.parseByte(),
            'B' => self.parseByteBitfield(),
            'h' => self.parseShort(),
            'H' => self.parseUShort(),
            'i' => self.parseInt(),
            'I' => self.parseUInt(),
            'l' => self.parseLong(),
            'k' => self.parseULong(),
            'L' => self.parseLongLong(),
            'K' => self.parseULongLong(),
            'n' => self.parseSsize(),

            // Floating point
            'f' => self.parseFloat(),
            'd' => self.parseDouble(),
            'D' => self.parseComplex(),

            // Strings
            'c' => self.parseChar(),
            'C' => self.parseUnicodeChar(),
            's' => self.parseString(),
            'z' => self.parseStringOrNone(),
            'y' => self.parseBytes(),
            'u', 'Z' => self.parseUnicode(),
            'U' => self.parseUnicodeObject(),
            'S' => self.parseBytesObject(),
            'Y' => self.parseByteArray(),
            'w' => self.parseWriteBuffer(),

            // Objects
            'O' => self.parseObject(),
            'p' => self.parsePredicate(),

            // Encoding
            'e' => self.parseEncoding(),

            // Tuple
            '(' => self.parseTuple(),
            ')' => return null, // End of tuple

            // Modifiers (skip)
            '|', '$', '@' => self.parseOne(),

            // Meta (end of format)
            ':', ';' => return null,

            else => ArgError.InvalidFormat,
        };
    }

    // Integer parsing functions
    fn parseByte(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        if (value < 0 or value > 255) return ArgError.OverflowError;
        return ArgValue{ .byte = @intCast(value) };
    }

    fn parseByteBitfield(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .byte = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseShort(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) {
            return ArgError.OverflowError;
        }
        return ArgValue{ .short = @intCast(value) };
    }

    fn parseUShort(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ushort = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseInt(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) {
            return ArgError.OverflowError;
        }
        return ArgValue{ .int = @intCast(value) };
    }

    fn parseUInt(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .uint = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .long = value };
    }

    fn parseULong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToULong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ulong = value };
    }

    fn parseLongLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .longlong = value };
    }

    fn parseULongLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToULong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ulonglong = value };
    }

    fn parseSsize(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ssize = @intCast(value) };
    }

    // Float parsing
    fn parseFloat(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToDouble(arg) catch return ArgError.TypeError;
        return ArgValue{ .float = @floatCast(value) };
    }

    fn parseDouble(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToDouble(arg) catch return ArgError.TypeError;
        return ArgValue{ .double = value };
    }

    fn parseComplex(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToComplex(arg) catch return ArgError.TypeError;
        return ArgValue{ .complex = value };
    }

    // String parsing
    fn parseChar(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = convertToString(arg) catch return ArgError.TypeError;
        if (str.len != 1) return ArgError.TypeError;
        return ArgValue{ .char = str[0] };
    }

    fn parseUnicodeChar(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = convertToString(arg) catch return ArgError.TypeError;
        // Decode single UTF-8 codepoint
        if (str.len == 0) return ArgError.TypeError;
        const cp = std.unicode.utf8Decode(str[0..@min(4, str.len)]) catch return ArgError.UnicodeDecodeError;
        return ArgValue{ .unicode_char = cp };
    }

    fn parseString(self: *Self) ArgError!ArgValue {
        // Check for modifier
        const has_len = self.peek() == '#';
        if (has_len) self.advance();
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = convertToString(arg) catch return ArgError.TypeError;

        if (has_buffer) {
            return ArgValue{ .buffer = .{
                .ptr = str.ptr,
                .len = str.len,
            } };
        }
        return ArgValue{ .string = str };
    }

    fn parseStringOrNone(self: *Self) ArgError!ArgValue {
        const has_len = self.peek() == '#';
        if (has_len) self.advance();
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (isNone(arg)) {
            return ArgValue{ .string_null = null };
        }
        const str = convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .string_null = str };
    }

    fn parseBytes(self: *Self) ArgError!ArgValue {
        const has_len = self.peek() == '#';
        if (has_len) self.advance();
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const bytes = convertToBytes(arg) catch return ArgError.TypeError;

        if (has_buffer) {
            return ArgValue{ .buffer = .{
                .ptr = bytes.ptr,
                .len = bytes.len,
            } };
        }
        return ArgValue{ .bytes = bytes };
    }

    fn parseUnicode(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .unicode = str };
    }

    fn parseUnicodeObject(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!isUnicode(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseBytesObject(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!isBytesObj(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseByteArray(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!isByteArray(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseWriteBuffer(self: *Self) ArgError!ArgValue {
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const buffer = getWriteBuffer(arg) catch return ArgError.BufferError;
        return ArgValue{ .buffer_rw = buffer };
    }

    // Object parsing
    fn parseObject(self: *Self) ArgError!ArgValue {
        const next = self.peek();

        // O! - type check
        if (next == '!') {
            self.advance();
            // Type object would be next arg, then actual object
            _ = self.nextArg() orelse return ArgError.MissingArgument; // type
            const arg = self.nextArg() orelse return ArgError.MissingArgument;
            return ArgValue{ .object = arg };
        }

        // O& - converter function
        if (next == '&') {
            self.advance();
            // Converter function and its arg would be handled differently in C
            // For Zig, we just get the object
            const arg = self.nextArg() orelse return ArgError.MissingArgument;
            return ArgValue{ .object = arg };
        }

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        return ArgValue{ .object = arg };
    }

    fn parsePredicate(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = convertToBool(arg);
        return ArgValue{ .bool = value };
    }

    fn parseEncoding(self: *Self) ArgError!ArgValue {
        // es or et format
        const next = self.peek() orelse return ArgError.InvalidFormat;
        if (next != 's' and next != 't') return ArgError.InvalidFormat;
        self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .string = str };
    }

    fn parseTuple(self: *Self) ArgError!ArgValue {
        var values = std.ArrayList(ArgValue).init(self.allocator);
        errdefer values.deinit();

        while (true) {
            const value = try self.parseOne() orelse break;
            values.append(value) catch return ArgError.OutOfMemory;

            if (self.peek() == ')') {
                self.advance();
                break;
            }
        }

        return ArgValue{ .tuple = values.toOwnedSlice() catch return ArgError.OutOfMemory };
    }

    /// Parse all arguments according to format
    pub fn parseAll(self: *Self) ArgError![]ArgValue {
        var values = std.ArrayList(ArgValue).init(self.allocator);
        errdefer values.deinit();

        while (try self.parseOne()) |value| {
            values.append(value) catch return ArgError.OutOfMemory;
        }

        return values.toOwnedSlice() catch return ArgError.OutOfMemory;
    }
};

// Conversion helper functions (stubs - would interface with actual Python objects)

fn convertToLong(_: *anyopaque) !i64 {
    // Would call PyLong_AsLong
    return 0;
}

fn convertToULong(_: *anyopaque) !u64 {
    // Would call PyLong_AsUnsignedLong
    return 0;
}

fn convertToDouble(_: *anyopaque) !f64 {
    // Would call PyFloat_AsDouble
    return 0.0;
}

fn convertToComplex(_: *anyopaque) !struct { real: f64, imag: f64 } {
    // Would call PyComplex_RealAsDouble/PyComplex_ImagAsDouble
    return .{ .real = 0.0, .imag = 0.0 };
}

fn convertToString(_: *anyopaque) ![]const u8 {
    // Would call PyUnicode_AsUTF8AndSize
    return "";
}

fn convertToBytes(_: *anyopaque) ![]const u8 {
    // Would call PyBytes_AsStringAndSize
    return "";
}

fn convertToBool(_: *anyopaque) bool {
    // Would call PyObject_IsTrue
    return false;
}

fn isNone(_: *anyopaque) bool {
    // Would check if object is Py_None
    return false;
}

fn isUnicode(_: *anyopaque) bool {
    // Would call PyUnicode_Check
    return false;
}

fn isBytesObj(_: *anyopaque) bool {
    // Would call PyBytes_Check
    return false;
}

fn isByteArray(_: *anyopaque) bool {
    // Would call PyByteArray_Check
    return false;
}

fn getWriteBuffer(_: *anyopaque) !struct { ptr: [*]u8, len: usize } {
    // Would call PyObject_GetBuffer with PyBUF_WRITABLE
    return error.BufferError;
}

/// No-keyword argument checker
pub fn noKeywords(function_name: []const u8, kwargs: ?*anyopaque) bool {
    _ = function_name;
    return kwargs == null;
}

/// No-positional argument checker
pub fn noPositional(function_name: []const u8, args: []const *anyopaque) bool {
    _ = function_name;
    return args.len == 0;
}

/// Check if kwargs contains only string keys
pub fn hasOnlyStringKeys(_: ?*anyopaque) bool {
    // Would iterate kwargs and check key types
    return true;
}

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

/// Fast parser using pre-parsed format info
pub const FastArgParser = struct {
    keywords: []const []const u8,
    min_positional: usize,
    max_positional: usize,
    format_units: []const FormatUnit,

    pub const FormatUnit = struct {
        code: u8,
        flags: Flags,

        pub const Flags = packed struct {
            optional: bool = false,
            keyword_only: bool = false,
            has_length: bool = false,
            has_buffer: bool = false,
            has_converter: bool = false,
            has_typecheck: bool = false,
            _padding: u2 = 0,
        };
    };

    const Self = @This();

    pub fn parse(
        self: *const Self,
        args: []const *anyopaque,
        kwargs: ?*anyopaque,
        outputs: []*anyopaque,
    ) ArgError!void {
        _ = self;
        _ = args;
        _ = kwargs;
        _ = outputs;
        // Would implement fast path parsing
    }
};

/// Unpack positional args only (for methods with no kwargs)
pub fn unpackTupleOnly(
    args: []const *anyopaque,
    min: usize,
    max: usize,
    function_name: []const u8,
) ArgError!void {
    if (args.len < min) {
        _ = function_name;
        return ArgError.MissingArgument;
    }
    if (args.len > max) {
        return ArgError.TooManyArguments;
    }
}

/// Format parser state for building FastArgParser
pub const FormatParser = struct {
    format: []const u8,
    pos: usize,
    units: std.ArrayList(FastArgParser.FormatUnit),
    keywords: std.ArrayList([]const u8),
    min_pos: usize,
    max_pos: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, format: []const u8) Self {
        return .{
            .format = format,
            .pos = 0,
            .units = std.ArrayList(FastArgParser.FormatUnit).init(allocator),
            .keywords = std.ArrayList([]const u8).init(allocator),
            .min_pos = 0,
            .max_pos = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.units.deinit();
        self.keywords.deinit();
    }

    pub fn parse(self: *Self) !FastArgParser {
        var optional = false;
        var keyword_only = false;

        while (self.pos < self.format.len) {
            const c = self.format[self.pos];
            self.pos += 1;

            switch (c) {
                '|' => optional = true,
                '$' => keyword_only = true,
                ':', ';' => break,
                '(' => {
                    // Handle tuple - for now skip to matching ')'
                    var depth: usize = 1;
                    while (depth > 0 and self.pos < self.format.len) {
                        if (self.format[self.pos] == '(') depth += 1;
                        if (self.format[self.pos] == ')') depth -= 1;
                        self.pos += 1;
                    }
                },
                else => {
                    if (c >= 'A' and c <= 'z') {
                        var flags = FastArgParser.FormatUnit.Flags{};
                        flags.optional = optional;
                        flags.keyword_only = keyword_only;

                        // Check for modifiers
                        while (self.pos < self.format.len) {
                            const mod = self.format[self.pos];
                            switch (mod) {
                                '#' => {
                                    flags.has_length = true;
                                    self.pos += 1;
                                },
                                '*' => {
                                    flags.has_buffer = true;
                                    self.pos += 1;
                                },
                                '&' => {
                                    flags.has_converter = true;
                                    self.pos += 1;
                                },
                                '!' => {
                                    flags.has_typecheck = true;
                                    self.pos += 1;
                                },
                                else => break,
                            }
                        }

                        try self.units.append(.{ .code = c, .flags = flags });
                        self.max_pos += 1;
                        if (!optional and !keyword_only) {
                            self.min_pos += 1;
                        }
                    }
                },
            }
        }

        return FastArgParser{
            .keywords = try self.keywords.toOwnedSlice(),
            .min_positional = self.min_pos,
            .max_positional = self.max_pos,
            .format_units = try self.units.toOwnedSlice(),
        };
    }
};

/// Finalization - cleanup any cached parser state
pub fn fini() void {
    // Cleanup any global parser caches
}

/// Initialize the argument parsing module
pub fn init() void {
    // Initialize any global state
}

// Tests
test "format code enum" {
    const code: FormatCode = @enumFromInt('i');
    try std.testing.expectEqual(FormatCode.i, code);
}

test "arg parser init" {
    const allocator = std.testing.allocator;
    const args = [_]*anyopaque{};
    const parser = ArgParser.init(allocator, "ii|s:test_func", &args, null, null);
    try std.testing.expectEqual(@as(usize, 2), parser.min_args);
    try std.testing.expectEqual(@as(usize, 3), parser.max_args);
    try std.testing.expectEqualStrings("test_func", parser.function_name.?);
}

test "validate arg count" {
    const result1 = validateArgCount(2, 4, 3, "test");
    try std.testing.expect(result1.valid);

    const result2 = validateArgCount(2, 4, 1, "test");
    try std.testing.expect(!result2.valid);

    const result3 = validateArgCount(2, 4, 5, "test");
    try std.testing.expect(!result3.valid);
}

test "format parser" {
    const allocator = std.testing.allocator;
    var parser = FormatParser.init(allocator, "iis|O:func");
    defer parser.deinit();

    const fast = try parser.parse();
    defer allocator.free(fast.format_units);
    defer allocator.free(fast.keywords);

    try std.testing.expectEqual(@as(usize, 3), fast.min_positional);
    try std.testing.expectEqual(@as(usize, 4), fast.max_positional);
    try std.testing.expectEqual(@as(usize, 4), fast.format_units.len);
}
