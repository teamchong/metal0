//! ArgumentParser implementation
//!
//! Core argument parsing logic.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const argument_mod = @import("argument.zig");
const parse_result_mod = @import("parse_result.zig");
const subparsers_mod = @import("subparsers.zig");
const utils = @import("utils.zig");
const formatter = @import("formatter.zig");

pub const Argument = argument_mod.Argument;
pub const ParseResult = parse_result_mod.ParseResult;
pub const SubparserGroup = subparsers_mod.SubparserGroup;

/// Command-line argument parser
pub const ArgumentParser = struct {
    const Self = @This();
    const ArgList = std.ArrayList(Argument);
    const ValueMap = hashmap_helper.StringHashMap(types.ArgValue);

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
            .arguments = .{},
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
        self.arguments.deinit(self.allocator);
    }

    /// Add an argument to the parser
    pub fn addArgument(self: *Self, names: []const []const u8, options: types.ArgumentOptions) !void {
        try self.arguments.append(self.allocator, .{
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
        const argv = args orelse utils.getSystemArgs(self.allocator);

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
                            formatter.printHelp(self);
                            return error.HelpRequested;
                        },
                        .version => {
                            return error.VersionRequested;
                        },
                        .append => {
                            // Append value to list
                            const value_to_append = if (arg.nargs != null and i + 1 < argv.len) blk: {
                                i += 1;
                                break :blk argv[i];
                            } else arg.default orelse "";

                            const dest = arg.getDest();
                            if (result.values.get(dest)) |existing| {
                                // Append to existing list
                                if (existing == .strings) {
                                    var new_list: std.ArrayList([]const u8) = .{};
                                    for (existing.strings) |s| {
                                        try new_list.append(self.allocator, s);
                                    }
                                    try new_list.append(self.allocator, value_to_append);
                                    try result.values.put(dest, .{ .strings = try new_list.toOwnedSlice(self.allocator) });
                                }
                            } else {
                                // Create new list with single value
                                var new_list: std.ArrayList([]const u8) = .{};
                                try new_list.append(self.allocator, value_to_append);
                                try result.values.put(dest, .{ .strings = try new_list.toOwnedSlice(self.allocator) });
                            }
                        },
                        .append_const => {
                            // Append constant to list
                            const const_val = arg.const_value orelse "";
                            const dest = arg.getDest();
                            if (result.values.get(dest)) |existing| {
                                if (existing == .strings) {
                                    var new_list: std.ArrayList([]const u8) = .{};
                                    for (existing.strings) |s| {
                                        try new_list.append(self.allocator, s);
                                    }
                                    try new_list.append(self.allocator, const_val);
                                    try result.values.put(dest, .{ .strings = try new_list.toOwnedSlice(self.allocator) });
                                }
                            } else {
                                var new_list: std.ArrayList([]const u8) = .{};
                                try new_list.append(self.allocator, const_val);
                                try result.values.put(dest, .{ .strings = try new_list.toOwnedSlice(self.allocator) });
                            }
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
                    try result.remaining.append(self.allocator, arg_str);
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
        formatter.printHelp(self);
    }

    /// Format help as string
    pub fn formatHelp(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        return formatter.formatHelp(self, allocator);
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
