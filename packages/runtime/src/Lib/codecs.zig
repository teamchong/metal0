//! CPython source: Lib/codecs.py
//!
//! Provides the foundation for encoding/decoding operations.
//!
//! Mirrors: CPython Lib/codecs.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Codec Info
// ============================================================================

/// Information about a codec
pub const CodecInfo = struct {
    name: []const u8,
    encode: EncodeFn,
    decode: DecodeFn,
    incrementalencoder: ?*const fn (errors: []const u8) IncrementalEncoder = null,
    incrementaldecoder: ?*const fn (errors: []const u8) IncrementalDecoder = null,
    streamreader: ?type = null,
    streamwriter: ?type = null,
};

pub const EncodeFn = *const fn (input: []const u8, errors: []const u8) EncodeResult;
pub const DecodeFn = *const fn (input: []const u8, errors: []const u8) DecodeResult;

pub const EncodeResult = struct {
    output: []const u8,
    length: usize,
};

pub const DecodeResult = struct {
    output: []const u8,
    length: usize,
};

// ============================================================================
// Codec Registry
// ============================================================================

var codec_registry: ?hashmap_helper.StringHashMap(CodecInfo) = null;
var search_functions: std.ArrayList(*const fn (name: []const u8) ?CodecInfo) = .{};
var registry_initialized = false;

fn initRegistry() void {
    if (registry_initialized) return;
    codec_registry = hashmap_helper.StringHashMap(CodecInfo).init(allocator_helper.fast_allocator);
    registry_initialized = true;
}

/// Register a codec search function
pub fn register(search_function: *const fn (name: []const u8) ?CodecInfo) !void {
    initRegistry();
    try search_functions.append(allocator_helper.fast_allocator, search_function);
}

/// Look up a codec by name
pub fn lookup(name: []const u8) ?CodecInfo {
    initRegistry();

    // Normalize name
    var normalized: [256]u8 = undefined;
    var len: usize = 0;
    for (name) |c| {
        if (len >= normalized.len) break;
        if (c == ' ' or c == '-' or c == '_') {
            normalized[len] = '_';
        } else {
            normalized[len] = std.ascii.toLower(c);
        }
        len += 1;
    }
    const norm_name = normalized[0..len];

    // Check registry first
    if (codec_registry) |*reg| {
        if (reg.get(norm_name)) |info| {
            return info;
        }
    }

    // Try search functions
    for (search_functions.items) |search_fn| {
        if (search_fn(norm_name)) |info| {
            return info;
        }
    }

    return null;
}

/// Get encoder for a codec
pub fn getencoder(encoding: []const u8) ?EncodeFn {
    if (lookup(encoding)) |info| {
        return info.encode;
    }
    return null;
}

/// Get decoder for a codec
pub fn getdecoder(encoding: []const u8) ?DecodeFn {
    if (lookup(encoding)) |info| {
        return info.decode;
    }
    return null;
}

/// Get incremental encoder
pub fn getincrementalencoder(encoding: []const u8) ?*const fn (errors: []const u8) IncrementalEncoder {
    if (lookup(encoding)) |info| {
        return info.incrementalencoder;
    }
    return null;
}

/// Get incremental decoder
pub fn getincrementaldecoder(encoding: []const u8) ?*const fn (errors: []const u8) IncrementalDecoder {
    if (lookup(encoding)) |info| {
        return info.incrementaldecoder;
    }
    return null;
}

// ============================================================================
// Encode/Decode Functions
// ============================================================================

/// Encode a string using the named codec
pub fn encode(allocator: std.mem.Allocator, input: []const u8, encoding: []const u8, errors: []const u8) ![]u8 {
    _ = allocator;
    if (lookup(encoding)) |info| {
        const result = info.encode(input, errors);
        return @constCast(result.output);
    }
    return error.UnknownEncoding;
}

/// Decode bytes using the named codec
pub fn decode(allocator: std.mem.Allocator, input: []const u8, encoding: []const u8, errors: []const u8) ![]u8 {
    _ = allocator;
    if (lookup(encoding)) |info| {
        const result = info.decode(input, errors);
        return @constCast(result.output);
    }
    return error.UnknownEncoding;
}

// ============================================================================
// Incremental Encoder/Decoder
// ============================================================================

