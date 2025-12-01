/// Python argparse module - Command-line argument parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ArgumentParser", genArgumentParser },
    .{ "Namespace", genNamespace },
    .{ "FileType", genFileType },
    .{ "REMAINDER", genREMAINDER },
    .{ "SUPPRESS", genSUPPRESS },
    .{ "OPTIONAL", genOPTIONAL },
    .{ "ZERO_OR_MORE", genZERO_OR_MORE },
    .{ "ONE_OR_MORE", genONE_OR_MORE },
});

/// Generate argparse.ArgumentParser(description=None, prog=None) -> ArgumentParser
pub fn genArgumentParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("description: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("prog: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("arguments: std.ArrayList(Argument),\n");
    try self.emitIndent();
    try self.emit("parsed: hashmap_helper.StringHashMap([]const u8),\n");
    try self.emitIndent();
    try self.emit("positional_args: std.ArrayList([]const u8),\n");
    try self.emitIndent();
    try self.emit("const Argument = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("short: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("help: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("default: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("required: bool = false,\n");
    try self.emitIndent();
    try self.emit("is_flag: bool = false,\n");
    try self.emitIndent();
    try self.emit("action: ?[]const u8 = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("pub fn init() @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".arguments = .{},\n");
    try self.emitIndent();
    try self.emit(".parsed = .{},\n");
    try self.emitIndent();
    try self.emit(".positional_args = .{},\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn add_argument(self: *@This(), name: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const is_optional = name.len > 0 and name[0] == '-';\n");
    try self.emitIndent();
    try self.emit("self.arguments.append(__global_allocator, Argument{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".name = name,\n");
    try self.emitIndent();
    try self.emit(".is_flag = is_optional,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn parse_args(self: *@This()) *@This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const args = std.process.argsAlloc(__global_allocator) catch return self;\n");
    try self.emitIndent();
    try self.emit("var i: usize = 1;\n");
    try self.emitIndent();
    try self.emit("while (i < args.len) : (i += 1) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const arg = args[i];\n");
    try self.emitIndent();
    try self.emit("if (arg.len > 2 and std.mem.startsWith(u8, arg, \"--\")) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.parsed.put(arg[2..eq], arg[eq + 1 ..]) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], \"-\")) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.parsed.put(arg[2..], args[i + 1]) catch {};\n");
    try self.emitIndent();
    try self.emit("i += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.parsed.put(arg[2..], \"true\") catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else if (arg.len > 1 and arg[0] == '-') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], \"-\")) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.parsed.put(arg[1..], args[i + 1]) catch {};\n");
    try self.emitIndent();
    try self.emit("i += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.parsed.put(arg[1..], \"true\") catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.positional_args.append(__global_allocator, arg) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("return self;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), name: []const u8) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return self.parsed.get(name);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get_positional(self: *@This(), index: usize) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (index < self.positional_args.items.len) return self.positional_args.items[index];\n");
    try self.emitIndent();
    try self.emit("return null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn print_help(self: *@This()) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("const stdout = std.io.getStdOut().writer();\n");
    try self.emitIndent();
    try self.emit("stdout.print(\"usage: program [options]\\n\", .{}) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init()");
}

/// Generate argparse.Namespace() -> Namespace object (simple dict-like)
pub fn genNamespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: hashmap_helper.StringHashMap([]const u8),\n");
    try self.emitIndent();
    try self.emit("pub fn init() @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), key: []const u8) ?[]const u8 { return self.data.get(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn set(self: *@This(), key: []const u8, val: []const u8) void { self.data.put(key, val) catch {}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init()");
}

/// Generate argparse.FileType(mode='r') -> file type factory
pub fn genFileType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns a callable that opens files - simplified to just return the mode
    try self.emit("\"r\"");
}

/// Generate argparse.REMAINDER constant
pub fn genREMAINDER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"...\"");
}

/// Generate argparse.SUPPRESS constant
pub fn genSUPPRESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"==SUPPRESS==\"");
}

/// Generate argparse.OPTIONAL constant
pub fn genOPTIONAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"?\"");
}

/// Generate argparse.ZERO_OR_MORE constant
pub fn genZERO_OR_MORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"*\"");
}

/// Generate argparse.ONE_OR_MORE constant
pub fn genONE_OR_MORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"+\"");
}
