/// Python optparse module - Parser for command line options (deprecated, use argparse)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "OptionParser", genOptionParser }, .{ "add_option", genEmpty }, .{ "parse_args", genParseArgs },
    .{ "set_usage", genUnit }, .{ "set_defaults", genUnit }, .{ "get_default_values", genEmpty },
    .{ "get_option", genNull }, .{ "has_option", genFalse }, .{ "remove_option", genUnit },
    .{ "add_option_group", genEmpty }, .{ "get_option_group", genNull },
    .{ "print_help", genUnit }, .{ "print_usage", genUnit }, .{ "print_version", genUnit },
    .{ "format_help", genEmptyStr }, .{ "format_usage", genEmptyStr }, .{ "error", genOptError },
    .{ "Option", genOption }, .{ "OptionGroup", genOptionGroup }, .{ "Values", genEmpty },
    .{ "OptionError", genOptError }, .{ "OptionConflictError", genOptConflictError },
    .{ "OptionValueError", genOptValueError }, .{ "BadOptionError", genBadOptError },
    .{ "AmbiguousOptionError", genAmbigOptError },
    .{ "HelpFormatter", genHelpFormatter }, .{ "IndentedHelpFormatter", genHelpFormatter },
    .{ "TitledHelpFormatter", genTitledFormatter },
    .{ "SUPPRESS_HELP", genSuppress }, .{ "SUPPRESS_USAGE", genSuppress }, .{ "NO_DEFAULT", genNoDefault },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genSuppress(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"SUPPRESS\""); }
fn genNoDefault(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"NO\""); }

// Errors
fn genOptError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OptionError"); }
fn genOptConflictError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OptionConflictError"); }
fn genOptValueError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OptionValueError"); }
fn genBadOptError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.BadOptionError"); }
fn genAmbigOptError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.AmbiguousOptionError"); }

// Structs
fn genOptionParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .usage = null, .description = null, .formatter = null, .add_help_option = true, .prog = null, .epilog = null }"); }
fn genParseArgs(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .{}, &[_][]const u8{} }"); }
fn genOption(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .action = \"store\", .type = null, .dest = null, .default = null, .nargs = 1, .const = null, .choices = null, .callback = null, .callback_args = null, .callback_kwargs = null, .help = null, .metavar = null }"); }
fn genOptionGroup(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .title = null, .description = null }"); }
fn genHelpFormatter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }"); }
fn genTitledFormatter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .indent_increment = 0, .max_help_position = 24, .width = null, .short_first = 0 }"); }