/// Base incremental encoder
pub const IncrementalEncoder = struct {
    const Self = @This();

    errors: []const u8,
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, errors: []const u8) Self {
        return .{
            .errors = errors,
            .buffer = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn encodeChunk(self: *Self, input: []const u8, final: bool) ![]u8 {
        _ = final;
        // Default: just copy
        try self.buffer.appendSlice(self.allocator, input);
        const result = try self.buffer.toOwnedSlice(self.allocator);
        return result;
    }

    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn getstate(self: *Self) struct { buffer: []u8, state: i32 } {
        return .{ .buffer = self.buffer.items, .state = 0 };
    }

    pub fn setstate(self: *Self, state: struct { buffer: []u8, state: i32 }) void {
        self.buffer.clearRetainingCapacity();
        self.buffer.appendSlice(self.allocator, state.buffer) catch unreachable;
    }
};

/// Base incremental decoder
pub const IncrementalDecoder = struct {
    const Self = @This();

    errors: []const u8,
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, errors: []const u8) Self {
        return .{
            .errors = errors,
            .buffer = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn decodeChunk(self: *Self, input: []const u8, final: bool) ![]u8 {
        _ = final;
        try self.buffer.appendSlice(self.allocator, input);
        const result = try self.buffer.toOwnedSlice(self.allocator);
        return result;
    }

    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn getstate(self: *Self) struct { buffer: []u8, state: i32 } {
        return .{ .buffer = self.buffer.items, .state = 0 };
    }

    pub fn setstate(self: *Self, state: struct { buffer: []u8, state: i32 }) void {
        self.buffer.clearRetainingCapacity();
        self.buffer.appendSlice(self.allocator, state.buffer) catch unreachable;
    }
};

// ============================================================================
// Stream Reader/Writer
// ============================================================================

/// Stream reader wrapper
pub fn StreamReader(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        reader: ReaderType,
        encoding: []const u8,
        errors: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, reader: ReaderType, encoding: []const u8, errors: []const u8) Self {
            return .{
                .reader = reader,
                .encoding = encoding,
                .errors = errors,
                .allocator = allocator,
            };
        }

        pub fn read(self: *Self, size: ?usize) ![]u8 {
            const s = size orelse 4096;
            var buf = try self.allocator.alloc(u8, s);
            const n = try self.reader.read(buf);
            if (n < s) {
                buf = try self.allocator.realloc(buf, n);
            }
            return decode(self.allocator, buf[0..n], self.encoding, self.errors);
        }

        pub fn readline(self: *Self) ![]u8 {
            var line: std.ArrayList(u8) = .{};
            while (true) {
                const byte = self.reader.readByte() catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };
                try line.append(self.allocator, byte);
                if (byte == '\n') break;
            }
            return decode(self.allocator, line.items, self.encoding, self.errors);
        }
    };
}

/// Stream writer wrapper
pub fn StreamWriter(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        writer: WriterType,
        encoding: []const u8,
        errors: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, writer: WriterType, encoding: []const u8, errors: []const u8) Self {
            return .{
                .writer = writer,
                .encoding = encoding,
                .errors = errors,
                .allocator = allocator,
            };
        }

        pub fn write(self: *Self, data: []const u8) !usize {
            const encoded = try encode(self.allocator, data, self.encoding, self.errors);
            defer self.allocator.free(encoded);
            return self.writer.write(encoded);
        }

        pub fn writelines(self: *Self, lines: []const []const u8) !void {
            for (lines) |line| {
                _ = try self.write(line);
            }
        }
    };
}

// ============================================================================
// Error Handlers
// ============================================================================

/// Error handling modes
pub const ErrorMode = enum {
    strict, // Raise exception on error
    ignore, // Ignore errors
    replace, // Replace with replacement character
    xmlcharrefreplace, // Replace with XML character reference
    backslashreplace, // Replace with backslash escape
    namereplace, // Replace with \N{...} escape
    surrogatepass, // Allow surrogates
    surrogateescape, // Escape surrogates
};

/// Error handler function type
pub const ErrorHandlerFn = *const fn ([]const u8, usize) struct { replacement: []const u8, position: usize };

/// Registry of custom error handlers
var error_handlers: std.StringHashMapUnmanaged(ErrorHandlerFn) = .{};
var error_handler_allocator: ?std.mem.Allocator = null;

/// Initialize the error handler registry
pub fn initErrorHandlers(allocator: std.mem.Allocator) void {
    if (error_handler_allocator == null) {
        error_handler_allocator = allocator;
    }
}

/// Register an error handler
pub fn register_error(name: []const u8, handler: ErrorHandlerFn) void {
    if (error_handler_allocator) |alloc| {
        // Duplicate the name for storage
        const name_copy = alloc.dupe(u8, name) catch return;
        error_handlers.put(alloc, name_copy, handler) catch {
            alloc.free(name_copy);
        };
    }
}

/// Look up an error handler by name
pub fn lookup_error(name: []const u8) ?ErrorHandlerFn {
    // Check custom handlers first
    if (error_handlers.get(name)) |handler| {
        return handler;
    }

    // Built-in handlers
    if (std.mem.eql(u8, name, "strict")) {
        return &strictHandler;
    } else if (std.mem.eql(u8, name, "ignore")) {
        return &ignoreHandler;
    } else if (std.mem.eql(u8, name, "replace")) {
        return &replaceHandler;
    }

    return null;
}

