//! Python 'optparse' module - Command-line option parsing library
//!
//! A powerful, extensible, and easy-to-use option parser.
//! Note: In Python 3.2+, argparse is preferred over optparse.
//!
//! Mirrors: CPython Lib/optparse.py

const std = @import("std");

// ============================================================================
// Option Actions
// ============================================================================

/// Action to take when option is encountered
pub const OptionAction = enum {
    store, // Store value in dest
    store_const, // Store a constant value
    store_true, // Store True
    store_false, // Store False
    append, // Append to a list
    append_const, // Append a constant to a list
    count, // Increment a counter
    callback, // Call a callback function
    help, // Print help and exit
    version, // Print version and exit
};

/// Type of option argument
pub const OptionType = enum {
    string,
    int,
    long,
    float,
    complex,
    choice,
};

// ============================================================================
// Option
// ============================================================================

/// Represents a command-line option
pub const Option = struct {
    const Self = @This();

    // Option strings (e.g., "-f", "--file")
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,

    // Configuration
    action: OptionAction = .store,
    option_type: OptionType = .string,
    dest: ?[]const u8 = null,
    default: ?[]const u8 = null,
    const_value: ?[]const u8 = null,
    nargs: usize = 1,
    choices: ?[]const []const u8 = null,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    callback: ?*const fn (*OptionParser, *Option, []const u8, *Values) void = null,

    /// Create an option
    pub fn init(short: ?[]const u8, long: ?[]const u8) Self {
        return .{
            .short = short,
            .long = long,
        };
    }

    /// Get the destination name
    pub fn getDest(self: Self) []const u8 {
        if (self.dest) |d| return d;

        // Derive from long option
        if (self.long) |l| {
            if (std.mem.startsWith(u8, l, "--")) {
                return l[2..];
            }
        }

        // Derive from short option
        if (self.short) |s| {
            if (std.mem.startsWith(u8, s, "-")) {
                return s[1..];
            }
        }

        return "";
    }

    /// Check if a string matches this option
    pub fn matches(self: Self, arg: []const u8) bool {
        if (self.short) |s| {
            if (std.mem.eql(u8, arg, s)) return true;
        }
        if (self.long) |l| {
            if (std.mem.eql(u8, arg, l)) return true;
            // Check for --opt=value format
            if (std.mem.startsWith(u8, arg, l) and
                arg.len > l.len and arg[l.len] == '=')
            {
                return true;
            }
        }
        return false;
    }

    /// Get metavar for help display
    pub fn getMetavar(self: Self) []const u8 {
        if (self.metavar) |m| return m;
        if (self.choices) |_| return "CHOICE";

        return switch (self.option_type) {
            .string => "STRING",
            .int, .long => "INT",
            .float => "FLOAT",
            .complex => "COMPLEX",
            .choice => "CHOICE",
        };
    }
};

// ============================================================================
// Values - Container for parsed option values
// ============================================================================

/// Container for parsed option values
pub const Values = struct {
    const Self = @This();
    const ValueMap = std.StringHashMap(Value);

    allocator: std.mem.Allocator,
    values: ValueMap,

    pub const Value = union(enum) {
        string: []const u8,
        string_list: std.ArrayList([]const u8),
        boolean: bool,
        integer: i64,
        float: f64,
        count: u32,
        none,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = ValueMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string_list => |*list| list.deinit(),
                else => {},
            }
        }
        self.values.deinit();
    }

    pub fn set(self: *Self, key: []const u8, value: Value) !void {
        try self.values.put(key, value);
    }

    pub fn get(self: Self, key: []const u8) ?Value {
        return self.values.get(key);
    }

    pub fn getString(self: Self, key: []const u8) ?[]const u8 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: Self, key: []const u8) bool {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => false,
            };
        }
        return false;
    }

    pub fn getInt(self: Self, key: []const u8) ?i64 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .integer => |i| i,
                .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
                else => null,
            };
        }
        return null;
    }

    pub fn getCount(self: Self, key: []const u8) u32 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .count => |c| c,
                else => 0,
            };
        }
        return 0;
    }

    pub fn has(self: Self, key: []const u8) bool {
        return self.values.contains(key);
    }
};

// ============================================================================
// OptionGroup - Group of related options
// ============================================================================

/// Group of related options for help display
pub const OptionGroup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parser: *OptionParser,
    title: []const u8,
    description: ?[]const u8,
    options: std.ArrayList(Option),

    pub fn init(allocator: std.mem.Allocator, parser: *OptionParser, title: []const u8) Self {
        return .{
            .allocator = allocator,
            .parser = parser,
            .title = title,
            .description = null,
            .options = std.ArrayList(Option).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.options.deinit();
    }

    pub fn addOption(self: *Self, option: Option) !void {
        try self.options.append(option);
    }
};

