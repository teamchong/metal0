/// Python optparse module - Parser for command line options (deprecated, use argparse)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "OptionParser", genOptionParser },
    .{ "add_option", genAddOption },
    .{ "parse_args", genParseArgs },
    .{ "set_usage", genSetUsage },
    .{ "set_defaults", genSetDefaults },
    .{ "get_default_values", genGetDefaultValues },
    .{ "get_option", genGetOption },
    .{ "has_option", genHasOption },
    .{ "remove_option", genRemoveOption },
    .{ "add_option_group", genAddOptionGroup },
    .{ "get_option_group", genGetOptionGroup },
    .{ "print_help", genPrintHelp },
    .{ "print_usage", genPrintUsage },
    .{ "print_version", genPrintVersion },
    .{ "format_help", genFormatHelp },
    .{ "format_usage", genFormatUsage },
    .{ "error", genError },
    .{ "Option", genOption },
    .{ "OptionGroup", genOptionGroup },
    .{ "Values", genValues },
    .{ "OptionError", genOptionError },
    .{ "OptionConflictError", genOptionConflictError },
    .{ "OptionValueError", genOptionValueError },
    .{ "BadOptionError", genBadOptionError },
    .{ "AmbiguousOptionError", genAmbiguousOptionError },
    .{ "HelpFormatter", genHelpFormatter },
    .{ "IndentedHelpFormatter", genIndentedHelpFormatter },
    .{ "TitledHelpFormatter", genTitledHelpFormatter },
    .{ "SUPPRESS_HELP", genSuppressHelp },
    .{ "SUPPRESS_USAGE", genSuppressUsage },
    .{ "NO_DEFAULT", genNoDefault },
});

fn genOptionParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .usage = null, .description = null, .formatter = null, .add_help_option = true, .prog = null, .epilog = null }"), builder_mod.EmitConfig.forExpression());
}

fn genAddOption(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genParseArgs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .{}, &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genSetUsage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetDefaults(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetDefaultValues(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetOption(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genHasOption(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genRemoveOption(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genAddOptionGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetOptionGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genPrintHelp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintUsage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genFormatHelp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genFormatUsage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OptionError"), builder_mod.EmitConfig.forExpression());
}

fn genOption(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .action = \"store\", .type = null, .dest = null, .default = null, .nargs = 1, .const = null, .choices = null, .callback = null, .callback_args = null, .callback_kwargs = null, .help = null, .metavar = null }"), builder_mod.EmitConfig.forExpression());
}

fn genOptionGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .title = null, .description = null }"), builder_mod.EmitConfig.forExpression());
}

fn genValues(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genOptionError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OptionError"), builder_mod.EmitConfig.forExpression());
}

fn genOptionConflictError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OptionConflictError"), builder_mod.EmitConfig.forExpression());
}

fn genOptionValueError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OptionValueError"), builder_mod.EmitConfig.forExpression());
}

fn genBadOptionError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.BadOptionError"), builder_mod.EmitConfig.forExpression());
}

fn genAmbiguousOptionError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.AmbiguousOptionError"), builder_mod.EmitConfig.forExpression());
}

fn genHelpFormatter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genIndentedHelpFormatter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .indent_increment = 2, .max_help_position = 24, .width = null, .short_first = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genTitledHelpFormatter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .indent_increment = 0, .max_help_position = 24, .width = null, .short_first = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSuppressHelp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("SUPPRESS"), builder_mod.EmitConfig.forExpression());
}

fn genSuppressUsage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("SUPPRESS"), builder_mod.EmitConfig.forExpression());
}

fn genNoDefault(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("NO"), builder_mod.EmitConfig.forExpression());
}
