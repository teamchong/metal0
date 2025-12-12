//! CPython source: Lib/configparser.py
//!
//! Interpolation classes for variable substitution in configuration values.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

/// No interpolation
pub const BasicInterpolation = struct {
    pub fn beforeGet(self: *BasicInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8, defaults: anytype) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        _ = defaults;
        return value;
    }

    pub fn beforeSet(self: *BasicInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        return value;
    }
};

/// Extended interpolation with ${section:option} syntax
pub const ExtendedInterpolation = struct {
    allocator: std.mem.Allocator = allocator_helper.fast_allocator,
    max_depth: u8 = 10,

    /// Perform ${section:option} or ${option} interpolation
    pub fn beforeGet(self: *ExtendedInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8, defaults: anytype) ![]const u8 {
        _ = option;
        return self.interpolate(parser, section, value, defaults, 0);
    }

    fn interpolate(self: *ExtendedInterpolation, parser: anytype, section: []const u8, value: []const u8, defaults: anytype, depth: u8) ![]const u8 {
        if (depth > self.max_depth) return error.InterpolationDepthError;

        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < value.len) {
            if (i + 1 < value.len and value[i] == '$' and value[i + 1] == '{') {
                // Find closing brace
                const start = i + 2;
                var end = start;
                while (end < value.len and value[end] != '}') : (end += 1) {}
                if (end >= value.len) {
                    try result.append(self.allocator, value[i]);
                    i += 1;
                    continue;
                }

                const ref = value[start..end];

                // Parse section:option or just option
                var ref_section = section;
                var ref_option = ref;
                if (std.mem.indexOf(u8, ref, ":")) |colon_idx| {
                    ref_section = ref[0..colon_idx];
                    ref_option = ref[colon_idx + 1 ..];
                }

                // Look up the value
                var ref_value: ?[]const u8 = null;

                // Check defaults first
                if (@TypeOf(defaults) != @TypeOf(null)) {
                    if (defaults.get(ref_option)) |v| {
                        ref_value = v;
                    }
                }

                // Then check section
                if (ref_value == null) {
                    if (parser.sections.get(ref_section)) |sect| {
                        if (sect.get(ref_option)) |v| {
                            ref_value = v;
                        }
                    }
                }

                // Check parser defaults
                if (ref_value == null) {
                    if (parser.defaults.get(ref_option)) |v| {
                        ref_value = v;
                    }
                }

                if (ref_value) |v| {
                    // Recursively interpolate
                    const interpolated = try self.interpolate(parser, ref_section, v, defaults, depth + 1);
                    try result.appendSlice(self.allocator, interpolated);
                } else {
                    return error.InterpolationMissingOptionError;
                }

                i = end + 1;
            } else {
                try result.append(self.allocator, value[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    pub fn beforeSet(self: *ExtendedInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        return value;
    }
};
