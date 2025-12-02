/// Python email module - Email handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// email module functions
pub const EmailMessageFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "EmailMessage", genEmailMessage },
    .{ "Message", genMessage },
});

/// email.mime.text module functions
pub const EmailMimeTextFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "MIMEText", genMIMEText },
});

/// email.mime.multipart module functions
pub const EmailMimeMultipartFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "MIMEMultipart", genMIMEMultipart },
});

/// email.mime.base module functions
pub const EmailMimeBaseFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "MIMEBase", genMIMEBase },
    .{ "MIMEApplication", genMIMEApplication },
    .{ "MIMEImage", genMIMEImage },
    .{ "MIMEAudio", genMIMEAudio },
});

/// email.utils module functions
pub const EmailUtilsFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "formataddr", genFormataddr },
    .{ "parseaddr", genParseaddr },
    .{ "formatdate", genFormatdate },
    .{ "make_msgid", genMakeMsgid },
});

/// Generate email.message.EmailMessage() -> EmailMessage
pub fn genEmailMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("headers: hashmap_helper.StringHashMap([]const u8),\n");
    try self.emitIndent();
    try self.emit("body: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn init() @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .headers = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn set_content(__self: *@This(), content: []const u8) void { __self.body = content; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_content(__self: *@This()) []const u8 { return __self.body; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_body(__self: *@This()) []const u8 { return __self.body; }\n");
    try self.emitIndent();
    try self.emit("pub fn as_string(__self: *@This()) []const u8 { return __self.body; }\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); }\n");
    try self.emitIndent();
    try self.emit("pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn add_header(__self: *@This(), name: []const u8, value: []const u8) void { __self.set(name, value); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init()");
}

/// Generate email.message.Message() -> Message (legacy)
pub fn genMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genEmailMessage(self, args);
}

/// Generate email.mime.text.MIMEText(text, subtype='plain') -> MIMEText
pub fn genMIMEText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { body: []const u8 = \"\", subtype: []const u8 = \"plain\" }{}");
        return;
    }

    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("body: []const u8,\n");
    try self.emitIndent();
    try self.emit("subtype: []const u8 = \"plain\",\n");
    try self.emitIndent();
    try self.emit("headers: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn as_string(__self: *@This()) []const u8 { return __self.body; }\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); }\n");
    try self.emitIndent();
    try self.emit("pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .body = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

/// Generate email.mime.multipart.MIMEMultipart(subtype='mixed') -> MIMEMultipart
pub fn genMIMEMultipart(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("subtype: []const u8 = \"mixed\",\n");
    try self.emitIndent();
    try self.emit("parts: std.ArrayList([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("headers: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn attach(__self: *@This(), part: anytype) void { __self.parts.append(__global_allocator, part.as_string()) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn as_string(__self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("for (__self.parts.items) |p| result.appendSlice(__global_allocator, p) catch {};\n");
    try self.emitIndent();
    try self.emit("return result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.headers.get(name); }\n");
    try self.emitIndent();
    try self.emit("pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.headers.put(name, value) catch {}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate email.mime.base.MIMEBase(maintype, subtype) -> MIMEBase
pub fn genMIMEBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("maintype: []const u8 = \"application\",\n");
    try self.emitIndent();
    try self.emit("subtype: []const u8 = \"octet-stream\",\n");
    try self.emitIndent();
    try self.emit("payload: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn set_payload(__self: *@This(), data: []const u8) void { __self.payload = data; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_payload(__self: *@This()) []const u8 { return __self.payload; }\n");
    try self.emitIndent();
    try self.emit("pub fn add_header(__self: *@This(), name: []const u8, value: []const u8) void { _ = name; _ = value; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate email.mime.application.MIMEApplication(data) -> MIMEApplication
pub fn genMIMEApplication(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { payload: []const u8 = \"\" }{}");
        return;
    }
    try self.emit("struct { payload: []const u8 }{ .payload = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

/// Generate email.mime.image.MIMEImage(data) -> MIMEImage
pub fn genMIMEImage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMIMEApplication(self, args);
}

/// Generate email.mime.audio.MIMEAudio(data) -> MIMEAudio
pub fn genMIMEAudio(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genMIMEApplication(self, args);
}

/// Generate email.utils.formataddr((name, addr)) -> formatted string
pub fn genFormataddr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate email.utils.parseaddr(addr) -> (name, email)
pub fn genParseaddr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", \"\" }");
}

/// Generate email.utils.formatdate(timeval=None, localtime=False) -> date string
pub fn genFormatdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate email.utils.make_msgid(idstring=None, domain=None) -> message id
pub fn genMakeMsgid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"<message@localhost>\"");
}
