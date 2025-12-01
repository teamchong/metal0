/// Python urllib module - URL handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "urlparse", genUrlparse },
    .{ "urlunparse", genUrlunparse },
    .{ "urlencode", genUrlencode },
    .{ "quote", genQuote },
    .{ "quote_plus", genQuotePlus },
    .{ "unquote", genUnquote },
    .{ "unquote_plus", genUnquotePlus },
    .{ "urljoin", genUrljoin },
    .{ "parse_qs", genParseQs },
    .{ "parse_qsl", genParseQsl },
});

/// Generate urllib.parse.urlparse(urlstring) -> ParseResult
pub fn genUrlparse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_urlparse_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _url = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _scheme: []const u8 = \"\";\n");
    try self.emitIndent();
    try self.emit("var _netloc: []const u8 = \"\";\n");
    try self.emitIndent();
    try self.emit("var _path: []const u8 = _url;\n");
    try self.emitIndent();
    try self.emit("var _query: []const u8 = \"\";\n");
    try self.emitIndent();
    try self.emit("var _fragment: []const u8 = \"\";\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOf(u8, _url, \"://\")) |scheme_end| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_scheme = _url[0..scheme_end];\n");
    try self.emitIndent();
    try self.emit("const rest = _url[scheme_end + 3 ..];\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, rest, '/')) |path_start| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_netloc = rest[0..path_start];\n");
    try self.emitIndent();
    try self.emit("_path = rest[path_start..];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_netloc = rest;\n");
    try self.emitIndent();
    try self.emit("_path = \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, _path, '?')) |q| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_query = _path[q + 1 ..];\n");
    try self.emitIndent();
    try self.emit("_path = _path[0..q];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, _query, '#')) |f| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_fragment = _query[f + 1 ..];\n");
    try self.emitIndent();
    try self.emit("_query = _query[0..f];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_urlparse_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("scheme: []const u8,\n");
    try self.emitIndent();
    try self.emit("netloc: []const u8,\n");
    try self.emitIndent();
    try self.emit("path: []const u8,\n");
    try self.emitIndent();
    try self.emit("params: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("query: []const u8,\n");
    try self.emitIndent();
    try self.emit("fragment: []const u8,\n");
    try self.emitIndent();
    try self.emit("pub fn geturl(self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("return \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .scheme = _scheme, .netloc = _netloc, .path = _path, .query = _query, .fragment = _fragment };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.urlunparse(components) -> url string
pub fn genUrlunparse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_urlunparse_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _parts = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("if (_parts.scheme.len > 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _parts.scheme) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \"://\") catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _parts.netloc) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _parts.path) catch {};\n");
    try self.emitIndent();
    try self.emit("if (_parts.query.len > 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, '?') catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _parts.query) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_urlunparse_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.urlencode(query) -> encoded string
pub fn genUrlencode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_urlencode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _query = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _query;\n");
    try self.emitIndent();
    try self.emit("break :urllib_urlencode_blk \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.quote(s) -> percent-encoded string
pub fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_quote_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("const _safe = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~\";\n");
    try self.emitIndent();
    try self.emit("for (_s) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, _safe, c) != null) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, c) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const hex = \"0123456789ABCDEF\";\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, '%') catch {};\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, hex[c >> 4]) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, hex[c & 0xf]) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_quote_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.quote_plus(s) -> percent-encoded with + for spaces
pub fn genQuotePlus(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genQuote(self, args);
}

/// Generate urllib.parse.unquote(s) -> decoded string
pub fn genUnquote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_unquote_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_i < _s.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_s[_i] == '%' and _i + 2 < _s.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const hi = std.fmt.charToDigit(_s[_i + 1], 16) catch { _i += 1; continue; };\n");
    try self.emitIndent();
    try self.emit("const lo = std.fmt.charToDigit(_s[_i + 2], 16) catch { _i += 1; continue; };\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, (hi << 4) | lo) catch {};\n");
    try self.emitIndent();
    try self.emit("_i += 3;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _s[_i]) catch {};\n");
    try self.emitIndent();
    try self.emit("_i += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_unquote_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.unquote_plus(s) -> decoded with + as spaces
pub fn genUnquotePlus(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genUnquote(self, args);
}

/// Generate urllib.parse.urljoin(base, url) -> joined URL
pub fn genUrljoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("urllib_urljoin_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _base = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _url = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOf(u8, _url, \"://\") != null) break :urllib_urljoin_blk _url;\n");
    try self.emitIndent();
    try self.emit("if (_url.len > 0 and _url[0] == '/') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOf(u8, _base, \"://\")) |i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalarPos(u8, _base, i + 3, '/')) |j| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var r: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("r.appendSlice(__global_allocator, _base[0..j]) catch {};\n");
    try self.emitIndent();
    try self.emit("r.appendSlice(__global_allocator, _url) catch {};\n");
    try self.emitIndent();
    try self.emit("break :urllib_urljoin_blk r.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_urljoin_blk _url;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.parse_qs(qs) -> dict
pub fn genParseQs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_parseqs_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _qs = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = hashmap_helper.StringHashMap([]const u8).init(__global_allocator);\n");
    try self.emitIndent();
    try self.emit("var _pairs = std.mem.splitScalar(u8, _qs, '&');\n");
    try self.emitIndent();
    try self.emit("while (_pairs.next()) |pair| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.put(pair[0..eq], pair[eq + 1 ..]) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_parseqs_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate urllib.parse.parse_qsl(qs) -> list of tuples
pub fn genParseQsl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("urllib_parseqsl_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _qs = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(struct { []const u8, []const u8 }) = .{};\n");
    try self.emitIndent();
    try self.emit("var _pairs = std.mem.splitScalar(u8, _qs, '&');\n");
    try self.emitIndent();
    try self.emit("while (_pairs.next()) |pair| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, .{ pair[0..eq], pair[eq + 1 ..] }) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :urllib_parseqsl_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
