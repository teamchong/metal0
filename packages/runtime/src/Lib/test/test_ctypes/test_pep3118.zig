//! test.test_ctypes.test_pep3118 - Tests for PEP 3118 buffer protocol
//! Reference: cpython/Lib/test/test_ctypes/test_pep3118.py
//!
//! Tests for the buffer protocol implementation in ctypes as specified
//! in PEP 3118.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Buffer Format Characters
// ============================================================================

pub const FormatChar = struct {
    pub const BYTE: u8 = 'b';
    pub const UBYTE: u8 = 'B';
    pub const CHAR: u8 = 'c';
    pub const SHORT: u8 = 'h';
    pub const USHORT: u8 = 'H';
    pub const INT: u8 = 'i';
    pub const UINT: u8 = 'I';
    pub const LONG: u8 = 'l';
    pub const ULONG: u8 = 'L';
    pub const LONGLONG: u8 = 'q';
    pub const ULONGLONG: u8 = 'Q';
    pub const FLOAT: u8 = 'f';
    pub const DOUBLE: u8 = 'd';
    pub const POINTER: u8 = 'P';
    pub const BOOL: u8 = '?';
};

/// Get size for format character
pub fn getFormatSize(format: u8) usize {
    return switch (format) {
        FormatChar.BYTE, FormatChar.UBYTE, FormatChar.CHAR, FormatChar.BOOL => 1,
        FormatChar.SHORT, FormatChar.USHORT => 2,
        FormatChar.INT, FormatChar.UINT => 4,
        FormatChar.LONG, FormatChar.ULONG => 8,
        FormatChar.LONGLONG, FormatChar.ULONGLONG => 8,
        FormatChar.FLOAT => 4,
        FormatChar.DOUBLE => 8,
        FormatChar.POINTER => @sizeOf(*anyopaque),
        else => 1,
    };
}

// ============================================================================
// Buffer View
// ============================================================================

pub const Py_buffer = struct {
    buf: ?*anyopaque = null,
    obj: ?*anyopaque = null,
    len: isize = 0,
    itemsize: isize = 1,
    readonly: bool = false,
    ndim: i32 = 0,
    format: ?[*:0]const u8 = null,
    shape: ?[*]isize = null,
    strides: ?[*]isize = null,
    suboffsets: ?[*]isize = null,
    internal: ?*anyopaque = null,

    pub fn init() Py_buffer {
        return .{};
    }

    /// Check if buffer is contiguous
    pub fn isContiguous(self: *const Py_buffer, order: u8) bool {
        _ = order;
        if (self.ndim == 0) return true;
        if (self.strides == null) return true;

        // Check C-contiguous (row-major)
        if (self.ndim == 1 and self.strides.?[0] == self.itemsize) {
            return true;
        }

        return false;
    }

    /// Get total number of bytes
    pub fn getSize(self: *const Py_buffer) usize {
        if (self.len < 0) return 0;
        return @intCast(self.len);
    }

    /// Get format string
    pub fn getFormat(self: *const Py_buffer) []const u8 {
        if (self.format) |fmt| {
            var len: usize = 0;
            while (fmt[len] != 0) : (len += 1) {}
            return fmt[0..len];
        }
        return "B"; // Default: unsigned bytes
    }
};

// ============================================================================
// Buffer Producer
// ============================================================================

pub fn BufferProducer(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        data: [N]T = undefined,
        exported: bool = false,

        pub fn init() Self {
            return .{ .data = [_]T{std.mem.zeroes(T)} ** N };
        }

        pub fn getBuffer(self: *Self, view: *Py_buffer, flags: i32) !void {
            _ = flags;
            view.buf = @ptrCast(&self.data);
            view.len = @intCast(@sizeOf(T) * N);
            view.itemsize = @sizeOf(T);
            view.ndim = 1;
            view.readonly = false;
            self.exported = true;
        }

        pub fn releaseBuffer(self: *Self) void {
            self.exported = false;
        }

        pub fn isExported(self: *const Self) bool {
            return self.exported;
        }
    };
}

// ============================================================================
// Format String Parser
// ============================================================================

pub const FormatInfo = struct {
    item_count: usize = 0,
    total_size: usize = 0,
    is_native: bool = true,
    is_little_endian: bool = true,
};

