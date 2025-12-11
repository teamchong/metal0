/// parser - Argument Parser
/// Main argument parser implementation.

const std = @import("std");
const types = @import("types.zig");
const converters = @import("converters.zig");

pub const FormatCode = types.FormatCode;
pub const ArgValue = types.ArgValue;
pub const ArgError = types.ArgError;

// ============================================================================
// Argument Parser
// ============================================================================

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
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        if (value < 0 or value > 255) return ArgError.OverflowError;
        return ArgValue{ .byte = @intCast(value) };
    }

    fn parseByteBitfield(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .byte = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseShort(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) {
            return ArgError.OverflowError;
        }
        return ArgValue{ .short = @intCast(value) };
    }

    fn parseUShort(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ushort = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseInt(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) {
            return ArgError.OverflowError;
        }
        return ArgValue{ .int = @intCast(value) };
    }

    fn parseUInt(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .uint = @truncate(@as(u64, @bitCast(value))) };
    }

    fn parseLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .long = value };
    }

    fn parseULong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToULong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ulong = value };
    }

    fn parseLongLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .longlong = value };
    }

    fn parseULongLong(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToULong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ulonglong = value };
    }

    fn parseSsize(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToLong(arg) catch return ArgError.TypeError;
        return ArgValue{ .ssize = @intCast(value) };
    }

    // Float parsing
    fn parseFloat(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToDouble(arg) catch return ArgError.TypeError;
        return ArgValue{ .float = @floatCast(value) };
    }

    fn parseDouble(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToDouble(arg) catch return ArgError.TypeError;
        return ArgValue{ .double = value };
    }

    fn parseComplex(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const value = converters.convertToComplex(arg) catch return ArgError.TypeError;
        return ArgValue{ .complex = value };
    }

    // String parsing
    fn parseChar(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = converters.convertToString(arg) catch return ArgError.TypeError;
        if (str.len != 1) return ArgError.TypeError;
        return ArgValue{ .char = str[0] };
    }

    fn parseUnicodeChar(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = converters.convertToString(arg) catch return ArgError.TypeError;
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
        const str = converters.convertToString(arg) catch return ArgError.TypeError;

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
        if (converters.isNone(arg)) {
            return ArgValue{ .string_null = null };
        }
        const str = converters.convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .string_null = str };
    }

    fn parseBytes(self: *Self) ArgError!ArgValue {
        const has_len = self.peek() == '#';
        if (has_len) self.advance();
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const bytes = converters.convertToBytes(arg) catch return ArgError.TypeError;

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
        const str = converters.convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .unicode = str };
    }

    fn parseUnicodeObject(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!converters.isUnicode(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseBytesObject(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!converters.isBytesObj(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseByteArray(self: *Self) ArgError!ArgValue {
        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        if (!converters.isByteArray(arg)) return ArgError.TypeError;
        return ArgValue{ .object = arg };
    }

    fn parseWriteBuffer(self: *Self) ArgError!ArgValue {
        const has_buffer = self.peek() == '*';
        if (has_buffer) self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const buffer = converters.getWriteBuffer(arg) catch return ArgError.BufferError;
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
        const value = converters.convertToBool(arg);
        return ArgValue{ .bool = value };
    }

    fn parseEncoding(self: *Self) ArgError!ArgValue {
        // es or et format
        const next = self.peek() orelse return ArgError.InvalidFormat;
        if (next != 's' and next != 't') return ArgError.InvalidFormat;
        self.advance();

        const arg = self.nextArg() orelse return ArgError.MissingArgument;
        const str = converters.convertToString(arg) catch return ArgError.TypeError;
        return ArgValue{ .string = str };
    }

    fn parseTuple(self: *Self) ArgError!ArgValue {
        var values = std.ArrayList(ArgValue).init(self.allocator);
        errdefer values.deinit();

        while (true) {
            const value = try self.parseOne() orelse break;
            values.append(self.allocator, value) catch return ArgError.OutOfMemory;

            if (self.peek() == ')') {
                self.advance();
                break;
            }
        }

        return ArgValue{ .tuple = values.toOwnedSlice(self.allocator) catch return ArgError.OutOfMemory };
    }

    /// Parse all arguments according to format
    pub fn parseAll(self: *Self) ArgError![]ArgValue {
        var values = std.ArrayList(ArgValue).init(self.allocator);
        errdefer values.deinit();

        while (try self.parseOne()) |value| {
            values.append(self.allocator, value) catch return ArgError.OutOfMemory;
        }

        return values.toOwnedSlice(self.allocator) catch return ArgError.OutOfMemory;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "arg parser init" {
    const allocator = std.testing.allocator;
    const args = [_]*anyopaque{};
    const parser = ArgParser.init(allocator, "ii|s:test_func", &args, null, null);
    try std.testing.expectEqual(@as(usize, 2), parser.min_args);
    try std.testing.expectEqual(@as(usize, 3), parser.max_args);
    try std.testing.expectEqualStrings("test_func", parser.function_name.?);
}
