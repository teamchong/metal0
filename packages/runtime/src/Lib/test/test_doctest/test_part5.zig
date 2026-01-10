//! test.test_doctest.test_part5 - Option Flags implementation
//! ELLIPSIS, NORMALIZE_WHITESPACE, and other doctest option flags.
const std = @import("std");

/// All doctest option flags matching Python's doctest module
pub const OptionFlags = struct {
    /// ... in expected output matches any substring
    pub const ELLIPSIS: u32 = 1 << 0;

    /// Collapse all whitespace sequences to a single space
    pub const NORMALIZE_WHITESPACE: u32 = 1 << 1;

    /// Ignore exception message details, match only type
    pub const IGNORE_EXCEPTION_DETAIL: u32 = 1 << 2;

    /// Don't accept True/False for 1/0 in output
    pub const DONT_ACCEPT_TRUE_FOR_1: u32 = 1 << 3;

    /// Don't accept <BLANKLINE> for empty lines
    pub const DONT_ACCEPT_BLANKLINE: u32 = 1 << 4;

    /// Skip this example entirely
    pub const SKIP: u32 = 1 << 5;

    /// Report first failure only
    pub const REPORT_ONLY_FIRST_FAILURE: u32 = 1 << 6;

    /// Include source in failure reports
    pub const REPORT_UDIFF: u32 = 1 << 7;

    /// Use context diff format
    pub const REPORT_CDIFF: u32 = 1 << 8;

    /// Use ndiff format
    pub const REPORT_NDIFF: u32 = 1 << 9;

    /// Fail on first error/unexpected exception
    pub const FAIL_FAST: u32 = 1 << 10;

    /// Comparison flags (affect output matching)
    pub const COMPARISON_FLAGS: u32 = ELLIPSIS |
        NORMALIZE_WHITESPACE |
        DONT_ACCEPT_TRUE_FOR_1 |
        DONT_ACCEPT_BLANKLINE;

    /// Reporting flags (affect output format)
    pub const REPORTING_FLAGS: u32 = REPORT_ONLY_FIRST_FAILURE |
        REPORT_UDIFF |
        REPORT_CDIFF |
        REPORT_NDIFF;

    /// Get flag by name
    pub fn byName(name: []const u8) ?u32 {
        const flags = std.StaticStringMap(u32).initComptime(.{
            .{ "ELLIPSIS", ELLIPSIS },
            .{ "NORMALIZE_WHITESPACE", NORMALIZE_WHITESPACE },
            .{ "IGNORE_EXCEPTION_DETAIL", IGNORE_EXCEPTION_DETAIL },
            .{ "DONT_ACCEPT_TRUE_FOR_1", DONT_ACCEPT_TRUE_FOR_1 },
            .{ "DONT_ACCEPT_BLANKLINE", DONT_ACCEPT_BLANKLINE },
            .{ "SKIP", SKIP },
            .{ "REPORT_ONLY_FIRST_FAILURE", REPORT_ONLY_FIRST_FAILURE },
            .{ "REPORT_UDIFF", REPORT_UDIFF },
            .{ "REPORT_CDIFF", REPORT_CDIFF },
            .{ "REPORT_NDIFF", REPORT_NDIFF },
            .{ "FAIL_FAST", FAIL_FAST },
        });
        return flags.get(name);
    }

    /// Get name of a flag
    pub fn getName(flag: u32) ?[]const u8 {
        return switch (flag) {
            ELLIPSIS => "ELLIPSIS",
            NORMALIZE_WHITESPACE => "NORMALIZE_WHITESPACE",
            IGNORE_EXCEPTION_DETAIL => "IGNORE_EXCEPTION_DETAIL",
            DONT_ACCEPT_TRUE_FOR_1 => "DONT_ACCEPT_TRUE_FOR_1",
            DONT_ACCEPT_BLANKLINE => "DONT_ACCEPT_BLANKLINE",
            SKIP => "SKIP",
            REPORT_ONLY_FIRST_FAILURE => "REPORT_ONLY_FIRST_FAILURE",
            REPORT_UDIFF => "REPORT_UDIFF",
            REPORT_CDIFF => "REPORT_CDIFF",
            REPORT_NDIFF => "REPORT_NDIFF",
            FAIL_FAST => "FAIL_FAST",
            else => null,
        };
    }
};