// Built-in error handlers
fn strictHandler(_: []const u8, pos: usize) struct { replacement: []const u8, position: usize } {
    // Strict mode raises error - return empty replacement at same position
    return .{ .replacement = "", .position = pos };
}

fn ignoreHandler(_: []const u8, pos: usize) struct { replacement: []const u8, position: usize } {
    // Ignore mode skips the bad character
    return .{ .replacement = "", .position = pos + 1 };
}

fn replaceHandler(_: []const u8, pos: usize) struct { replacement: []const u8, position: usize } {
    // Replace mode uses replacement character
    return .{ .replacement = "\xef\xbf\xbd", .position = pos + 1 }; // U+FFFD
}

// ============================================================================
// BOM Constants
// ============================================================================

pub const BOM = "\xef\xbb\xbf"; // UTF-8 BOM
pub const BOM_UTF8 = BOM;
pub const BOM_LE = "\xff\xfe"; // UTF-16 LE
pub const BOM_BE = "\xfe\xff"; // UTF-16 BE
pub const BOM_UTF16 = BOM_LE; // Native UTF-16
pub const BOM_UTF16_LE = BOM_LE;
pub const BOM_UTF16_BE = BOM_BE;
pub const BOM_UTF32 = "\xff\xfe\x00\x00"; // Native UTF-32
pub const BOM_UTF32_LE = "\xff\xfe\x00\x00";
pub const BOM_UTF32_BE = "\x00\x00\xfe\xff";

// ============================================================================
// Utility Functions
// ============================================================================

/// Open a file with encoding
pub fn open(allocator: std.mem.Allocator, filename: []const u8, mode: []const u8, encoding: ?[]const u8, errors: ?[]const u8, buffering: ?i32) !std.fs.File {
    _ = allocator;
    _ = encoding;
    _ = errors;
    _ = buffering;

    const flags: std.fs.File.OpenFlags = if (std.mem.indexOf(u8, mode, "w") != null)
        .{ .mode = .write_only }
    else
        .{};

    return std.fs.cwd().openFile(filename, flags);
}

/// Encode a filename for the filesystem
pub fn encodeFilesystemPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // On most systems, just return as-is
    return allocator.dupe(u8, path);
}

/// Decode a filename from the filesystem
pub fn decodeFilesystemPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return allocator.dupe(u8, path);
}

/// Make an identity encoding
pub fn makeIdentityCodec(name: []const u8) CodecInfo {
    const encode_fn = struct {
        fn f(input: []const u8, errors: []const u8) EncodeResult {
            _ = errors;
            return .{ .output = input, .length = input.len };
        }
    }.f;

    const decode_fn = struct {
        fn f(input: []const u8, errors: []const u8) DecodeResult {
            _ = errors;
            return .{ .output = input, .length = input.len };
        }
    }.f;

    return .{
        .name = name,
        .encode = encode_fn,
        .decode = decode_fn,
    };
}

// ============================================================================
// Charmap Codec
// ============================================================================

/// Create a charmap encoder
pub fn charmapEncode(input: []const u8, errors: []const u8, mapping: ?[]const ?u8) ![]u8 {
    _ = errors;
    if (mapping == null) {
        return @constCast(input);
    }

    var result: std.ArrayList(u8) = .{};
    for (input) |c| {
        if (mapping.?[c]) |mapped| {
            try result.append(allocator_helper.fast_allocator, mapped);
        } else {
            try result.append(allocator_helper.fast_allocator, c);
        }
    }
    return result.toOwnedSlice(allocator_helper.fast_allocator);
}

/// Create a charmap decoder
pub fn charmapDecode(input: []const u8, errors: []const u8, mapping: ?[]const ?u21) ![]u8 {
    _ = errors;
    if (mapping == null) {
        return @constCast(input);
    }

    var result: std.ArrayList(u8) = .{};
    for (input) |c| {
        if (mapping.?[c]) |codepoint| {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buf) catch continue;
            try result.appendSlice(allocator_helper.fast_allocator, buf[0..len]);
        } else {
            try result.append(allocator_helper.fast_allocator, c);
        }
    }
    return result.toOwnedSlice(allocator_helper.fast_allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "BOM constants" {
    try std.testing.expectEqualStrings("\xef\xbb\xbf", BOM_UTF8);
    try std.testing.expectEqualStrings("\xff\xfe", BOM_UTF16_LE);
    try std.testing.expectEqualStrings("\xfe\xff", BOM_UTF16_BE);
}

test "identity codec" {
    const codec = makeIdentityCodec("identity");
    try std.testing.expectEqualStrings("identity", codec.name);

    const result = codec.encode("hello", "strict");
    try std.testing.expectEqualStrings("hello", result.output);
    try std.testing.expectEqual(@as(usize, 5), result.length);
}

test "incremental encoder" {
    var encoder = IncrementalEncoder.init(std.testing.allocator, "strict");
    defer encoder.deinit();

    const result = try encoder.encodeChunk("test", true);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("test", result);
}
