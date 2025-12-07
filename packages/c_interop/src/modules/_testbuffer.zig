//! Python '_testbuffer' module - Buffer protocol testing
//!
//! Internal test module for verifying CPython's buffer protocol implementation.
//! The buffer protocol allows Python objects to share memory efficiently
//! without copying data.
//!
//! In metal0's AOT model, we use Zig slices which provide similar
//! zero-copy semantics natively.
//!
//! Mirrors: CPython Modules/_testbuffer.c

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TestBufferError = error{
    TestFailed,
    BufferError,
    TypeError,
    ValueError,
    OutOfMemory,
};

// ============================================================================
// Test Counters
// ============================================================================

var tests_run: usize = 0;
var tests_passed: usize = 0;
var tests_failed: usize = 0;

// ============================================================================
// Buffer Flags (matching CPython's Py_buffer flags)
// ============================================================================

pub const PyBUF_SIMPLE: i32 = 0;
pub const PyBUF_WRITABLE: i32 = 0x0001;
pub const PyBUF_FORMAT: i32 = 0x0004;
pub const PyBUF_ND: i32 = 0x0008;
pub const PyBUF_STRIDES: i32 = 0x0010 | PyBUF_ND;
pub const PyBUF_C_CONTIGUOUS: i32 = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_F_CONTIGUOUS: i32 = 0x0040 | PyBUF_STRIDES;
pub const PyBUF_ANY_CONTIGUOUS: i32 = 0x0080 | PyBUF_STRIDES;
pub const PyBUF_INDIRECT: i32 = 0x0100 | PyBUF_STRIDES;

pub const PyBUF_CONTIG: i32 = PyBUF_ND | PyBUF_WRITABLE;
pub const PyBUF_CONTIG_RO: i32 = PyBUF_ND;
pub const PyBUF_STRIDED: i32 = PyBUF_STRIDES | PyBUF_WRITABLE;
pub const PyBUF_STRIDED_RO: i32 = PyBUF_STRIDES;
pub const PyBUF_RECORDS: i32 = PyBUF_STRIDES | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_RECORDS_RO: i32 = PyBUF_STRIDES | PyBUF_FORMAT;
pub const PyBUF_FULL: i32 = PyBUF_INDIRECT | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_FULL_RO: i32 = PyBUF_INDIRECT | PyBUF_FORMAT;

// ============================================================================
// Buffer Structure
// ============================================================================

/// Buffer info structure (mirrors Py_buffer)
pub const BufferInfo = struct {
    buf: ?[*]u8 = null,
    len: isize = 0,
    itemsize: isize = 1,
    readonly: bool = true,
    format: ?[]const u8 = null,
    ndim: i32 = 1,
    shape: ?[]const isize = null,
    strides: ?[]const isize = null,
    suboffsets: ?[]const isize = null,
    internal: ?*anyopaque = null,
};

// ============================================================================
// Test Buffer Object
// ============================================================================

/// Simple test buffer implementation
pub const TestBuffer = struct {
    const Self = @This();

    data: []u8,
    readonly: bool,
    format: []const u8,
    itemsize: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, readonly: bool) !Self {
        const data = try allocator.alloc(u8, size);
        return Self{
            .data = data,
            .readonly = readonly,
            .format = "B", // unsigned char
            .itemsize = 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    pub fn getBuffer(self: *const Self) BufferInfo {
        return BufferInfo{
            .buf = self.data.ptr,
            .len = @intCast(self.data.len),
            .itemsize = @intCast(self.itemsize),
            .readonly = self.readonly,
            .format = self.format,
            .ndim = 1,
        };
    }
};

// ============================================================================
// Buffer Protocol Tests
// ============================================================================

/// Test simple buffer
pub fn test_simple_buffer() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 256, true) catch return error.OutOfMemory;
    defer buf.deinit();

    const info = buf.getBuffer();
    if (info.len != 256) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

