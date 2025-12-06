/// Unicode Format Implementation - PyUnicode_Format() for % formatting
///
/// Implements CPython's Objects/unicode_format.c
/// Provides % (modulo) formatting for Unicode strings
///
/// Reference: cpython/Objects/unicode_format.c
/// This implements the unicode version of str % args

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// FORMAT FLAGS (from pycore_format.h)
// ============================================================================

pub const F_LJUST: c_int = 1 << 0; // Left justify
pub const F_SIGN: c_int = 1 << 1; // Always print sign
pub const F_BLANK: c_int = 1 << 2; // Leave blank for positive
pub const F_ALT: c_int = 1 << 3; // Alternate form (0x, 0o, etc.)
pub const F_ZERO: c_int = 1 << 4; // Zero pad

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// unicode_formatter_t - formatter state for % formatting
/// Reference: cpython/Objects/unicode_format.c
pub const unicode_formatter_t = extern struct {
    args: ?*cpython.PyObject, // 8 bytes - arguments tuple or single object
    args_owned: c_int, // 4 bytes - whether we own the args reference
    arglen: isize, // 8 bytes - number of arguments
    argidx: isize, // 8 bytes - current argument index
    dict: ?*cpython.PyObject, // 8 bytes - dictionary for %(name) format

    fmtkind: c_int, // 4 bytes - PyUnicode_KIND of format string
    fmtcnt: isize, // 8 bytes - remaining characters in format string
    fmtpos: isize, // 8 bytes - current position in format string
    fmtdata: ?*const anyopaque, // 8 bytes - format string data pointer
    fmtstr: ?*cpython.PyObject, // 8 bytes - format string object

    // _PyUnicodeWriter is embedded here in CPython
    // We'll handle this separately
};

