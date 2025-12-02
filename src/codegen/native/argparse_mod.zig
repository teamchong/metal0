/// Python argparse module - Command-line argument parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ArgumentParser", genArgumentParser }, .{ "Namespace", genNamespace }, .{ "FileType", genFileType },
    .{ "REMAINDER", genREMAINDER }, .{ "SUPPRESS", genSUPPRESS }, .{ "OPTIONAL", genOPTIONAL },
    .{ "ZERO_OR_MORE", genZERO_OR_MORE }, .{ "ONE_OR_MORE", genONE_OR_MORE },
});

const ArgumentParserStruct = "struct { description: ?[]const u8 = null, prog: ?[]const u8 = null, arguments: std.ArrayList(Argument), parsed: hashmap_helper.StringHashMap([]const u8), positional_args: std.ArrayList([]const u8), const Argument = struct { name: []const u8, short: ?[]const u8 = null, help: ?[]const u8 = null, default: ?[]const u8 = null, required: bool = false, is_flag: bool = false, action: ?[]const u8 = null }; pub fn init() @This() { return @This(){ .arguments = .{}, .parsed = .{}, .positional_args = .{} }; } pub fn add_argument(__self: *@This(), name: []const u8) void { const is_optional = name.len > 0 and name[0] == '-'; __self.arguments.append(__global_allocator, Argument{ .name = name, .is_flag = is_optional }) catch {}; } pub fn parse_args(__self: *@This()) *@This() { const args_arr = std.process.argsAlloc(__global_allocator) catch return __self; var i: usize = 1; while (i < args_arr.len) : (i += 1) { const arg = args_arr[i]; if (arg.len > 2 and std.mem.startsWith(u8, arg, \"--\")) { if (std.mem.indexOfScalar(u8, arg, '=')) |eq| { __self.parsed.put(arg[2..eq], arg[eq + 1 ..]) catch {}; } else if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], \"-\")) { __self.parsed.put(arg[2..], args_arr[i + 1]) catch {}; i += 1; } else { __self.parsed.put(arg[2..], \"true\") catch {}; } } else if (arg.len > 1 and arg[0] == '-') { if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], \"-\")) { __self.parsed.put(arg[1..], args_arr[i + 1]) catch {}; i += 1; } else { __self.parsed.put(arg[1..], \"true\") catch {}; } } else { __self.positional_args.append(__global_allocator, arg) catch {}; } } return __self; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.parsed.get(name); } pub fn get_positional(__self: *@This(), index: usize) ?[]const u8 { if (index < __self.positional_args.items.len) return __self.positional_args.items[index]; return null; } pub fn print_help(__self: *@This()) void { _ = __self; const stdout = std.io.getStdOut().writer(); stdout.print(\"usage: program [options]\\n\", .{}) catch {}; } }.init()";

const NamespaceStruct = "struct { data: hashmap_helper.StringHashMap([]const u8), pub fn init() @This() { return @This(){ .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }; } pub fn get(__self: *@This(), key: []const u8) ?[]const u8 { return __self.data.get(key); } pub fn set(__self: *@This(), key: []const u8, val: []const u8) void { __self.data.put(key, val) catch {}; } }.init()";

fn genArgumentParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ArgumentParserStruct); }
fn genNamespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, NamespaceStruct); }
fn genFileType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"r\""); }
fn genREMAINDER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"...\""); }
fn genSUPPRESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"==SUPPRESS==\""); }
fn genOPTIONAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"?\""); }
fn genZERO_OR_MORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"*\""); }
fn genONE_OR_MORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"+\""); }
