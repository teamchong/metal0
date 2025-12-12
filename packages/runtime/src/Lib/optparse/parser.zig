//! CPython source: Lib/optparse.py
//!
//! Command-line option parser.
//! Mirrors: CPython Lib/optparse.py

const std = @import("std");
const types = @import("types.zig");
const option_mod = @import("option.zig");
const option_group_mod = @import("option_group.zig");
const values_mod = @import("values.zig");

const OptionAction = types.OptionAction;
const OptionType = types.OptionType;
const ErrorBehavior = types.ErrorBehavior;
const Option = option_mod.Option;
const OptionGroup = option_group_mod.OptionGroup;
const Values = values_mod.Values;

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

    // Interspersed arguments flag (POSIX-style when false)
    allow_interspersed_args: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        var parser = Self{
            .allocator = allocator,
            .usage = null,
            .description = null,
            .epilog = null,
            .version = null,
            .prog = null,
            .add_help_option = true,
            .options = .{},
            .groups = .{},
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
        self.options.deinit(self.allocator);
        for (self.groups.items) |*group| {
            group.deinit();
        }
        self.groups.deinit(self.allocator);
    }

    fn addDefaultOptions(self: *Self) !void {
        if (self.add_help_option) {
            try self.options.append(self.allocator, .{
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
    pub fn addOption(self: *Self, opt: Option) !void {
        try self.options.append(self.allocator, opt);
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
        try self.options.append(self.allocator, .{
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
        try self.groups.append(self.allocator, group);
    }

    /// Create a new option group
    pub fn createOptionGroup(self: *Self, title: []const u8) OptionGroup {
        return OptionGroup.init(
            self.allocator,
            @ptrCast(self),
            title,
        );
    }

    /// Parse command-line arguments
    pub fn parseArgs(self: *Self, args: []const []const u8) !struct {
        values: Values,
        args: []const []const u8,
    } {
        var vals = Values.init(self.allocator);
        errdefer vals.deinit();

        var remaining: std.ArrayList([]const u8) = .{};
        errdefer remaining.deinit(self.allocator);

        // Set defaults
        for (self.options.items) |opt| {
            if (opt.default) |def| {
                try vals.set(opt.getDest(), .{ .string = def });
            }
            switch (opt.action) {
                .store_true => try vals.set(opt.getDest(), .{ .boolean = false }),
                .store_false => try vals.set(opt.getDest(), .{ .boolean = true }),
                .count => try vals.set(opt.getDest(), .{ .count = 0 }),
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
                    try remaining.append(self.allocator, args[i]);
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

                const option_found = opt.?;
                i = try self.processOption(option_found, args, i, &vals);
            } else {
                try remaining.append(self.allocator, arg);
            }
        }

        return .{
            .values = vals,
            .args = try remaining.toOwnedSlice(self.allocator),
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
        opt: Option,
        args: []const []const u8,
        idx: usize,
        vals: *Values,
    ) !usize {
        var i = idx;
        const arg = args[i];

        // Extract value from --opt=value format
        var embedded_value: ?[]const u8 = null;
        if (opt.long) |l| {
            if (std.mem.startsWith(u8, arg, l) and arg.len > l.len and arg[l.len] == '=') {
                embedded_value = arg[l.len + 1 ..];
            }
        }

        switch (opt.action) {
            .store => {
                if (embedded_value) |v| {
                    try vals.set(opt.getDest(), .{ .string = v });
                } else if (i + 1 < args.len) {
                    i += 1;
                    try vals.set(opt.getDest(), .{ .string = args[i] });
                } else {
                    return error.MissingArgument;
                }
            },
            .store_const => {
                if (opt.const_value) |cv| {
                    try vals.set(opt.getDest(), .{ .string = cv });
                }
            },
            .store_true => {
                try vals.set(opt.getDest(), .{ .boolean = true });
            },
            .store_false => {
                try vals.set(opt.getDest(), .{ .boolean = false });
            },
            .count => {
                const current = vals.getCount(opt.getDest());
                try vals.set(opt.getDest(), .{ .count = current + 1 });
            },
            .append => {
                // Append value to a list
                if (i + 1 < args.len) {
                    i += 1;
                    const dest = opt.getDest();

                    // Get or create the list
                    if (vals.values.getPtr(dest)) |existing| {
                        switch (existing.*) {
                            .string_list => |*list| {
                                try list.append(vals.allocator, args[i]);
                            },
                            else => {
                                // Convert to list
                                var list: std.ArrayList([]const u8) = .{};
                                try list.append(vals.allocator, args[i]);
                                try vals.set(dest, .{ .string_list = list });
                            },
                        }
                    } else {
                        // Create new list
                        var list: std.ArrayList([]const u8) = .{};
                        try list.append(vals.allocator, args[i]);
                        try vals.set(dest, .{ .string_list = list });
                    }
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
    /// When disabled, parsing stops at first non-option argument (POSIX behavior)
    pub fn disableInterspersedArgs(self: *Self) void {
        self.allow_interspersed_args = false;
    }

    /// Enable interspersed arguments (default)
    /// Options can appear anywhere in the argument list
    pub fn enableInterspersedArgs(self: *Self) void {
        self.allow_interspersed_args = true;
    }

    /// Check if interspersed arguments are allowed
    pub fn allowsInterspersedArgs(self: *const Self) bool {
        return self.allow_interspersed_args;
    }
};

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
