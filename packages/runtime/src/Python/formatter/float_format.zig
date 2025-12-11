/// Float formatting utilities
const std = @import("std");

/// Sign handling for float formatting
pub const FloatSignOption = enum { none, plus, space };

/// Format type for float formatting
pub const FloatFormatType = enum { general, fixed, scientific, repr };

/// Options for Python float formatting
pub const PyFloatFormatOptions = struct {
    sign: FloatSignOption = .none,
    precision: ?u32 = null,
    format_type: FloatFormatType = .general,
};

/// Canonical Python float formatter
pub fn formatPythonFloat(allocator: std.mem.Allocator, value: f64, options: PyFloatFormatOptions) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    if (std.math.isNan(value)) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
        try result.appendSlice(allocator, "nan");
        return result.toOwnedSlice(allocator);
    }

    if (std.math.isInf(value)) {
        if (value < 0) {
            try result.appendSlice(allocator, "-inf");
        } else {
            switch (options.sign) {
                .plus => try result.append(allocator, '+'),
                .space => try result.append(allocator, ' '),
                .none => {},
            }
            try result.appendSlice(allocator, "inf");
        }
        return result.toOwnedSlice(allocator);
    }

    if (value >= 0) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
    }

    switch (options.format_type) {
        .repr, .general => {
            if (@mod(value, 1.0) == 0.0 and @abs(value) < 1e15) {
                try result.writer(allocator).print("{d:.1}", .{value});
            } else {
                try result.writer(allocator).print("{d}", .{value});
            }
        },
        .fixed => {
            const prec = options.precision orelse 6;
            try result.writer(allocator).print("{d:.[1]}", .{ value, prec });
        },
        .scientific => {
            const prec = options.precision orelse 6;
            try result.writer(allocator).print("{e:.[1]}", .{ value, prec });
        },
    }

    return result.toOwnedSlice(allocator);
}

/// Format float value for printing
pub fn formatFloat(value: f64, allocator: std.mem.Allocator) ![]const u8 {
    return formatPythonFloat(allocator, value, .{});
}

/// Python-style floored modulo
pub fn pyFloatMod(a: f64, b: f64) f64 {
    const result = @mod(a, b);
    if ((result < 0 and b > 0) or (result > 0 and b < 0)) {
        return result + b;
    }
    return result;
}

/// Python-style floor division
pub fn pyFloatFloorDiv(a: f64, b: f64) f64 {
    return @floor(a / b);
}