// ============================================================================
// OptionParser
// ============================================================================

/// Command-line option parser
pub const OptionParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Configuration
    usage: ?[]const u8,
    description: ?[]const u8,
    epilog: ?[]const u8,
    version: ?[]const u8,
    prog: ?[]const u8,
    add_help_option: bool,

    // Options and groups
    options: std.ArrayList(Option),
    groups: std.ArrayList(OptionGroup),

    // Error handling
    on_error: ErrorBehavior = .exit,

    pub const ErrorBehavior = enum {
        exit,
        raise,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        var parser = Self{
            .allocator = allocator,
            .usage = null,
            .description = null,
            .epilog = null,
            .version = null,
            .prog = null,
            .add_help_option = true,
            .options = std.ArrayList(Option).init(allocator),
            .groups = std.ArrayList(OptionGroup).init(allocator),
        };

        // Add default help option
        parser.addDefaultOptions() catch {};

        return parser;
    }

    pub fn initWithUsage(allocator: std.mem.Allocator, usage: []const u8) Self {
        var parser = Self.init(allocator);
        parser.usage = usage;
        return parser;
    }

    pub fn deinit(self: *Self) void {
        self.options.deinit();
        for (self.groups.items) |*group| {
            group.deinit();
        }
        self.groups.deinit();
    }

    fn addDefaultOptions(self: *Self) !void {
        if (self.add_help_option) {
            try self.options.append(.{
                .short = "-h",
                .long = "--help",
                .action = .help,
                .help = "show this help message and exit",
            });
        }
    }

    /// Set the usage string
    pub fn setUsage(self: *Self, usage: []const u8) void {
        self.usage = usage;
    }

    /// Set the description
    pub fn setDescription(self: *Self, description: []const u8) void {
        self.description = description;
    }

    /// Add an option
    pub fn addOption(self: *Self, option: Option) !void {
        try self.options.append(option);
    }

    /// Add option using builder pattern
    pub fn addOptionEx(
        self: *Self,
        short: ?[]const u8,
        long: ?[]const u8,
        config: struct {
            action: OptionAction = .store,
            option_type: OptionType = .string,
            dest: ?[]const u8 = null,
            default: ?[]const u8 = null,
            const_value: ?[]const u8 = null,
            nargs: usize = 1,
            choices: ?[]const []const u8 = null,
            help: ?[]const u8 = null,
            metavar: ?[]const u8 = null,
        },
    ) !void {
        try self.options.append(.{
            .short = short,
            .long = long,
            .action = config.action,
            .option_type = config.option_type,
            .dest = config.dest,
            .default = config.default,
            .const_value = config.const_value,
            .nargs = config.nargs,
            .choices = config.choices,
            .help = config.help,
            .metavar = config.metavar,
        });
    }

    /// Add an option group
    pub fn addOptionGroup(self: *Self, group: OptionGroup) !void {
        try self.groups.append(group);
    }

    /// Create a new option group
    pub fn createOptionGroup(self: *Self, title: []const u8) OptionGroup {
        return OptionGroup.init(self.allocator, self, title);
    }

    /// Parse command-line arguments
    pub fn parseArgs(self: *Self, args: []const []const u8) !struct {
        values: Values,
        args: []const []const u8,
    } {
        var values = Values.init(self.allocator);
        errdefer values.deinit();

        var remaining = std.ArrayList([]const u8).init(self.allocator);
        errdefer remaining.deinit();

        // Set defaults
        for (self.options.items) |opt| {
            if (opt.default) |def| {
                try values.set(opt.getDest(), .{ .string = def });
            }
            switch (opt.action) {
                .store_true => try values.set(opt.getDest(), .{ .boolean = false }),
                .store_false => try values.set(opt.getDest(), .{ .boolean = true }),
                .count => try values.set(opt.getDest(), .{ .count = 0 }),
                else => {},
            }
        }

        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            // Check for end of options
            if (std.mem.eql(u8, arg, "--")) {
                i += 1;
                while (i < args.len) : (i += 1) {
                    try remaining.append(args[i]);
                }
                break;
            }

            // Check if it's an option
            if (std.mem.startsWith(u8, arg, "-")) {
                const opt = self.findOption(arg);
                if (opt == null) {
                    if (self.on_error == .exit) {
                        self.printUsageError(arg);
                        return error.UnknownOption;
                    }
                    return error.UnknownOption;
                }

                const option = opt.?;
                i = try self.processOption(option, args, i, &values);
            } else {
                try remaining.append(arg);
            }
        }

        return .{
            .values = values,
            .args = try remaining.toOwnedSlice(),
        };
    }

    fn findOption(self: *Self, arg: []const u8) ?Option {
        // Check main options
        for (self.options.items) |opt| {
            if (opt.matches(arg)) return opt;
        }

        // Check groups
        for (self.groups.items) |group| {
            for (group.options.items) |opt| {
                if (opt.matches(arg)) return opt;
            }
        }

        return null;
    }

    fn processOption(
        self: *Self,
        option: Option,
        args: []const []const u8,
        idx: usize,
        values: *Values,
    ) !usize {
        var i = idx;
        const arg = args[i];

        // Extract value from --opt=value format
        var embedded_value: ?[]const u8 = null;
        if (option.long) |l| {
            if (std.mem.startsWith(u8, arg, l) and arg.len > l.len and arg[l.len] == '=') {
                embedded_value = arg[l.len + 1 ..];
            }
        }

        switch (option.action) {
            .store => {
                if (embedded_value) |v| {
                    try values.set(option.getDest(), .{ .string = v });
                } else if (i + 1 < args.len) {
                    i += 1;
                    try values.set(option.getDest(), .{ .string = args[i] });
                } else {
                    return error.MissingArgument;
                }
            },
            .store_const => {
                if (option.const_value) |cv| {
                    try values.set(option.getDest(), .{ .string = cv });
                }
            },
            .store_true => {
                try values.set(option.getDest(), .{ .boolean = true });
            },
            .store_false => {
                try values.set(option.getDest(), .{ .boolean = false });
            },
            .count => {
                const current = values.getCount(option.getDest());
                try values.set(option.getDest(), .{ .count = current + 1 });
            },
            .append => {
                // Would need list handling
                if (i + 1 < args.len) {
                    i += 1;
                    try values.set(option.getDest(), .{ .string = args[i] });
                }
            },
            .help => {
                self.printHelp();
                return error.HelpRequested;
            },
            .version => {
                self.printVersion();
                return error.VersionRequested;
            },
            else => {},
        }

        return i;
    }

    fn printUsageError(self: *Self, arg: []const u8) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("error: no such option: {s}\n", .{arg}) catch {};
        self.printUsage();
    }

    /// Print usage information
    pub fn printUsage(self: *Self) void {
        const stdout = std.io.getStdOut().writer();

        stdout.print("Usage: {s}", .{self.prog orelse "program"}) catch {};

        if (self.usage) |u| {
            stdout.print(" {s}", .{u}) catch {};
        } else {
            stdout.print(" [options]", .{}) catch {};
        }

        stdout.print("\n", .{}) catch {};
    }

    /// Print help message
    pub fn printHelp(self: *Self) void {
        const stdout = std.io.getStdOut().writer();

        self.printUsage();

        if (self.description) |desc| {
            stdout.print("\n{s}\n", .{desc}) catch {};
        }

        // Print options
        stdout.print("\nOptions:\n", .{}) catch {};
        for (self.options.items) |opt| {
            self.printOption(stdout, opt) catch {};
        }

        // Print groups
        for (self.groups.items) |group| {
            stdout.print("\n{s}:\n", .{group.title}) catch {};
            if (group.description) |desc| {
                stdout.print("  {s}\n", .{desc}) catch {};
            }
            for (group.options.items) |opt| {
                self.printOption(stdout, opt) catch {};
            }
        }

        if (self.epilog) |ep| {
            stdout.print("\n{s}\n", .{ep}) catch {};
        }
    }

    fn printOption(self: *Self, writer: anytype, opt: Option) !void {
        _ = self;
        try writer.print("  ", .{});

        var name_buf: [64]u8 = undefined;
        var name_len: usize = 0;

        if (opt.short) |s| {
            @memcpy(name_buf[name_len .. name_len + s.len], s);
            name_len += s.len;
        }

        if (opt.long) |l| {
            if (opt.short != null) {
                name_buf[name_len] = ',';
                name_buf[name_len + 1] = ' ';
                name_len += 2;
            }
            @memcpy(name_buf[name_len .. name_len + l.len], l);
            name_len += l.len;
        }

        // Add metavar for options that take arguments
        if (opt.action == .store or opt.action == .append) {
            const mv = opt.getMetavar();
            name_buf[name_len] = ' ';
            name_len += 1;
            @memcpy(name_buf[name_len .. name_len + mv.len], mv);
            name_len += mv.len;
        }

        try writer.print("{s: <28}", .{name_buf[0..name_len]});

        if (opt.help) |h| {
            try writer.print("{s}", .{h});
        }

        try writer.print("\n", .{});
    }

    /// Print version information
    pub fn printVersion(self: *Self) void {
        const stdout = std.io.getStdOut().writer();
        if (self.version) |v| {
            stdout.print("{s}\n", .{v}) catch {};
        }
    }

    /// Disable interspersed arguments
    pub fn disableInterspersedArgs(self: *Self) void {
        _ = self;
        // Would affect parsing behavior
    }

    /// Enable interspersed arguments
    pub fn enableInterspersedArgs(self: *Self) void {
        _ = self;
        // Would affect parsing behavior
    }
};

