//! CPython source: Lib/argparse.py
//!
//! Parser for command-line options, arguments and sub-commands.
//!
//! Mirrors: CPython Lib/argparse.py

const std = @import("std");

// ============================================================================
// Argument Types
// ============================================================================

/// Argument action types
pub const Action = enum {
    store, // Store the value (default)
    store_const, // Store a constant value
    store_true, // Store true
    store_false, // Store false
    append, // Append to a list
    append_const, // Append a constant to a list
    count, // Count occurrences
    help, // Print help and exit
    version, // Print version and exit
};

/// Argument nargs specification
pub const Nargs = union(enum) {
    exact: u32, // Exact number of arguments
    optional, // ? - zero or one
    zero_or_more, // * - zero or more
    one_or_more, // + - one or more
    remainder, // Remaining arguments
};

/// Parsed argument value
pub const ArgValue = union(enum) {
    string: []const u8,
    strings: []const []const u8,
    boolean: bool,
    integer: i64,
    float: f64,
    count: u32,
    none,
};

// ============================================================================
// Argument Definition
// ============================================================================

/// Definition of a command-line argument
pub const Argument = struct {
    const Self = @This();

    // Names (short and/or long)
    names: []const []const u8,

    // Configuration
    action: Action = .store,
    nargs: ?Nargs = null,
    const_value: ?[]const u8 = null,
    default: ?[]const u8 = null,
    type_name: []const u8 = "string",
    choices: ?[]const []const u8 = null,
    required: bool = false,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    dest: ?[]const u8 = null,

    /// Check if this is a positional argument
    pub fn isPositional(self: Self) bool {
        if (self.names.len == 0) return true;
        return !std.mem.startsWith(u8, self.names[0], "-");
    }

    /// Get the destination name for this argument
    pub fn getDest(self: Self) []const u8 {
        if (self.dest) |d| return d;
        if (self.names.len == 0) return "";

        // Find the long option name, or use the first one
        for (self.names) |name| {
            if (std.mem.startsWith(u8, name, "--")) {
                return name[2..];
            }
        }

        // Use short option without dash
        if (std.mem.startsWith(u8, self.names[0], "-")) {
            return self.names[0][1..];
        }

        return self.names[0];
    }
};

// ============================================================================
// Argument Parser
// ============================================================================