/// Parse a format string
pub fn parseFormat(format: []const u8) FormatInfo {
    var info = FormatInfo{};
    var i: usize = 0;

    // Check for byte order
    if (format.len > 0) {
        switch (format[0]) {
            '@', '=' => {
                info.is_native = true;
                i = 1;
            },
            '<' => {
                info.is_native = false;
                info.is_little_endian = true;
                i = 1;
            },
            '>', '!' => {
                info.is_native = false;
                info.is_little_endian = false;
                i = 1;
            },
            else => {},
        }
    }

    // Parse format chars
    while (i < format.len) : (i += 1) {
        const size = getFormatSize(format[i]);
        info.total_size += size;
        info.item_count += 1;
    }

    return info;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testFormatCharSizes() !void {
    try std.testing.expectEqual(@as(usize, 1), getFormatSize(FormatChar.BYTE));
    try std.testing.expectEqual(@as(usize, 2), getFormatSize(FormatChar.SHORT));
    try std.testing.expectEqual(@as(usize, 4), getFormatSize(FormatChar.INT));
    try std.testing.expectEqual(@as(usize, 8), getFormatSize(FormatChar.LONGLONG));
    try std.testing.expectEqual(@as(usize, 4), getFormatSize(FormatChar.FLOAT));
    try std.testing.expectEqual(@as(usize, 8), getFormatSize(FormatChar.DOUBLE));
}

fn testPyBufferInit() !void {
    const buf = Py_buffer.init();
    try std.testing.expect(buf.buf == null);
    try std.testing.expectEqual(@as(isize, 0), buf.len);
    try std.testing.expectEqual(@as(i32, 0), buf.ndim);
}

fn testPyBufferGetFormat() !void {
    var buf = Py_buffer.init();
    try std.testing.expectEqualStrings("B", buf.getFormat());

    buf.format = "i";
    try std.testing.expectEqualStrings("i", buf.getFormat());
}

fn testPyBufferGetSize() !void {
    var buf = Py_buffer.init();
    buf.len = 100;
    try std.testing.expectEqual(@as(usize, 100), buf.getSize());
}

fn testBufferProducer() !void {
    const Producer = BufferProducer(i32, 10);
    var producer = Producer.init();

    try std.testing.expect(!producer.isExported());

    var view = Py_buffer.init();
    try producer.getBuffer(&view, 0);

    try std.testing.expect(producer.isExported());
    try std.testing.expect(view.buf != null);
    try std.testing.expectEqual(@as(isize, 40), view.len); // 10 * 4 bytes

    producer.releaseBuffer();
    try std.testing.expect(!producer.isExported());
}

fn testParseFormatSimple() !void {
    const info = parseFormat("i");
    try std.testing.expectEqual(@as(usize, 1), info.item_count);
    try std.testing.expectEqual(@as(usize, 4), info.total_size);
    try std.testing.expect(info.is_native);
}

fn testParseFormatMultiple() !void {
    const info = parseFormat("iid");
    try std.testing.expectEqual(@as(usize, 3), info.item_count);
    try std.testing.expectEqual(@as(usize, 16), info.total_size); // 4 + 4 + 8
}

fn testParseFormatByteOrder() !void {
    const native = parseFormat("@i");
    try std.testing.expect(native.is_native);

    const little = parseFormat("<i");
    try std.testing.expect(!little.is_native);
    try std.testing.expect(little.is_little_endian);

    const big = parseFormat(">i");
    try std.testing.expect(!big.is_native);
    try std.testing.expect(!big.is_little_endian);
}

fn testPyBufferContiguous() !void {
    var buf = Py_buffer.init();
    buf.ndim = 1;
    buf.itemsize = 4;

    var strides = [_]isize{4};
    buf.strides = &strides;

    try std.testing.expect(buf.isContiguous('C'));
}

fn testFormatCharConstants() !void {
    try std.testing.expectEqual(@as(u8, 'b'), FormatChar.BYTE);
    try std.testing.expectEqual(@as(u8, 'i'), FormatChar.INT);
    try std.testing.expectEqual(@as(u8, 'd'), FormatChar.DOUBLE);
    try std.testing.expectEqual(@as(u8, 'P'), FormatChar.POINTER);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "format_char_sizes" {
    try testFormatCharSizes();
}

test "py_buffer_init" {
    try testPyBufferInit();
}

test "py_buffer_get_format" {
    try testPyBufferGetFormat();
}

test "py_buffer_get_size" {
    try testPyBufferGetSize();
}

test "buffer_producer" {
    try testBufferProducer();
}

test "parse_format_simple" {
    try testParseFormatSimple();
}

test "parse_format_multiple" {
    try testParseFormatMultiple();
}

test "parse_format_byte_order" {
    try testParseFormatByteOrder();
}

test "py_buffer_contiguous" {
    try testPyBufferContiguous();
}

test "format_char_constants" {
    try testFormatCharConstants();
}
