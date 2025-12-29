/// Python urllib module - URL handling
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const urlparseBody = "var _scheme: []const u8 = \"\"; var _netloc: []const u8 = \"\"; var _path: []const u8 = __v; var _query: []const u8 = \"\"; var _fragment: []const u8 = \"\"; if (std.mem.indexOf(u8, __v, \"://\")) |scheme_end| { _scheme = __v[0..scheme_end]; const rest = __v[scheme_end + 3 ..]; if (std.mem.indexOfScalar(u8, rest, '/')) |path_start| { _netloc = rest[0..path_start]; _path = rest[path_start..]; } else { _netloc = rest; _path = \"\"; } } if (std.mem.indexOfScalar(u8, _path, '?')) |q| { _query = _path[q + 1 ..]; _path = _path[0..q]; } if (std.mem.indexOfScalar(u8, _query, '#')) |f| { _fragment = _query[f + 1 ..]; _query = _query[0..f]; }";
const urlparseResult = "struct { scheme: []const u8, netloc: []const u8, path: []const u8, params: []const u8 = \"\", query: []const u8, fragment: []const u8, pub fn geturl(__self: @This()) []const u8 { _ = __self; return \"\"; } }{ .scheme = _scheme, .netloc = _netloc, .path = _path, .query = _query, .fragment = _fragment }";
const urlunparseBody = "var _result: std.ArrayList(u8) = .{}; if (__v.scheme.len > 0) { _result.appendSlice(__global_allocator, __v.scheme) catch unreachable; _result.appendSlice(__global_allocator, \"://\") catch unreachable; } _result.appendSlice(__global_allocator, __v.netloc) catch unreachable; _result.appendSlice(__global_allocator, __v.path) catch unreachable; if (__v.query.len > 0) { _result.append(__global_allocator, '?') catch unreachable; _result.appendSlice(__global_allocator, __v.query) catch unreachable; }";
const quoteBody = "var _result: std.ArrayList(u8) = .{}; const _safe = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~\"; for (__v) |c| { if (std.mem.indexOfScalar(u8, _safe, c) != null) { _result.append(__global_allocator, c) catch unreachable; } else { const hex = \"0123456789ABCDEF\"; _result.append(__global_allocator, '%') catch unreachable; _result.append(__global_allocator, hex[c >> 4]) catch unreachable; _result.append(__global_allocator, hex[c & 0xf]) catch unreachable; } }";
const unquoteBody = "var _result: std.ArrayList(u8) = .{}; var _i: usize = 0; while (_i < __v.len) { if (__v[_i] == '%' and _i + 2 < __v.len) { const hi = std.fmt.charToDigit(__v[_i + 1], 16) catch { _i += 1; continue; }; const lo = std.fmt.charToDigit(__v[_i + 2], 16) catch { _i += 1; continue; }; _result.append(__global_allocator, (hi << 4) | lo) catch unreachable; _i += 3; } else { _result.append(__global_allocator, __v[_i]) catch unreachable; _i += 1; } }";
const parseQsBody = "var _result = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var _pairs = std.mem.splitScalar(u8, __v, '&'); while (_pairs.next()) |pair| { if (std.mem.indexOfScalar(u8, pair, '=')) |eq| { _result.put(pair[0..eq], pair[eq + 1 ..]) catch unreachable; } }";
const parseQslBody = "var _result: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var _pairs = std.mem.splitScalar(u8, __v, '&'); while (_pairs.next()) |pair| { if (std.mem.indexOfScalar(u8, pair, '=')) |eq| { _result.append(__global_allocator, .{ pair[0..eq], pair[eq + 1 ..] }) catch unreachable; } }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "urlparse", h.wrapBlk("urlp", urlparseBody, urlparseResult, ".{ .scheme = \"\", .netloc = \"\", .path = \"\", .query = \"\", .fragment = \"\" }") },
    .{ "urlunparse", h.wrapBlk("urlunp", urlunparseBody, "_result.items", "\"\"") },
    .{ "urlencode", h.discard("\"\"") },
    .{ "quote", h.wrapBlk("quote", quoteBody, "_result.items", "\"\"") },
    .{ "quote_plus", h.wrapBlk("quotep", quoteBody, "_result.items", "\"\"") },
    .{ "unquote", h.wrapBlk("unquote", unquoteBody, "_result.items", "\"\"") },
    .{ "unquote_plus", h.wrapBlk("unqp", unquoteBody, "_result.items", "\"\"") },
    .{ "urljoin", genUrljoin },
    .{ "parse_qs", h.wrapBlk("pqs", parseQsBody, "_result", "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "parse_qsl", h.wrapBlk("pqsl", parseQslBody, "_result.items", "&.{}") },
});

fn genUrljoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.write("\"\"");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("join", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _base = ");
            const output1 = try b2.getBodyDupe();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.write("; const _url = ");
                const output2 = try b3.getBodyDupe();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; if (std.mem.indexOf(u8, _url, \"://\") != null) break :{s} _url; if (_url.len > 0 and _url[0] == '/') {{ if (std.mem.indexOf(u8, _base, \"://\")) |i| {{ if (std.mem.indexOfScalarPos(u8, _base, i + 3, '/')) |j| {{ var r: std.ArrayList(u8) = .{{}}; r.appendSlice(__global_allocator, _base[0..j]) catch unreachable; r.appendSlice(__global_allocator, _url) catch unreachable; break :{s} r.items; }} }} }} break :{s} _url", .{ label, label, label });
                const output3 = try b3.getBodyDupe();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}
