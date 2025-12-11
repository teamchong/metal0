/// Precise error types - Generate error{KeyError,IndexError}!T not anyerror!T
/// Python exception types mapped to Zig error enum values
const std = @import("std");

pub const PreciseError = enum {
    // Lookup errors
    KeyError, // dict[missing_key]
    IndexError, // list[out_of_bounds]
    AttributeError, // obj.missing_attr

    // Type errors
    TypeError, // type mismatch
    ValueError, // invalid value (e.g., int("abc"))

    // Arithmetic errors
    ZeroDivisionError, // x / 0
    OverflowError, // integer overflow

    // I/O errors
    FileNotFoundError, // open() missing file
    PermissionError, // access denied
    IOError, // general I/O

    // Runtime errors
    RuntimeError, // generic
    StopIteration, // iterator exhausted
    AssertionError, // assert failed
    NotImplementedError, // abstract method

    /// Generate Zig error set string from a slice of errors
    pub fn toErrorSet(errors: []const PreciseError) []const u8 {
        if (errors.len == 0) return "error{}";
        // For now, return a static representation
        // In practice, we'd build this dynamically
        return switch (errors[0]) {
            .KeyError => "error{KeyError}",
            .IndexError => "error{IndexError}",
            .ValueError => "error{ValueError}",
            .TypeError => "error{TypeError}",
            .ZeroDivisionError => "error{DivisionByZero}",
            .OverflowError => "error{Overflow}",
            .FileNotFoundError => "error{FileNotFound}",
            .AssertionError => "error{AssertionFailed}",
            else => "error{RuntimeError}",
        };
    }
};

/// Packed error set using bit flags for efficient storage (16 errors = 16 bits)
pub const ErrorSet = packed struct {
    KeyError: bool = false,
    IndexError: bool = false,
    AttributeError: bool = false,
    TypeError: bool = false,
    ValueError: bool = false,
    ZeroDivisionError: bool = false,
    OverflowError: bool = false,
    FileNotFoundError: bool = false,
    PermissionError: bool = false,
    IOError: bool = false,
    RuntimeError: bool = false,
    StopIteration: bool = false,
    AssertionError: bool = false,
    NotImplementedError: bool = false,
    _padding: u2 = 0,

    pub fn isEmpty(self: ErrorSet) bool {
        return @as(u16, @bitCast(self)) == 0;
    }

    pub fn merge(self: ErrorSet, other: ErrorSet) ErrorSet {
        return @bitCast(@as(u16, @bitCast(self)) | @as(u16, @bitCast(other)));
    }

    /// Generate Zig error set string like "error{KeyError,IndexError}"
    pub fn toZigErrorSet(self: ErrorSet, buf: []u8) []const u8 {
        if (self.isEmpty()) return "error{}";
        var pos: usize = 0;
        const prefix = "error{";
        @memcpy(buf[pos..][0..prefix.len], prefix);
        pos += prefix.len;

        var first = true;
        if (self.KeyError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "KeyError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.IndexError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "IndexError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.ValueError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "ValueError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.TypeError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "TypeError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.ZeroDivisionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "DivisionByZero";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.FileNotFoundError or self.IOError or self.PermissionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "IoError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.AssertionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "AssertionFailed";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.RuntimeError or self.NotImplementedError or self.AttributeError or self.OverflowError or self.StopIteration) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "RuntimeError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        buf[pos] = '}';
        pos += 1;
        return buf[0..pos];
    }
};