/// Parsed directive from doctest comment
pub const Directive = struct {
    flag: u32,
    enable: bool, // true for +FLAG, false for -FLAG

    pub fn apply(self: @This(), current_flags: u32) u32 {
        if (self.enable) {
            return current_flags | self.flag;
        } else {
            return current_flags & ~self.flag;
        }
    }
};

/// Parse directive from comment text
pub fn parseDirective(text: []const u8) ?Directive {
    const trimmed = std.mem.trim(u8, text, " \t");

    if (trimmed.len < 2) return null;

    const enable = trimmed[0] == '+';
    if (trimmed[0] != '+' and trimmed[0] != '-') return null;

    const flag_name = std.mem.trim(u8, trimmed[1..], " \t");
    const flag = OptionFlags.byName(flag_name) orelse return null;

    return .{
        .flag = flag,
        .enable = enable,
    };
}

/// Parse all directives from a line (may have multiple)
pub fn parseDirectives(
    allocator: std.mem.Allocator,
    line: []const u8,
) !std.ArrayList(Directive) {
    var directives = std.ArrayList(Directive).init(allocator);

    // Look for # doctest: marker
    const marker = "# doctest:";
    var rest = line;

    while (std.mem.indexOf(u8, rest, marker)) |idx| {
        const after = rest[idx + marker.len ..];

        // Find end of this directive (next # or end of line)
        var end: usize = after.len;
        for (after, 0..) |c, i| {
            if (c == '#' or c == ',') {
                end = i;
                break;
            }
        }

        const directive_text = after[0..end];
        if (parseDirective(directive_text)) |d| {
            try directives.append(d);
        }

        if (end >= after.len) break;
        rest = after[end..];
    }

    return directives;
}

/// Apply a list of directives to current flags
pub fn applyDirectives(directives: []const Directive, current_flags: u32) u32 {
    var flags = current_flags;
    for (directives) |d| {
        flags = d.apply(flags);
    }
    return flags;
}

/// Option flag set with helper methods
pub const FlagSet = struct {
    flags: u32 = 0,

    pub fn init() @This() {
        return .{};
    }

    pub fn initWith(flags: u32) @This() {
        return .{ .flags = flags };
    }

    pub fn set(self: *@This(), flag: u32) void {
        self.flags |= flag;
    }

    pub fn clear(self: *@This(), flag: u32) void {
        self.flags &= ~flag;
    }

    pub fn toggle(self: *@This(), flag: u32) void {
        self.flags ^= flag;
    }

    pub fn isSet(self: @This(), flag: u32) bool {
        return (self.flags & flag) != 0;
    }

    pub fn hasAny(self: @This(), flags: u32) bool {
        return (self.flags & flags) != 0;
    }

    pub fn hasAll(self: @This(), flags: u32) bool {
        return (self.flags & flags) == flags;
    }

    pub fn applyDirective(self: *@This(), directive: Directive) void {
        self.flags = directive.apply(self.flags);
    }

    /// Get active comparison flags
    pub fn comparisonFlags(self: @This()) u32 {
        return self.flags & OptionFlags.COMPARISON_FLAGS;
    }

    /// Get active reporting flags
    pub fn reportingFlags(self: @This()) u32 {
        return self.flags & OptionFlags.REPORTING_FLAGS;
    }

    /// Format flags as string
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        var first = true;
        var bit: u5 = 0;
        while (bit < 11) : (bit += 1) {
            const flag = @as(u32, 1) << bit;
            if (self.isSet(flag)) {
                if (!first) try writer.writeAll(" | ");
                first = false;
                if (OptionFlags.getName(flag)) |name| {
                    try writer.writeAll(name);
                } else {
                    try writer.print("0x{x}", .{flag});
                }
            }
        }
        if (first) {
            try writer.writeAll("(none)");
        }
    }
};

/// Default flags for various contexts
pub const DefaultFlags = struct {
    pub const TESTMOD: u32 = 0;
    pub const RUN_DOCSTRING_EXAMPLES: u32 = 0;
    pub const DEBUG: u32 = OptionFlags.REPORT_UDIFF;
    pub const VERBOSE: u32 = OptionFlags.REPORT_ONLY_FIRST_FAILURE;
};

