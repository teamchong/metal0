/// Python http module - HTTP protocol client/server
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const HttpClientFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "HTTPConnection", genHTTPConnection },
    .{ "HTTPSConnection", genHTTPSConnection },
    .{ "HTTPResponse", genHTTPResponse },
});

pub const HttpServerFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "HTTPServer", genHTTPServer },
    .{ "ThreadingHTTPServer", genThreadingHTTPServer },
    .{ "BaseHTTPRequestHandler", genBaseHTTPRequestHandler },
    .{ "SimpleHTTPRequestHandler", genSimpleHTTPRequestHandler },
    .{ "CGIHTTPRequestHandler", genCGIHTTPRequestHandler },
});

pub const HttpCookiesFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SimpleCookie", genSimpleCookie },
    .{ "BaseCookie", genBaseCookie },
});

// ============================================================================
// http.client - HTTP and HTTPS protocol client
// ============================================================================

/// Generate http.client.HTTPConnection(host, port=80, timeout=None)
pub fn genHTTPConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("host: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"localhost\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("port: u16 = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("80");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("socket: ?i64 = null,\n");
    try self.emitIndent();
    try self.emit("response_buf: []u8 = &[_]u8{},\n");
    try self.emitIndent();
    try self.emit("pub fn request(__self: *@This(), method: []const u8, url: []const u8, body: ?[]const u8, headers: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = method; _ = url; _ = body; _ = headers;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn getresponse(__self: *@This()) HTTPResponse {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("return HTTPResponse{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn set_debuglevel(__self: *@This(), level: i64) void { _ = level; }\n");
    try self.emitIndent();
    try self.emit("pub fn set_tunnel(__self: *@This(), host: []const u8, port: ?u16, headers: anytype) void { _ = host; _ = port; _ = headers; }\n");
    try self.emitIndent();
    try self.emit("pub fn connect(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self.socket = null; }\n");
    try self.emitIndent();
    try self.emit("pub fn putrequest(__self: *@This(), method: []const u8, url: []const u8) void { _ = method; _ = url; }\n");
    try self.emitIndent();
    try self.emit("pub fn putheader(__self: *@This(), header: []const u8, value: []const u8) void { _ = header; _ = value; }\n");
    try self.emitIndent();
    try self.emit("pub fn endheaders(__self: *@This(), message_body: ?[]const u8) void { _ = message_body; }\n");
    try self.emitIndent();
    try self.emit("pub fn send(__self: *@This(), data: []const u8) void { _ = data; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.client.HTTPSConnection(host, port=443, ...)
pub fn genHTTPSConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("host: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"localhost\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("port: u16 = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("443");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("socket: ?i64 = null,\n");
    try self.emitIndent();
    try self.emit("pub fn request(__self: *@This(), method: []const u8, url: []const u8, body: ?[]const u8, headers: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = method; _ = url; _ = body; _ = headers;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn getresponse(__self: *@This()) HTTPResponse { return HTTPResponse{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn connect(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self.socket = null; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.client.HTTPResponse (returned by getresponse)
pub fn genHTTPResponse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("status: i64 = 200,\n");
    try self.emitIndent();
    try self.emit("reason: []const u8 = \"OK\",\n");
    try self.emitIndent();
    try self.emit("version: i64 = 11,\n");
    try self.emitIndent();
    try self.emit("headers: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn read(__self: *@This(), amt: ?usize) []const u8 { _ = amt; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn readline(__self: *@This(), limit: ?usize) []const u8 { _ = limit; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn readlines(__self: *@This(), hint: ?usize) [][]const u8 { _ = hint; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn getheader(__self: *@This(), name: []const u8, default: ?[]const u8) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return __self.headers.get(name) orelse default;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn getheaders(__self: *@This()) []struct { []const u8, []const u8 } { return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn fileno(__self: *@This()) i64 { return -1; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn isclosed(__self: *@This()) bool { return false; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// ============================================================================
// http.server - HTTP servers
// ============================================================================

/// Generate http.server.HTTPServer(server_address, RequestHandlerClass)
pub fn genHTTPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("server_address: struct { []const u8, u16 } = .{ \"\", 8000 },\n");
    try self.emitIndent();
    try self.emit("pub fn serve_forever(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn handle_request(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn shutdown(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn server_close(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.server.ThreadingHTTPServer(server_address, RequestHandlerClass)
pub fn genThreadingHTTPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("server_address: struct { []const u8, u16 } = .{ \"\", 8000 },\n");
    try self.emitIndent();
    try self.emit("pub fn serve_forever(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn shutdown(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.server.BaseHTTPRequestHandler
pub fn genBaseHTTPRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("command: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("path: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("request_version: []const u8 = \"HTTP/1.1\",\n");
    try self.emitIndent();
    try self.emit("headers: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("rfile: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("wfile: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("pub fn send_response(__self: *@This(), code: i64, message: ?[]const u8) void { _ = code; _ = message; }\n");
    try self.emitIndent();
    try self.emit("pub fn send_header(__self: *@This(), keyword: []const u8, value: []const u8) void { _ = keyword; _ = value; }\n");
    try self.emitIndent();
    try self.emit("pub fn send_error(__self: *@This(), code: i64, message: ?[]const u8) void { _ = code; _ = message; }\n");
    try self.emitIndent();
    try self.emit("pub fn end_headers(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn log_request(__self: *@This(), code: ?i64, size: ?i64) void { _ = code; _ = size; }\n");
    try self.emitIndent();
    try self.emit("pub fn log_error(__self: *@This(), format: []const u8) void { _ = format; }\n");
    try self.emitIndent();
    try self.emit("pub fn log_message(__self: *@This(), format: []const u8) void { _ = format; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.server.SimpleHTTPRequestHandler
pub fn genSimpleHTTPRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("command: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("path: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("directory: []const u8 = \".\",\n");
    try self.emitIndent();
    try self.emit("extensions_map: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn do_GET(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn do_HEAD(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn send_head(__self: *@This()) ?*anyopaque { return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn list_directory(__self: *@This(), path: []const u8) ?*anyopaque { _ = path; return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn translate_path(__self: *@This(), path: []const u8) []const u8 { return path; }\n");
    try self.emitIndent();
    try self.emit("pub fn guess_type(__self: *@This(), path: []const u8) []const u8 { _ = path; return \"application/octet-stream\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.server.CGIHTTPRequestHandler
pub fn genCGIHTTPRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("cgi_directories: [][]const u8 = &[_][]const u8{ \"/cgi-bin\", \"/htbin\" },\n");
    try self.emitIndent();
    try self.emit("pub fn do_POST(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn is_cgi(__self: *@This()) bool { return false; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// ============================================================================
// http.cookies - HTTP state management
// ============================================================================

/// Generate http.cookies.SimpleCookie(input=None)
pub fn genSimpleCookie(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("cookies: hashmap_helper.StringHashMap(Morsel) = .{},\n");
    try self.emitIndent();
    try self.emit("pub const Morsel = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("key: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("value: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("coded_value: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("path: []const u8 = \"/\",\n");
    try self.emitIndent();
    try self.emit("domain: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("expires: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("max_age: ?i64 = null,\n");
    try self.emitIndent();
    try self.emit("secure: bool = false,\n");
    try self.emitIndent();
    try self.emit("httponly: bool = false,\n");
    try self.emitIndent();
    try self.emit("samesite: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn output(__self: *@This(), header: []const u8) []const u8 { _ = header; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn js_output(__self: *@This()) []const u8 { return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn OutputString(__self: *@This()) []const u8 { return \"\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("pub fn load(__self: *@This(), rawdata: anytype) void { _ = rawdata; }\n");
    try self.emitIndent();
    try self.emit("pub fn output(__self: *@This(), header: []const u8, sep: []const u8) []const u8 { _ = header; _ = sep; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn js_output(__self: *@This()) []const u8 { return \"\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate http.cookies.BaseCookie(input=None)
pub fn genBaseCookie(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("cookies: hashmap_helper.StringHashMap(anyopaque) = .{},\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// ============================================================================
// http.HTTPStatus - HTTP status codes
// ============================================================================

/// Generate http.HTTPStatus enum
pub fn genHTTPStatus(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub const CONTINUE = 100;\n");
    try self.emitIndent();
    try self.emit("pub const SWITCHING_PROTOCOLS = 101;\n");
    try self.emitIndent();
    try self.emit("pub const PROCESSING = 102;\n");
    try self.emitIndent();
    try self.emit("pub const OK = 200;\n");
    try self.emitIndent();
    try self.emit("pub const CREATED = 201;\n");
    try self.emitIndent();
    try self.emit("pub const ACCEPTED = 202;\n");
    try self.emitIndent();
    try self.emit("pub const NON_AUTHORITATIVE_INFORMATION = 203;\n");
    try self.emitIndent();
    try self.emit("pub const NO_CONTENT = 204;\n");
    try self.emitIndent();
    try self.emit("pub const RESET_CONTENT = 205;\n");
    try self.emitIndent();
    try self.emit("pub const PARTIAL_CONTENT = 206;\n");
    try self.emitIndent();
    try self.emit("pub const MULTI_STATUS = 207;\n");
    try self.emitIndent();
    try self.emit("pub const ALREADY_REPORTED = 208;\n");
    try self.emitIndent();
    try self.emit("pub const MULTIPLE_CHOICES = 300;\n");
    try self.emitIndent();
    try self.emit("pub const MOVED_PERMANENTLY = 301;\n");
    try self.emitIndent();
    try self.emit("pub const FOUND = 302;\n");
    try self.emitIndent();
    try self.emit("pub const SEE_OTHER = 303;\n");
    try self.emitIndent();
    try self.emit("pub const NOT_MODIFIED = 304;\n");
    try self.emitIndent();
    try self.emit("pub const USE_PROXY = 305;\n");
    try self.emitIndent();
    try self.emit("pub const TEMPORARY_REDIRECT = 307;\n");
    try self.emitIndent();
    try self.emit("pub const PERMANENT_REDIRECT = 308;\n");
    try self.emitIndent();
    try self.emit("pub const BAD_REQUEST = 400;\n");
    try self.emitIndent();
    try self.emit("pub const UNAUTHORIZED = 401;\n");
    try self.emitIndent();
    try self.emit("pub const PAYMENT_REQUIRED = 402;\n");
    try self.emitIndent();
    try self.emit("pub const FORBIDDEN = 403;\n");
    try self.emitIndent();
    try self.emit("pub const NOT_FOUND = 404;\n");
    try self.emitIndent();
    try self.emit("pub const METHOD_NOT_ALLOWED = 405;\n");
    try self.emitIndent();
    try self.emit("pub const NOT_ACCEPTABLE = 406;\n");
    try self.emitIndent();
    try self.emit("pub const PROXY_AUTHENTICATION_REQUIRED = 407;\n");
    try self.emitIndent();
    try self.emit("pub const REQUEST_TIMEOUT = 408;\n");
    try self.emitIndent();
    try self.emit("pub const CONFLICT = 409;\n");
    try self.emitIndent();
    try self.emit("pub const GONE = 410;\n");
    try self.emitIndent();
    try self.emit("pub const LENGTH_REQUIRED = 411;\n");
    try self.emitIndent();
    try self.emit("pub const PRECONDITION_FAILED = 412;\n");
    try self.emitIndent();
    try self.emit("pub const REQUEST_ENTITY_TOO_LARGE = 413;\n");
    try self.emitIndent();
    try self.emit("pub const REQUEST_URI_TOO_LONG = 414;\n");
    try self.emitIndent();
    try self.emit("pub const UNSUPPORTED_MEDIA_TYPE = 415;\n");
    try self.emitIndent();
    try self.emit("pub const REQUESTED_RANGE_NOT_SATISFIABLE = 416;\n");
    try self.emitIndent();
    try self.emit("pub const EXPECTATION_FAILED = 417;\n");
    try self.emitIndent();
    try self.emit("pub const IM_A_TEAPOT = 418;\n");
    try self.emitIndent();
    try self.emit("pub const MISDIRECTED_REQUEST = 421;\n");
    try self.emitIndent();
    try self.emit("pub const UNPROCESSABLE_ENTITY = 422;\n");
    try self.emitIndent();
    try self.emit("pub const LOCKED = 423;\n");
    try self.emitIndent();
    try self.emit("pub const FAILED_DEPENDENCY = 424;\n");
    try self.emitIndent();
    try self.emit("pub const TOO_EARLY = 425;\n");
    try self.emitIndent();
    try self.emit("pub const UPGRADE_REQUIRED = 426;\n");
    try self.emitIndent();
    try self.emit("pub const PRECONDITION_REQUIRED = 428;\n");
    try self.emitIndent();
    try self.emit("pub const TOO_MANY_REQUESTS = 429;\n");
    try self.emitIndent();
    try self.emit("pub const REQUEST_HEADER_FIELDS_TOO_LARGE = 431;\n");
    try self.emitIndent();
    try self.emit("pub const UNAVAILABLE_FOR_LEGAL_REASONS = 451;\n");
    try self.emitIndent();
    try self.emit("pub const INTERNAL_SERVER_ERROR = 500;\n");
    try self.emitIndent();
    try self.emit("pub const NOT_IMPLEMENTED = 501;\n");
    try self.emitIndent();
    try self.emit("pub const BAD_GATEWAY = 502;\n");
    try self.emitIndent();
    try self.emit("pub const SERVICE_UNAVAILABLE = 503;\n");
    try self.emitIndent();
    try self.emit("pub const GATEWAY_TIMEOUT = 504;\n");
    try self.emitIndent();
    try self.emit("pub const HTTP_VERSION_NOT_SUPPORTED = 505;\n");
    try self.emitIndent();
    try self.emit("pub const VARIANT_ALSO_NEGOTIATES = 506;\n");
    try self.emitIndent();
    try self.emit("pub const INSUFFICIENT_STORAGE = 507;\n");
    try self.emitIndent();
    try self.emit("pub const LOOP_DETECTED = 508;\n");
    try self.emitIndent();
    try self.emit("pub const NOT_EXTENDED = 510;\n");
    try self.emitIndent();
    try self.emit("pub const NETWORK_AUTHENTICATION_REQUIRED = 511;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

// ============================================================================
// HTTP Response type (helper)
// ============================================================================

/// HTTPResponse type used internally
pub fn genHTTPResponseType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("const HTTPResponse = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("status: i64 = 200,\n");
    try self.emitIndent();
    try self.emit("reason: []const u8 = \"OK\",\n");
    try self.emitIndent();
    try self.emit("pub fn read(__self: *@This()) []const u8 { return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn getheader(__self: *@This(), name: []const u8) ?[]const u8 { _ = name; return null; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};");
}
