/// Python urllib module - URL handling
const std = @import("std");
const h = @import("mod_helper.zig");

const urlparseBody = "; var _scheme: []const u8 = \"\"; var _netloc: []const u8 = \"\"; var _path: []const u8 = _url; var _query: []const u8 = \"\"; var _fragment: []const u8 = \"\"; if (std.mem.indexOf(u8, _url, \"://\")) |scheme_end| { _scheme = _url[0..scheme_end]; const rest = _url[scheme_end + 3 ..]; if (std.mem.indexOfScalar(u8, rest, '/')) |path_start| { _netloc = rest[0..path_start]; _path = rest[path_start..]; } else { _netloc = rest; _path = \"\"; } } if (std.mem.indexOfScalar(u8, _path, '?')) |q| { _query = _path[q + 1 ..]; _path = _path[0..q]; } if (std.mem.indexOfScalar(u8, _query, '#')) |f| { _fragment = _query[f + 1 ..]; _query = _query[0..f]; } break :blk struct { scheme: []const u8, netloc: []const u8, path: []const u8, params: []const u8 = \"\", query: []const u8, fragment: []const u8, pub fn geturl(__self: @This()) []const u8 { _ = __self; return \"\"; } }{ .scheme = _scheme, .netloc = _netloc, .path = _path, .query = _query, .fragment = _fragment }; }";
const urlunparseBody = "; var _result: std.ArrayList(u8) = .{}; if (_parts.scheme.len > 0) { _result.appendSlice(__global_allocator, _parts.scheme) catch {}; _result.appendSlice(__global_allocator, \"://\") catch {}; } _result.appendSlice(__global_allocator, _parts.netloc) catch {}; _result.appendSlice(__global_allocator, _parts.path) catch {}; if (_parts.query.len > 0) { _result.append(__global_allocator, '?') catch {}; _result.appendSlice(__global_allocator, _parts.query) catch {}; } break :blk _result.items; }";
const quoteBody = "; var _result: std.ArrayList(u8) = .{}; const _safe = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~\"; for (_s) |c| { if (std.mem.indexOfScalar(u8, _safe, c) != null) { _result.append(__global_allocator, c) catch {}; } else { const hex = \"0123456789ABCDEF\"; _result.append(__global_allocator, '%') catch {}; _result.append(__global_allocator, hex[c >> 4]) catch {}; _result.append(__global_allocator, hex[c & 0xf]) catch {}; } } break :blk _result.items; }";
const unquoteBody = "; var _result: std.ArrayList(u8) = .{}; var _i: usize = 0; while (_i < _s.len) { if (_s[_i] == '%' and _i + 2 < _s.len) { const hi = std.fmt.charToDigit(_s[_i + 1], 16) catch { _i += 1; continue; }; const lo = std.fmt.charToDigit(_s[_i + 2], 16) catch { _i += 1; continue; }; _result.append(__global_allocator, (hi << 4) | lo) catch {}; _i += 3; } else { _result.append(__global_allocator, _s[_i]) catch {}; _i += 1; } } break :blk _result.items; }";
const urljoinBody = "; if (std.mem.indexOf(u8, _url, \"://\") != null) break :blk _url; if (_url.len > 0 and _url[0] == '/') { if (std.mem.indexOf(u8, _base, \"://\")) |i| { if (std.mem.indexOfScalarPos(u8, _base, i + 3, '/')) |j| { var r: std.ArrayList(u8) = .{}; r.appendSlice(__global_allocator, _base[0..j]) catch {}; r.appendSlice(__global_allocator, _url) catch {}; break :blk r.items; } } } break :blk _url; }";
const parseQsBody = "; var _result = hashmap_helper.StringHashMap([]const u8).init(__global_allocator); var _pairs = std.mem.splitScalar(u8, _qs, '&'); while (_pairs.next()) |pair| { if (std.mem.indexOfScalar(u8, pair, '=')) |eq| { _result.put(pair[0..eq], pair[eq + 1 ..]) catch {}; } } break :blk _result; }";
const parseQslBody = "; var _result: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var _pairs = std.mem.splitScalar(u8, _qs, '&'); while (_pairs.next()) |pair| { if (std.mem.indexOfScalar(u8, pair, '=')) |eq| { _result.append(__global_allocator, .{ pair[0..eq], pair[eq + 1 ..] }) catch {}; } } break :blk _result.items; }";

const genQuote = h.wrap("blk: { const _s = ", quoteBody, "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "urlparse", h.wrap("blk: { const _url = ", urlparseBody, ".{ .scheme = \"\", .netloc = \"\", .path = \"\", .query = \"\", .fragment = \"\" }") },
    .{ "urlunparse", h.wrap("blk: { const _parts = ", urlunparseBody, "\"\"") },
    .{ "urlencode", h.discard("\"\"") },
    .{ "quote", genQuote }, .{ "quote_plus", genQuote },
    .{ "unquote", h.wrap("blk: { const _s = ", unquoteBody, "\"\"") },
    .{ "unquote_plus", h.wrap("blk: { const _s = ", unquoteBody, "\"\"") },
    .{ "urljoin", h.wrap2("blk: { const _base = ", "; const _url = ", urljoinBody, "\"\"") },
    .{ "parse_qs", h.wrap("blk: { const _qs = ", parseQsBody, "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "parse_qsl", h.wrap("blk: { const _qs = ", parseQslBody, "&.{}") },
});