/// Register a custom option flag
pub const CustomFlags = struct {
    next_bit: u5 = 11, // Start after built-in flags
    names: std.StringHashMap(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .names = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.names.deinit();
    }

    pub fn register(self: *@This(), name: []const u8) !u32 {
        if (self.next_bit >= 32) return error.TooManyFlags;

        const flag = @as(u32, 1) << self.next_bit;
        try self.names.put(name, flag);
        self.next_bit += 1;
        return flag;
    }

    pub fn get(self: @This(), name: []const u8) ?u32 {
        return self.names.get(name);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OptionFlags_values" {
    try std.testing.expectEqual(@as(u32, 1), OptionFlags.ELLIPSIS);
    try std.testing.expectEqual(@as(u32, 2), OptionFlags.NORMALIZE_WHITESPACE);
    try std.testing.expectEqual(@as(u32, 4), OptionFlags.IGNORE_EXCEPTION_DETAIL);
    try std.testing.expectEqual(@as(u32, 32), OptionFlags.SKIP);
}

test "OptionFlags_byName" {
    try std.testing.expectEqual(OptionFlags.ELLIPSIS, OptionFlags.byName("ELLIPSIS").?);
    try std.testing.expectEqual(OptionFlags.SKIP, OptionFlags.byName("SKIP").?);
    try std.testing.expect(OptionFlags.byName("INVALID") == null);
}

test "OptionFlags_getName" {
    try std.testing.expectEqualStrings("ELLIPSIS", OptionFlags.getName(OptionFlags.ELLIPSIS).?);
    try std.testing.expectEqualStrings("SKIP", OptionFlags.getName(OptionFlags.SKIP).?);
    try std.testing.expect(OptionFlags.getName(0xFFFF) == null);
}

test "Directive_apply_enable" {
    const d = Directive{ .flag = OptionFlags.ELLIPSIS, .enable = true };
    try std.testing.expectEqual(OptionFlags.ELLIPSIS, d.apply(0));
    try std.testing.expectEqual(
        OptionFlags.ELLIPSIS | OptionFlags.SKIP,
        d.apply(OptionFlags.SKIP),
    );
}

test "Directive_apply_disable" {
    const d = Directive{ .flag = OptionFlags.ELLIPSIS, .enable = false };
    try std.testing.expectEqual(@as(u32, 0), d.apply(OptionFlags.ELLIPSIS));
    try std.testing.expectEqual(
        OptionFlags.SKIP,
        d.apply(OptionFlags.ELLIPSIS | OptionFlags.SKIP),
    );
}

test "parseDirective_plus" {
    const d = parseDirective("+ELLIPSIS").?;
    try std.testing.expectEqual(OptionFlags.ELLIPSIS, d.flag);
    try std.testing.expect(d.enable);
}

test "parseDirective_minus" {
    const d = parseDirective("-SKIP").?;
    try std.testing.expectEqual(OptionFlags.SKIP, d.flag);
    try std.testing.expect(!d.enable);
}

test "parseDirective_with_spaces" {
    const d = parseDirective("  +NORMALIZE_WHITESPACE  ").?;
    try std.testing.expectEqual(OptionFlags.NORMALIZE_WHITESPACE, d.flag);
}

test "parseDirective_invalid" {
    try std.testing.expect(parseDirective("ELLIPSIS") == null); // No +/-
    try std.testing.expect(parseDirective("+INVALID") == null); // Unknown flag
    try std.testing.expect(parseDirective("") == null); // Empty
}

test "parseDirectives_single" {
    var directives = try parseDirectives(std.testing.allocator, ">>> x = 1  # doctest: +ELLIPSIS");
    defer directives.deinit();

    try std.testing.expectEqual(@as(usize, 1), directives.items.len);
    try std.testing.expectEqual(OptionFlags.ELLIPSIS, directives.items[0].flag);
}

test "parseDirectives_multiple" {
    var directives = try parseDirectives(
        std.testing.allocator,
        ">>> test  # doctest: +ELLIPSIS, +NORMALIZE_WHITESPACE",
    );
    defer directives.deinit();

    try std.testing.expect(directives.items.len >= 1);
}

test "applyDirectives" {
    const directives = [_]Directive{
        .{ .flag = OptionFlags.ELLIPSIS, .enable = true },
        .{ .flag = OptionFlags.SKIP, .enable = true },
    };

    const result = applyDirectives(&directives, 0);
    try std.testing.expectEqual(OptionFlags.ELLIPSIS | OptionFlags.SKIP, result);
}

test "FlagSet_init" {
    const fs = FlagSet.init();
    try std.testing.expectEqual(@as(u32, 0), fs.flags);
}

test "FlagSet_set_and_clear" {
    var fs = FlagSet.init();

    fs.set(OptionFlags.ELLIPSIS);
    try std.testing.expect(fs.isSet(OptionFlags.ELLIPSIS));

    fs.clear(OptionFlags.ELLIPSIS);
    try std.testing.expect(!fs.isSet(OptionFlags.ELLIPSIS));
}

test "FlagSet_toggle" {
    var fs = FlagSet.init();

    fs.toggle(OptionFlags.ELLIPSIS);
    try std.testing.expect(fs.isSet(OptionFlags.ELLIPSIS));

    fs.toggle(OptionFlags.ELLIPSIS);
    try std.testing.expect(!fs.isSet(OptionFlags.ELLIPSIS));
}

test "FlagSet_hasAny" {
    var fs = FlagSet.initWith(OptionFlags.ELLIPSIS);

    try std.testing.expect(fs.hasAny(OptionFlags.ELLIPSIS | OptionFlags.SKIP));
    try std.testing.expect(!fs.hasAny(OptionFlags.SKIP | OptionFlags.FAIL_FAST));
}

test "FlagSet_hasAll" {
    var fs = FlagSet.initWith(OptionFlags.ELLIPSIS | OptionFlags.SKIP);

    try std.testing.expect(fs.hasAll(OptionFlags.ELLIPSIS | OptionFlags.SKIP));
    try std.testing.expect(!fs.hasAll(OptionFlags.ELLIPSIS | OptionFlags.FAIL_FAST));
}

test "FlagSet_applyDirective" {
    var fs = FlagSet.init();

    fs.applyDirective(.{ .flag = OptionFlags.ELLIPSIS, .enable = true });
    try std.testing.expect(fs.isSet(OptionFlags.ELLIPSIS));

    fs.applyDirective(.{ .flag = OptionFlags.ELLIPSIS, .enable = false });
    try std.testing.expect(!fs.isSet(OptionFlags.ELLIPSIS));
}

test "FlagSet_comparisonFlags" {
    var fs = FlagSet.initWith(OptionFlags.ELLIPSIS | OptionFlags.REPORT_UDIFF);

    try std.testing.expectEqual(OptionFlags.ELLIPSIS, fs.comparisonFlags());
}

test "FlagSet_reportingFlags" {
    var fs = FlagSet.initWith(OptionFlags.ELLIPSIS | OptionFlags.REPORT_UDIFF);

    try std.testing.expectEqual(OptionFlags.REPORT_UDIFF, fs.reportingFlags());
}

test "FlagSet_format" {
    var fs = FlagSet.initWith(OptionFlags.ELLIPSIS | OptionFlags.SKIP);

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{fs});

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "ELLIPSIS") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SKIP") != null);
}