/// Test writable buffer
pub fn test_writable_buffer() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 128, false) catch return error.OutOfMemory;
    defer buf.deinit();

    if (buf.readonly) {
        tests_failed += 1;
        return error.BufferError;
    }

    // Write to buffer
    buf.data[0] = 42;
    if (buf.data[0] != 42) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

/// Test readonly buffer
pub fn test_readonly_buffer() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 64, true) catch return error.OutOfMemory;
    defer buf.deinit();

    const info = buf.getBuffer();
    if (!info.readonly) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

/// Test buffer format
pub fn test_buffer_format() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 32, true) catch return error.OutOfMemory;
    defer buf.deinit();

    const info = buf.getBuffer();
    if (info.format == null or !std.mem.eql(u8, info.format.?, "B")) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

/// Test buffer itemsize
pub fn test_buffer_itemsize() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 16, true) catch return error.OutOfMemory;
    defer buf.deinit();

    const info = buf.getBuffer();
    if (info.itemsize != 1) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

/// Test buffer ndim
pub fn test_buffer_ndim() TestBufferError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var buf = TestBuffer.init(allocator, 16, true) catch return error.OutOfMemory;
    defer buf.deinit();

    const info = buf.getBuffer();
    if (info.ndim != 1) {
        tests_failed += 1;
        return error.BufferError;
    }
    tests_passed += 1;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Run all buffer tests
pub fn run_all_tests() TestBufferError!void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;

    try test_simple_buffer();
    try test_writable_buffer();
    try test_readonly_buffer();
    try test_buffer_format();
    try test_buffer_itemsize();
    try test_buffer_ndim();
}

/// Get test statistics
pub fn get_test_stats() struct { run: usize, passed: usize, failed: usize } {
    return .{
        .run = tests_run,
        .passed = tests_passed,
        .failed = tests_failed,
    };
}

/// Reset test counters
pub fn reset_test_stats() void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;
}

// ============================================================================
// Format String Helpers
// ============================================================================

/// Get format string for a type
pub fn getFormatChar(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |info| blk: {
            if (info.signedness == .signed) {
                break :blk switch (info.bits) {
                    8 => "b",
                    16 => "h",
                    32 => "i",
                    64 => "q",
                    else => "?",
                };
            } else {
                break :blk switch (info.bits) {
                    8 => "B",
                    16 => "H",
                    32 => "I",
                    64 => "Q",
                    else => "?",
                };
            }
        },
        .float => |info| switch (info.bits) {
            32 => "f",
            64 => "d",
            else => "?",
        },
        else => "?",
    };
}

/// Calculate buffer size for format
pub fn getItemSize(format: []const u8) usize {
    if (format.len == 0) return 1;
    return switch (format[0]) {
        'b', 'B', 'c', '?' => 1,
        'h', 'H' => 2,
        'i', 'I', 'l', 'L', 'f' => 4,
        'q', 'Q', 'd' => 8,
        else => 1,
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    reset_test_stats();
}

pub fn reset() void {
    reset_test_stats();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "run buffer tests" {
    init();
    try run_all_tests();
    const stats = get_test_stats();
    try std.testing.expect(stats.run > 0);
    try std.testing.expectEqual(stats.run, stats.passed);
}

test "buffer flags" {
    try std.testing.expectEqual(@as(i32, 0), PyBUF_SIMPLE);
    try std.testing.expectEqual(@as(i32, 1), PyBUF_WRITABLE);
}

test "getFormatChar" {
    try std.testing.expectEqualStrings("b", getFormatChar(i8));
    try std.testing.expectEqualStrings("B", getFormatChar(u8));
    try std.testing.expectEqualStrings("i", getFormatChar(i32));
    try std.testing.expectEqualStrings("f", getFormatChar(f32));
    try std.testing.expectEqualStrings("d", getFormatChar(f64));
}

test "getItemSize" {
    try std.testing.expectEqual(@as(usize, 1), getItemSize("B"));
    try std.testing.expectEqual(@as(usize, 4), getItemSize("i"));
    try std.testing.expectEqual(@as(usize, 8), getItemSize("d"));
}
