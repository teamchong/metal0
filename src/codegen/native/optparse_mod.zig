/// Python optparse module - Parser for command line options (deprecated, use argparse)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "OptionParser", genConst(".{ .usage = null, .description = null, .formatter = null, .add_help_option = true, .prog = null, .epilog = null }") },
    .{ "add_option", genConst(".{}") }, .{ "parse_args", genConst(".{ .{}, &[_][]const u8{} }") },
    .{ "set_usage", genConst("{}") }, .{ "set_defaults", genConst("{}") }, .{ "get_default_values", genConst(".{}") },
    .{ "get_option", genConst("null") }, .{ "has_option", genConst("false") }, .{ "remove_option", genConst("{}") },
    .{ "add_option_group", genConst(".{}") }, .{ "get_option_group", genConst("null") },
    .{ "print_help", genConst("{}") }, .{ "print_usage", genConst("{}") }, .{ "print_version", genConst("{}") },
    .{ "format_help", genConst("\"\"") }, .{ "format_usage", genConst("\"\"") }, .{ "error", genConst("error.OptionError") },
    .{ "Option", genConst(".{ .action = \"store\", .type = null, .dest = null, .default = null, .nargs = 1, .const = null, .choices = null, .callback = null, .callback_args = null, .callback_kwargs = null, .help = null, .metavar = null }") },
    .{ "OptionGroup", genConst(".{ .title = null, .description = null }") }, .{ "Values", genConst(".{}") },
    .{ "OptionError", genConst("error.OptionError") }, .{ "OptionConflictError", genConst("error.OptionConflictError") },
    .{ "OptionValueError", genConst("error.OptionValueError") }, .{ "BadOptionError", genConst("error.BadOptionError") },
    .{ "AmbiguousOptionError", genConst("error.AmbiguousOptionError") },
    .{ "HelpFormatter", genConst(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }") },
    .{ "IndentedHelpFormatter", genConst(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }") },
    .{ "TitledHelpFormatter", genConst(".{ .indent_increment = 0, .max_help_position = 24, .width = null, .short_first = 0 }") },
    .{ "SUPPRESS_HELP", genConst("\"SUPPRESS\"") }, .{ "SUPPRESS_USAGE", genConst("\"SUPPRESS\"") }, .{ "NO_DEFAULT", genConst("\"NO\"") },
});