test "FlagSet_format_empty" {
    const fs = FlagSet.init();

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{fs});

    const output = stream.getWritten();
    try std.testing.expectEqualStrings("(none)", output);
}

test "CustomFlags_register" {
    var custom = CustomFlags.init(std.testing.allocator);
    defer custom.deinit();

    const flag1 = try custom.register("MY_FLAG");
    const flag2 = try custom.register("OTHER_FLAG");

    try std.testing.expect(flag1 != flag2);
    try std.testing.expectEqual(flag1, custom.get("MY_FLAG").?);
    try std.testing.expectEqual(flag2, custom.get("OTHER_FLAG").?);
}

test "COMPARISON_FLAGS_contains" {
    try std.testing.expect((OptionFlags.COMPARISON_FLAGS & OptionFlags.ELLIPSIS) != 0);
    try std.testing.expect((OptionFlags.COMPARISON_FLAGS & OptionFlags.NORMALIZE_WHITESPACE) != 0);
    try std.testing.expect((OptionFlags.COMPARISON_FLAGS & OptionFlags.SKIP) == 0);
}

test "REPORTING_FLAGS_contains" {
    try std.testing.expect((OptionFlags.REPORTING_FLAGS & OptionFlags.REPORT_UDIFF) != 0);
    try std.testing.expect((OptionFlags.REPORTING_FLAGS & OptionFlags.ELLIPSIS) == 0);
}
