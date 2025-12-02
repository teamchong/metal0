/// Python optparse module - Parser for command line options (deprecated, use argparse)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "OptionParser", h.c(".{ .usage = null, .description = null, .formatter = null, .add_help_option = true, .prog = null, .epilog = null }") },
    .{ "add_option", h.c(".{}") }, .{ "parse_args", h.c(".{ .{}, &[_][]const u8{} }") },
    .{ "set_usage", h.c("{}") }, .{ "set_defaults", h.c("{}") }, .{ "get_default_values", h.c(".{}") },
    .{ "get_option", h.c("null") }, .{ "has_option", h.c("false") }, .{ "remove_option", h.c("{}") },
    .{ "add_option_group", h.c(".{}") }, .{ "get_option_group", h.c("null") },
    .{ "print_help", h.c("{}") }, .{ "print_usage", h.c("{}") }, .{ "print_version", h.c("{}") },
    .{ "format_help", h.c("\"\"") }, .{ "format_usage", h.c("\"\"") }, .{ "error", h.err("OptionError") },
    .{ "Option", h.c(".{ .action = \"store\", .type = null, .dest = null, .default = null, .nargs = 1, .const = null, .choices = null, .callback = null, .callback_args = null, .callback_kwargs = null, .help = null, .metavar = null }") },
    .{ "OptionGroup", h.c(".{ .title = null, .description = null }") }, .{ "Values", h.c(".{}") },
    .{ "OptionError", h.err("OptionError") }, .{ "OptionConflictError", h.err("OptionConflictError") },
    .{ "OptionValueError", h.err("OptionValueError") }, .{ "BadOptionError", h.err("BadOptionError") },
    .{ "AmbiguousOptionError", h.err("AmbiguousOptionError") },
    .{ "HelpFormatter", h.c(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }") },
    .{ "IndentedHelpFormatter", h.c(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }") },
    .{ "TitledHelpFormatter", h.c(".{ .indent_increment = 0, .max_help_position = 24, .width = null, .short_first = 0 }") },
    .{ "SUPPRESS_HELP", h.c("\"SUPPRESS\"") }, .{ "SUPPRESS_USAGE", h.c("\"SUPPRESS\"") }, .{ "NO_DEFAULT", h.c("\"NO\"") },
});
