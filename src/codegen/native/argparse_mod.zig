/// Python argparse module - Command-line argument parsing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const ArgumentParserStruct = "struct { description: ?[]const u8 = null, prog: ?[]const u8 = null, arguments: std.ArrayList(Argument), parsed: hashmap_helper.StringHashMap([]const u8), positional_args: std.ArrayList([]const u8), const Argument = struct { name: []const u8, short: ?[]const u8 = null, help: ?[]const u8 = null, default: ?[]const u8 = null, required: bool = false, is_flag: bool = false, action: ?[]const u8 = null }; pub fn init() @This() { return @This(){ .arguments = .{}, .parsed = .{}, .positional_args = .{} }; } pub fn add_argument(__self: *@This(), name: []const u8) void { const is_optional = name.len > 0 and name[0] == '-'; __self.arguments.append(__global_allocator, Argument{ .name = name, .is_flag = is_optional }) catch unreachable; } pub fn parse_args(__self: *@This()) *@This() { const args_arr = std.process.argsAlloc(__global_allocator) catch return __self; var i: usize = 1; while (i < args_arr.len) : (i += 1) { const arg = args_arr[i]; if (arg.len > 2 and std.mem.startsWith(u8, arg, \"--\")) { if (std.mem.indexOfScalar(u8, arg, '=')) |eq| { __self.parsed.put(arg[2..eq], arg[eq + 1 ..]) catch unreachable; } else if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], \"-\")) { __self.parsed.put(arg[2..], args_arr[i + 1]) catch unreachable; i += 1; } else { __self.parsed.put(arg[2..], \"true\") catch unreachable; } } else if (arg.len > 1 and arg[0] == '-') { if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], \"-\")) { __self.parsed.put(arg[1..], args_arr[i + 1]) catch unreachable; i += 1; } else { __self.parsed.put(arg[1..], \"true\") catch unreachable; } } else { __self.positional_args.append(__global_allocator, arg) catch unreachable; } } return __self; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.parsed.get(name); } pub fn get_positional(__self: *@This(), index: usize) ?[]const u8 { if (index < __self.positional_args.items.len) return __self.positional_args.items[index]; return null; } pub fn print_help(__self: *@This()) void { _ = __self; const stdout = std.io.getStdOut().writer(); stdout.print(\"usage: program [options]\\n\", .{}) catch unreachable; } }.init()";

const NamespaceStruct = "struct { data: hashmap_helper.StringHashMap([]const u8), pub fn init() @This() { return @This(){ .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }; } pub fn get(__self: *@This(), key: []const u8) ?[]const u8 { return __self.data.get(key); } pub fn set(__self: *@This(), key: []const u8, val: []const u8) void { __self.data.put(key, val) catch unreachable; } }.init()";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ArgumentParser", genArgumentParser },
    .{ "Namespace", genNamespace },
    .{ "FileType", genFileType },
    .{ "REMAINDER", genRemainder },
    .{ "SUPPRESS", genSuppress },
    .{ "OPTIONAL", genOptional },
    .{ "ZERO_OR_MORE", genZeroOrMore },
    .{ "ONE_OR_MORE", genOneOrMore },
});

fn genArgumentParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ArgumentParserStruct), builder_mod.EmitConfig.forExpression());
}

fn genNamespace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(NamespaceStruct), builder_mod.EmitConfig.forExpression());
}

fn genFileType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("r"), builder_mod.EmitConfig.forExpression());
}

fn genRemainder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("..."), builder_mod.EmitConfig.forExpression());
}

fn genSuppress(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("==SUPPRESS=="), builder_mod.EmitConfig.forExpression());
}

fn genOptional(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("?"), builder_mod.EmitConfig.forExpression());
}

fn genZeroOrMore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("*"), builder_mod.EmitConfig.forExpression());
}

fn genOneOrMore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("+"), builder_mod.EmitConfig.forExpression());
}