/// Command-line argument parser
pub const ArgumentParser = struct {
    const Self = @This();
    const ArgList = std.ArrayList(Argument);
    const ValueMap = std.StringHashMap(ArgValue);

    allocator: std.mem.Allocator,

    // Parser configuration
    prog: ?[]const u8 = null,
    usage: ?[]const u8 = null,
    description: ?[]const u8 = null,
    epilog: ?[]const u8 = null,
    add_help: bool = true,
    allow_abbrev: bool = true,

    // Registered arguments
    arguments: ArgList,

    // Subparsers
    subparsers: ?*SubparserGroup = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        var parser = Self{
            .allocator = allocator,
            .arguments = ArgList.init(allocator),
        };

        // Add help argument by default
        if (parser.add_help) {
            parser.addArgument(&.{ "-h", "--help" }, .{
                .action = .help,
                .help = "show this help message and exit",
            }) catch {};
        }

        return parser;
    }

    pub fn deinit(self: *Self) void {
        self.arguments.deinit();
    }

    /// Add an argument to the parser
    pub fn addArgument(self: *Self, names: []const []const u8, options: ArgumentOptions) !void {
        try self.arguments.append(.{
            .names = names,
            .action = options.action,
            .nargs = options.nargs,
            .const_value = options.const_value,
            .default = options.default,
            .type_name = options.type_name,
            .choices = options.choices,
            .required = options.required,
            .help = options.help,
            .metavar = options.metavar,
            .dest = options.dest,
        });
    }

    /// Parse command-line arguments
    pub fn parseArgs(self: *Self, args: ?[]const []const u8) !ParseResult {
        const argv = args orelse getSystemArgs(self.allocator);

        var result = ParseResult.init(self.allocator);
        var i: usize = 0;

        // Set defaults
        for (self.arguments.items) |arg| {
            if (arg.default) |def| {
                try result.values.put(arg.getDest(), .{ .string = def });
            } else {
                switch (arg.action) {
                    .store_true => try result.values.put(arg.getDest(), .{ .boolean = false }),
                    .store_false => try result.values.put(arg.getDest(), .{ .boolean = true }),
                    .count => try result.values.put(arg.getDest(), .{ .count = 0 }),
                    else => {},
                }
            }
        }

        // Process positional arguments index
        var positional_idx: usize = 0;

        while (i < argv.len) {
            const arg_str = argv[i];

            if (std.mem.startsWith(u8, arg_str, "-")) {
                // Optional argument
                const matched_arg = self.findArgument(arg_str);
                if (matched_arg) |arg| {
                    switch (arg.action) {
                        .store => {
                            if (i + 1 < argv.len) {
                                i += 1;
                                try result.values.put(arg.getDest(), .{ .string = argv[i] });
                            } else {
                                return error.MissingValue;
                            }
                        },
                        .store_const => {
                            if (arg.const_value) |cv| {
                                try result.values.put(arg.getDest(), .{ .string = cv });
                            }
                        },
                        .store_true => {
                            try result.values.put(arg.getDest(), .{ .boolean = true });
                        },
                        .store_false => {
                            try result.values.put(arg.getDest(), .{ .boolean = false });
                        },
                        .count => {
                            const current = result.values.get(arg.getDest()) orelse .{ .count = 0 };
                            const new_count = switch (current) {
                                .count => |c| c + 1,
                                else => 1,
                            };
                            try result.values.put(arg.getDest(), .{ .count = new_count });
                        },
                        .help => {
                            self.printHelp();
                            return error.HelpRequested;
                        },
                        .version => {
                            return error.VersionRequested;
                        },
                        .append, .append_const => {
                            // Would need list handling
                        },
                    }
                } else {
                    return error.UnrecognizedArgument;
                }
            } else {
                // Positional argument
                const positionals = self.getPositionalArgs();
                if (positional_idx < positionals.len) {
                    const arg = positionals[positional_idx];
                    try result.values.put(arg.getDest(), .{ .string = arg_str });
                    positional_idx += 1;
                } else {
                    try result.remaining.append(arg_str);
                }
            }

            i += 1;
        }

        // Check required arguments
        for (self.arguments.items) |arg| {
            if (arg.required and !result.values.contains(arg.getDest())) {
                return error.RequiredArgumentMissing;
            }
        }

        return result;
    }

    /// Find an argument by name
    fn findArgument(self: *Self, name: []const u8) ?Argument {
        // Handle --arg=value syntax
        var search_name = name;
        if (std.mem.indexOf(u8, name, "=")) |eq_pos| {
            search_name = name[0..eq_pos];
        }

        for (self.arguments.items) |arg| {
            for (arg.names) |arg_name| {
                if (std.mem.eql(u8, arg_name, search_name)) {
                    return arg;
                }
            }
        }
        return null;
    }

    /// Get positional arguments
    fn getPositionalArgs(self: *Self) []const Argument {
        var count: usize = 0;
        for (self.arguments.items) |arg| {
            if (arg.isPositional()) count += 1;
        }

        var result: [16]Argument = undefined;
        var idx: usize = 0;
        for (self.arguments.items) |arg| {
            if (arg.isPositional() and idx < 16) {
                result[idx] = arg;
                idx += 1;
            }
        }

        return result[0..idx];
    }

    /// Print help message
    pub fn printHelp(self: *Self) void {
        const writer = std.io.getStdOut().writer();

        // Usage
        writer.print("usage: {s}", .{self.prog orelse "prog"}) catch {};
        for (self.arguments.items) |arg| {
            if (!arg.isPositional()) {
                writer.print(" [{s}]", .{arg.names[0]}) catch {};
            }
        }
        for (self.arguments.items) |arg| {
            if (arg.isPositional()) {
                writer.print(" {s}", .{arg.getDest()}) catch {};
            }
        }
        writer.print("\n\n", .{}) catch {};

        // Description
        if (self.description) |desc| {
            writer.print("{s}\n\n", .{desc}) catch {};
        }

        // Positional arguments
        var has_positional = false;
        for (self.arguments.items) |arg| {
            if (arg.isPositional()) {
                if (!has_positional) {
                    writer.print("positional arguments:\n", .{}) catch {};
                    has_positional = true;
                }
                writer.print("  {s: <20}", .{arg.getDest()}) catch {};
                if (arg.help) |h| {
                    writer.print(" {s}", .{h}) catch {};
                }
                writer.print("\n", .{}) catch {};
            }
        }

        // Optional arguments
        writer.print("\noptions:\n", .{}) catch {};
        for (self.arguments.items) |arg| {
            if (!arg.isPositional()) {
                var name_buf: [64]u8 = undefined;
                var name_len: usize = 0;
                for (arg.names, 0..) |name, j| {
                    if (j > 0) {
                        name_buf[name_len] = ',';
                        name_buf[name_len + 1] = ' ';
                        name_len += 2;
                    }
                    @memcpy(name_buf[name_len .. name_len + name.len], name);
                    name_len += name.len;
                }
                writer.print("  {s: <20}", .{name_buf[0..name_len]}) catch {};
                if (arg.help) |h| {
                    writer.print(" {s}", .{h}) catch {};
                }
                writer.print("\n", .{}) catch {};
            }
        }

        // Epilog
        if (self.epilog) |ep| {
            writer.print("\n{s}\n", .{ep}) catch {};
        }
    }

    /// Format help as string
    pub fn formatHelp(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice("usage: ");
        try result.appendSlice(self.prog orelse "prog");

        for (self.arguments.items) |arg| {
            if (!arg.isPositional()) {
                try result.appendSlice(" [");
                try result.appendSlice(arg.names[0]);
                try result.append(']');
            }
        }

        try result.append('\n');

        if (self.description) |desc| {
            try result.append('\n');
            try result.appendSlice(desc);
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }
};