/// unicode_format_arg_t - parsed format argument
/// Reference: cpython/Objects/unicode_format.c
pub const unicode_format_arg_t = extern struct {
    ch: u32, // 4 bytes - format character (d, s, r, f, etc.)
    flags: c_int, // 4 bytes - format flags (F_LJUST, etc.)
    width: isize, // 8 bytes - field width
    prec: c_int, // 4 bytes - precision
    sign: c_int, // 4 bytes - sign character
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Get the next argument from the formatter context
fn unicode_format_getnextarg(ctx: *unicode_formatter_t) ?*cpython.PyObject {
    const argidx = ctx.argidx;

    if (argidx < ctx.arglen) {
        ctx.argidx += 1;
        if (ctx.arglen < 0) {
            return ctx.args;
        } else {
            const tuple = @import("tupleobject.zig");
            return tuple.PyTuple_GetItem(ctx.args.?, @intCast(argidx));
        }
    }
    // Not enough arguments
    return null;
}

/// Parse format flags from format string
fn parse_format_flags(data: [*]const u8, pos: *isize, end: isize) c_int {
    var flags: c_int = 0;

    while (pos.* < end) {
        const c = data[@intCast(pos.*)];
        switch (c) {
            '-' => flags |= F_LJUST,
            '+' => flags |= F_SIGN,
            ' ' => flags |= F_BLANK,
            '#' => flags |= F_ALT,
            '0' => flags |= F_ZERO,
            else => break,
        }
        pos.* += 1;
    }

    return flags;
}

/// Parse width from format string
fn parse_format_width(data: [*]const u8, pos: *isize, end: isize) isize {
    var width: isize = 0;

    while (pos.* < end) {
        const c = data[@intCast(pos.*)];
        if (c >= '0' and c <= '9') {
            width = width * 10 + @as(isize, c - '0');
            pos.* += 1;
        } else {
            break;
        }
    }

    return width;
}

/// Parse precision from format string
fn parse_format_precision(data: [*]const u8, pos: *isize, end: isize) c_int {
    if (pos.* >= end or data[@intCast(pos.*)] != '.') {
        return -1; // No precision specified
    }

    pos.* += 1; // Skip '.'
    var prec: c_int = 0;

    while (pos.* < end) {
        const c = data[@intCast(pos.*)];
        if (c >= '0' and c <= '9') {
            prec = prec * 10 + @as(c_int, c - '0');
            pos.* += 1;
        } else {
            break;
        }
    }

    return prec;
}

// ============================================================================
// FORMAT CONVERTERS
// ============================================================================

/// Format an integer value
fn format_long(value: ?*cpython.PyObject, arg: *const unicode_format_arg_t) ?*cpython.PyObject {
    _ = value;
    _ = arg;
    // TODO: Implement integer formatting
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("<int>");
}

/// Format a float value
fn format_float(value: ?*cpython.PyObject, arg: *const unicode_format_arg_t) ?*cpython.PyObject {
    _ = value;
    _ = arg;
    // TODO: Implement float formatting
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("<float>");
}

/// Format a string value (using str() or repr())
fn format_string(value: ?*cpython.PyObject, arg: *const unicode_format_arg_t, use_repr: bool) ?*cpython.PyObject {
    _ = arg;
    if (value == null) return null;

    const object_mod = @import("object.zig");

    if (use_repr) {
        return object_mod.PyObject_Repr(value);
    } else {
        return object_mod.PyObject_Str(value);
    }
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// PyUnicode_Format - format a string using % formatting
/// This is the main entry point for str % args
pub export fn PyUnicode_Format(format: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    if (format == null) return null;

    // Verify format is a unicode string
    const pyunicode = @import("unicodeobject.zig");
    if (pyunicode.PyUnicode_Check(format.?) == 0) {
        return null;
    }

    // Get format string info
    const fmt_len = pyunicode.PyUnicode_GetLength(format.?);
    if (fmt_len < 0) return null;

    // For simple case with no %, just return a copy
    const fmt_str = pyunicode.PyUnicode_AsUTF8(format.?);
    if (fmt_str == null) return null;

    // Check if there's any % formatting
    var has_format = false;
    var i: usize = 0;
    const len: usize = @intCast(fmt_len);
    while (i < len) : (i += 1) {
        if (fmt_str[i] == '%') {
            if (i + 1 < len and fmt_str[i + 1] == '%') {
                i += 1; // Skip %%
            } else {
                has_format = true;
                break;
            }
        }
    }

    if (!has_format) {
        // No formatting needed, return copy of format string
        format.?.ob_refcnt += 1;
        return format;
    }

    // Initialize formatter state
    var ctx: unicode_formatter_t = .{
        .args = args,
        .args_owned = 0,
        .arglen = 0,
        .argidx = 0,
        .dict = null,
        .fmtkind = 1, // PyUnicode_1BYTE_KIND
        .fmtcnt = fmt_len,
        .fmtpos = 0,
        .fmtdata = fmt_str,
        .fmtstr = format,
    };

    // Determine argument count
    const tuple = @import("tupleobject.zig");
    const dict = @import("dictobject.zig");

    if (args != null) {
        if (dict.PyDict_Check(args.?) != 0) {
            ctx.dict = args;
            ctx.arglen = -1;
        } else if (tuple.PyTuple_Check(args.?) != 0) {
            ctx.arglen = tuple.PyTuple_Size(args.?);
        } else {
            ctx.arglen = -1; // Single argument
        }
    }

    // Build result string
    // For now, return a placeholder - full implementation would iterate format string
    _ = &ctx;

    // Simple implementation: just return format string for now
    // Full implementation would process each % format spec
    format.?.ob_refcnt += 1;
    return format;
}

/// _PyUnicode_FormatLong - format a long integer
/// Used by unicode_format.c for %d, %i, %o, %x, %X format codes
pub export fn _PyUnicode_FormatLong(val: ?*cpython.PyObject, alt: c_int, prec: c_int, format_type: c_int) ?*cpython.PyObject {
    if (val == null) return null;

    const pyunicode = @import("unicodeobject.zig");
    const pylong = @import("longobject.zig");

    // Get the long value
    if (pylong.PyLong_Check(val.?) == 0) {
        return null;
    }

    // Format based on type
    var base: c_int = 10;
    var prefix: ?[*:0]const u8 = null;

    switch (@as(u8, @intCast(format_type))) {
        'd', 'i', 'u' => {
            base = 10;
        },
        'o' => {
            base = 8;
            if (alt != 0) prefix = "0o";
        },
        'x' => {
            base = 16;
            if (alt != 0) prefix = "0x";
        },
        'X' => {
            base = 16;
            if (alt != 0) prefix = "0X";
        },
        else => return null,
    }

    _ = prec;
    _ = base;
    _ = prefix;

    // TODO: Implement full formatting
    // For now return placeholder
    return pyunicode.PyUnicode_FromString("<long>");
}

/// Format a float into a string
pub export fn _PyUnicode_FormatFloat(val: ?*cpython.PyObject, prec: c_int, format_type: c_int, flags: c_int) ?*cpython.PyObject {
    if (val == null) return null;

    const arg: unicode_format_arg_t = .{
        .ch = @intCast(format_type),
        .flags = flags,
        .width = 0,
        .prec = prec,
        .sign = 0,
    };

    return format_float(val, &arg);
}

/// Check if a character is a valid format character
pub export fn _PyUnicode_IsFormatChar(ch: u32) c_int {
    return switch (ch) {
        'd', 'i', 'o', 'u', 'x', 'X', // integers
        'e', 'E', 'f', 'F', 'g', 'G', // floats
        'c', // character
        's', 'r', 'a', // string/repr/ascii
        '%', // literal %
        => 1,
        else => 0,
    };
}
