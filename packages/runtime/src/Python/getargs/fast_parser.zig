/// fast_parser - Fast Argument Parser
/// Pre-parsed format string for faster argument parsing.

const std = @import("std");
const types = @import("types.zig");

pub const ArgError = types.ArgError;

// ============================================================================
// Fast Parser
// ============================================================================

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

// ============================================================================
// Format Parser
// ============================================================================

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
        self.units.deinit(self.allocator);
        self.keywords.deinit(self.allocator);
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

                        try self.units.append(self.allocator, .{ .code = c, .flags = flags });
                        self.max_pos += 1;
                        if (!optional and !keyword_only) {
                            self.min_pos += 1;
                        }
                    }
                },
            }
        }

        return FastArgParser{
            .keywords = try self.keywords.toOwnedSlice(self.allocator),
            .min_positional = self.min_pos,
            .max_positional = self.max_pos,
            .format_units = try self.units.toOwnedSlice(self.allocator),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

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