/// Options for adding an argument
pub const ArgumentOptions = struct {
    action: Action = .store,
    nargs: ?Nargs = null,
    const_value: ?[]const u8 = null,
    default: ?[]const u8 = null,
    type_name: []const u8 = "string",
    choices: ?[]const []const u8 = null,
    required: bool = false,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    dest: ?[]const u8 = null,
};

/// Result of parsing arguments
pub const ParseResult = struct {
    const Self = @This();
    const ValueMap = std.StringHashMap(ArgValue);
    const StringList = std.ArrayList([]const u8);

    allocator: std.mem.Allocator,
    values: ValueMap,
    remaining: StringList,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = ValueMap.init(allocator),
            .remaining = StringList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
        self.remaining.deinit();
    }

    /// Get a string argument
    pub fn getString(self: Self, name: []const u8) ?[]const u8 {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    /// Get a boolean argument
    pub fn getBool(self: Self, name: []const u8) bool {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => false,
            };
        }
        return false;
    }

    /// Get a count argument
    pub fn getCount(self: Self, name: []const u8) u32 {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .count => |c| c,
                else => 0,
            };
        }
        return 0;
    }

    /// Get an integer argument
    pub fn getInt(self: Self, name: []const u8) ?i64 {
        if (self.getString(name)) |s| {
            return std.fmt.parseInt(i64, s, 10) catch null;
        }
        return null;
    }

    /// Check if an argument was provided
    pub fn has(self: Self, name: []const u8) bool {
        return self.values.contains(name);
    }
};

// ============================================================================
// Subparsers
// ============================================================================

