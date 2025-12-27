/// Python configparser module - Configuration file parser
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const ConfigParserStruct = "struct { sections_map: hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8)), pub fn init() @This() { return @This(){ .sections_map = hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8)).init(__global_allocator) }; } pub fn read(__self: *@This(), filename: []const u8) !void { const file = std.fs.cwd().openFile(filename, .{}) catch return; defer file.close(); const content = file.readToEndAlloc(__global_allocator, 1024 * 1024) catch return; __self.read_string(content); } pub fn read_string(__self: *@This(), content: []const u8) void { var current_section: ?[]const u8 = null; var lines = std.mem.splitScalar(u8, content, '\\n'); while (lines.next()) |line| { const trimmed = std.mem.trim(u8, line, \" \\t\\r\"); if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == ';') continue; if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') { current_section = trimmed[1 .. trimmed.len - 1]; if (__self.sections_map.get(current_section.?) == null) { __self.sections_map.put(current_section.?, hashmap_helper.StringHashMap([]const u8).init(__global_allocator)) catch continue; } } else if (current_section != null) { if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| { const key = std.mem.trim(u8, trimmed[0..eq_pos], \" \\t\"); const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], \" \\t\"); if (__self.sections_map.getPtr(current_section.?)) |sec| sec.put(key, value) catch unreachable; } } } } pub fn sections(__self: *@This()) [][]const u8 { var result: std.ArrayList([]const u8) = .{}; var iter = __self.sections_map.iterator(); while (iter.next()) |entry| result.append(__global_allocator, entry.key_ptr.*) catch continue; return result.items; } pub fn has_section(__self: *@This(), section: []const u8) bool { return __self.sections_map.get(section) != null; } pub fn get(__self: *@This(), section: []const u8, option: []const u8) ?[]const u8 { if (__self.sections_map.get(section)) |sec| return sec.get(option); return null; } pub fn getint(__self: *@This(), section: []const u8, option: []const u8) ?i64 { if (__self.get(section, option)) |val| return std.fmt.parseInt(i64, val, 10) catch null; return null; } pub fn getfloat(__self: *@This(), section: []const u8, option: []const u8) ?f64 { if (__self.get(section, option)) |val| return std.fmt.parseFloat(f64, val) catch null; return null; } pub fn getboolean(__self: *@This(), section: []const u8, option: []const u8) ?bool { if (__self.get(section, option)) |val| { if (std.mem.eql(u8, val, \"true\") or std.mem.eql(u8, val, \"yes\") or std.mem.eql(u8, val, \"1\")) return true; if (std.mem.eql(u8, val, \"false\") or std.mem.eql(u8, val, \"no\") or std.mem.eql(u8, val, \"0\")) return false; } return null; } pub fn set(__self: *@This(), section: []const u8, option: []const u8, value: []const u8) void { if (__self.sections_map.getPtr(section)) |sec| sec.put(option, value) catch unreachable; } pub fn add_section(__self: *@This(), section: []const u8) void { if (__self.sections_map.get(section) == null) { __self.sections_map.put(section, hashmap_helper.StringHashMap([]const u8).init(__global_allocator)) catch unreachable; } } pub fn options(__self: *@This(), section: []const u8) [][]const u8 { var result: std.ArrayList([]const u8) = .{}; if (__self.sections_map.get(section)) |sec| { var iter = sec.iterator(); while (iter.next()) |entry| result.append(__global_allocator, entry.key_ptr.*) catch continue; } return result.items; } }.init()";

/// ExtendedInterpolation is a class type marker (not an instance)
/// When passed as an argument, it represents the type itself
const ExtendedInterpolationStruct = "struct { pub const __name__ = \"ExtendedInterpolation\"; }";
const BasicInterpolationStruct = "struct { pub const __name__ = \"BasicInterpolation\"; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ConfigParser", genConfigParser },
    .{ "RawConfigParser", genRawConfigParser },
    .{ "SafeConfigParser", genSafeConfigParser },
    .{ "ExtendedInterpolation", genExtendedInterpolation },
    .{ "BasicInterpolation", genBasicInterpolation },
});

fn genConfigParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ConfigParserStruct), builder_mod.EmitConfig.forExpression());
}

fn genRawConfigParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ConfigParserStruct), builder_mod.EmitConfig.forExpression());
}

fn genSafeConfigParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ConfigParserStruct), builder_mod.EmitConfig.forExpression());
}

fn genExtendedInterpolation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ExtendedInterpolationStruct), builder_mod.EmitConfig.forExpression());
}

fn genBasicInterpolation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(BasicInterpolationStruct), builder_mod.EmitConfig.forExpression());
}