// ============================================================================
// Errors
// ============================================================================

pub const OptionError = error{
    UnknownOption,
    MissingArgument,
    InvalidChoice,
    InvalidType,
    AmbiguousOption,
    HelpRequested,
    VersionRequested,
};

/// Exception for bad option values
pub const OptionValueError = error{
    BadValue,
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a parser with common defaults
pub fn createParser(
    allocator: std.mem.Allocator,
    usage: ?[]const u8,
    description: ?[]const u8,
) OptionParser {
    var parser = OptionParser.init(allocator);
    if (usage) |u| parser.usage = u;
    if (description) |d| parser.description = d;
    return parser;
}

// ============================================================================
// Tests
// ============================================================================

test "Option init" {
    const opt = Option.init("-v", "--verbose");
    try std.testing.expectEqualStrings("-v", opt.short.?);
    try std.testing.expectEqualStrings("--verbose", opt.long.?);
}

test "Option getDest" {
    const opt1 = Option.init("-v", "--verbose");
    try std.testing.expectEqualStrings("verbose", opt1.getDest());

    const opt2 = Option.init("-n", null);
    try std.testing.expectEqualStrings("n", opt2.getDest());

    var opt3 = Option.init("-x", "--extra");
    opt3.dest = "custom";
    try std.testing.expectEqualStrings("custom", opt3.getDest());
}

test "Option matches" {
    const opt = Option.init("-v", "--verbose");
    try std.testing.expect(opt.matches("-v"));
    try std.testing.expect(opt.matches("--verbose"));
    try std.testing.expect(opt.matches("--verbose=yes"));
    try std.testing.expect(!opt.matches("-x"));
}

test "Values" {
    const allocator = std.testing.allocator;
    var values = Values.init(allocator);
    defer values.deinit();

    try values.set("name", .{ .string = "test" });
    try values.set("verbose", .{ .boolean = true });
    try values.set("count", .{ .count = 3 });

    try std.testing.expectEqualStrings("test", values.getString("name").?);
    try std.testing.expect(values.getBool("verbose"));
    try std.testing.expectEqual(@as(u32, 3), values.getCount("count"));
    try std.testing.expect(values.has("name"));
    try std.testing.expect(!values.has("missing"));
}

test "OptionParser init" {
    const allocator = std.testing.allocator;
    var parser = OptionParser.init(allocator);
    defer parser.deinit();

    try std.testing.expect(parser.add_help_option);
    try std.testing.expectEqual(@as(usize, 1), parser.options.items.len); // -h/--help
}

test "OptionParser addOption" {
    const allocator = std.testing.allocator;
    var parser = OptionParser.init(allocator);
    defer parser.deinit();

    try parser.addOption(.{
        .short = "-v",
        .long = "--verbose",
        .action = .store_true,
        .help = "Enable verbose output",
    });

    try std.testing.expectEqual(@as(usize, 2), parser.options.items.len);
}

test "OptionGroup" {
    const allocator = std.testing.allocator;
    var parser = OptionParser.init(allocator);
    defer parser.deinit();

    var group = parser.createOptionGroup("Debug options");
    try group.addOption(.{
        .short = "-d",
        .long = "--debug",
        .action = .store_true,
    });

    try std.testing.expectEqual(@as(usize, 1), group.options.items.len);
    group.deinit();
}

test "createParser" {
    const allocator = std.testing.allocator;
    var parser = createParser(allocator, "[options] file...", "Process files");
    defer parser.deinit();

    try std.testing.expectEqualStrings("[options] file...", parser.usage.?);
    try std.testing.expectEqualStrings("Process files", parser.description.?);
}