/// Group of subparsers
pub const SubparserGroup = struct {
    const Self = @This();
    const ParserMap = std.StringHashMap(*ArgumentParser);

    allocator: std.mem.Allocator,
    parsers: ParserMap,
    dest: []const u8,
    title: []const u8 = "subcommands",
    description: ?[]const u8 = null,
    required: bool = true,

    pub fn init(allocator: std.mem.Allocator, dest: []const u8) Self {
        return .{
            .allocator = allocator,
            .parsers = ParserMap.init(allocator),
            .dest = dest,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parsers.deinit();
    }

    pub fn addParser(self: *Self, name: []const u8, parser: *ArgumentParser) !void {
        try self.parsers.put(name, parser);
    }

    pub fn getParser(self: Self, name: []const u8) ?*ArgumentParser {
        return self.parsers.get(name);
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Get system command-line arguments
fn getSystemArgs(allocator: std.mem.Allocator) []const []const u8 {
    _ = allocator;
    // In real implementation, would use std.process.args()
    return &[_][]const u8{};
}

/// Type conversion error
pub const ArgumentTypeError = error{
    InvalidValue,
    OutOfRange,
};

/// Convert string to integer
pub fn intType(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 10) catch error.InvalidValue;
}

/// Convert string to float
pub fn floatType(s: []const u8) !f64 {
    return std.fmt.parseFloat(f64, s) catch error.InvalidValue;
}

// ============================================================================
// File Type
// ============================================================================

/// File type for argument parsing
pub const FileType = struct {
    mode: []const u8,

    pub fn init(mode: []const u8) FileType {
        return .{ .mode = mode };
    }

    pub fn open(self: FileType, path: []const u8) !std.fs.File {
        _ = self;
        return std.fs.cwd().openFile(path, .{});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ArgumentParser basic" {
    const allocator = std.testing.allocator;

    var parser = ArgumentParser.init(allocator);
    defer parser.deinit();

    try parser.addArgument(&.{"--verbose"}, .{
        .action = .store_true,
        .help = "Enable verbose output",
    });

    try parser.addArgument(&.{ "-n", "--number" }, .{
        .action = .store,
        .help = "A number",
    });

    try std.testing.expectEqual(@as(usize, 3), parser.arguments.items.len); // includes -h/--help
}

test "Argument.getDest" {
    const arg1 = Argument{
        .names = &.{ "-v", "--verbose" },
    };
    try std.testing.expectEqualStrings("verbose", arg1.getDest());

    const arg2 = Argument{
        .names = &.{"-n"},
    };
    try std.testing.expectEqualStrings("n", arg2.getDest());

    const arg3 = Argument{
        .names = &.{"filename"},
    };
    try std.testing.expectEqualStrings("filename", arg3.getDest());

    const arg4 = Argument{
        .names = &.{"-x"},
        .dest = "custom_dest",
    };
    try std.testing.expectEqualStrings("custom_dest", arg4.getDest());
}

test "Argument.isPositional" {
    const pos = Argument{ .names = &.{"filename"} };
    try std.testing.expect(pos.isPositional());

    const opt = Argument{ .names = &.{"--file"} };
    try std.testing.expect(!opt.isPositional());

    const short = Argument{ .names = &.{"-f"} };
    try std.testing.expect(!short.isPositional());
}

test "ParseResult" {
    const allocator = std.testing.allocator;

    var result = ParseResult.init(allocator);
    defer result.deinit();

    try result.values.put("verbose", .{ .boolean = true });
    try result.values.put("count", .{ .count = 3 });
    try result.values.put("name", .{ .string = "test" });

    try std.testing.expect(result.getBool("verbose"));
    try std.testing.expectEqual(@as(u32, 3), result.getCount("count"));
    try std.testing.expectEqualStrings("test", result.getString("name").?);
    try std.testing.expect(result.has("verbose"));
    try std.testing.expect(!result.has("missing"));
}

test "intType" {
    try std.testing.expectEqual(@as(i64, 42), try intType("42"));
    try std.testing.expectEqual(@as(i64, -100), try intType("-100"));
    try std.testing.expectError(error.InvalidValue, intType("not_a_number"));
}

test "floatType" {
    const f = try floatType("3.14");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), f, 0.001);
    try std.testing.expectError(error.InvalidValue, floatType("not_a_float"));
}
