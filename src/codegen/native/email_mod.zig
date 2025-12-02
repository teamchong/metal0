/// Python email module - Email handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const EmailMessageFuncs = std.StaticStringMap(h.H).initComptime(.{ .{ "EmailMessage", genEmailMessage }, .{ "Message", genEmailMessage } });
pub const EmailMimeTextFuncs = std.StaticStringMap(h.H).initComptime(.{ .{ "MIMEText", genMIMEText } });
pub const EmailMimeMultipartFuncs = std.StaticStringMap(h.H).initComptime(.{ .{ "MIMEMultipart", h.c("struct { subtype: []const u8 = \"mixed\", parts: std.ArrayList([]const u8) = .{}, headers: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn attach(__self: *@This(), part: anytype) void { __self.parts.append(__global_allocator, part.as_string()) catch {}; } pub fn as_string(__self: *@This()) []const u8 { var result: std.ArrayList(u8) = .{}; for (__self.parts.items) |p| result.appendSlice(__global_allocator, p) catch {}; return result.items; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; } }{}") } });
pub const EmailMimeBaseFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "MIMEBase", h.c("struct { maintype: []const u8 = \"application\", subtype: []const u8 = \"octet-stream\", payload: []const u8 = \"\", pub fn set_payload(__self: *@This(), data: []const u8) void { __self.payload = data; } pub fn get_payload(__self: *@This()) []const u8 { return __self.payload; } pub fn add_header(__self: *@This(), name: []const u8, value: []const u8) void { _ = name; _ = value; } }{}") },
    .{ "MIMEApplication", genMIMEApp }, .{ "MIMEImage", genMIMEApp }, .{ "MIMEAudio", genMIMEApp },
});
pub const EmailUtilsFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "formataddr", h.c("\"\"") }, .{ "parseaddr", h.c(".{ \"\", \"\" }") },
    .{ "formatdate", h.c("\"\"") }, .{ "make_msgid", h.c("\"<message@localhost>\"") },
});

fn genEmailMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { headers: hashmap_helper.StringHashMap([]const u8), body: []const u8 = \"\", pub fn init() @This() { return @This(){ .headers = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }; } pub fn set_content(__self: *@This(), content: []const u8) void { __self.body = content; } pub fn get_content(__self: *@This()) []const u8 { return __self.body; } pub fn get_body(__self: *@This()) []const u8 { return __self.body; } pub fn as_string(__self: *@This()) []const u8 { return __self.body; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; } pub fn add_header(__self: *@This(), name: []const u8, value: []const u8) void { __self.set(name, value); } }.init()");
}

fn genMIMEText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { body: []const u8 = \"\", subtype: []const u8 = \"plain\" }{}"); return; }
    try self.emit("struct { body: []const u8, subtype: []const u8 = \"plain\", headers: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn as_string(__self: *@This()) []const u8 { return __self.body; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; } }{ .body = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

fn genMIMEApp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { payload: []const u8 = \"\" }{}"); return; }
    try self.emit("struct { payload: []const u8 }{ .payload = "); try self.genExpr(args[0]); try self.emit(" }");
}
