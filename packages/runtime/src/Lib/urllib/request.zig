//! Python 'urllib.request' module - URL request handling
//!
//! Provides HTTP request functionality, including Request/Response classes and handlers.
//!
//! Mirrors: CPython Lib/urllib/request.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const response = @import("response.zig");

pub const Response = response.Response;

/// URL opener
pub const OpenerDirector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OpenerDirector {
        return .{ .allocator = allocator };
    }

    pub fn open(self: *OpenerDirector, url: []const u8) !Response {
        return urlopen(self.allocator, url);
    }
};

/// HTTP request
pub const Request = struct {
    url: []const u8,
    method: []const u8,
    headers: hashmap_helper.StringHashMap([]const u8),
    data: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) Request {
        return .{
            .url = url,
            .method = "GET",
            .headers = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .data = null,
        };
    }

    pub fn addHeader(self: *Request, key: []const u8, value: []const u8) !void {
        try self.headers.put(key, value);
    }

    pub fn getMethod(self: *Request) []const u8 {
        return self.method;
    }

    pub fn getFullUrl(self: *Request) []const u8 {
        return self.url;
    }
};

/// Simple URL fetch using std.http.Client
pub fn urlopen(allocator: std.mem.Allocator, url: []const u8) !Response {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch return error.URLError;

    var header_buf: [4096]u8 = undefined;
    var req = client.open(.GET, uri, .{
        .server_header_buffer = &header_buf,
    }) catch return error.URLError;
    defer req.deinit();

    req.send() catch return error.URLError;
    req.wait() catch return error.URLError;

    const body = req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch return error.URLError;

    var headers = hashmap_helper.StringHashMap([]const u8).init(allocator);

    return Response{
        .url = try allocator.dupe(u8, url),
        .status = @intFromEnum(req.status),
        .reason = "OK",
        .headers = headers,
        .body = body,
        .allocator = allocator,
    };
}

/// URL retrieve to file
pub fn urlretrieve(allocator: std.mem.Allocator, url: []const u8, filename: ?[]const u8) !struct { filename: []const u8, headers: hashmap_helper.StringHashMap([]const u8) } {
    // Fetch the URL
    var resp = try urlopen(allocator, url);
    defer resp.close();

    // Determine output filename
    const out_filename = filename orelse blk: {
        // Extract filename from URL path
        const uri = std.Uri.parse(url) catch return error.URLError;
        const path = uri.path.percent_encoded;
        if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
            break :blk try allocator.dupe(u8, path[idx + 1 ..]);
        }
        break :blk try allocator.dupe(u8, "downloaded_file");
    };

    // Write to file
    const file = try std.fs.cwd().createFile(out_filename, .{});
    defer file.close();
    try file.writeAll(resp.body);

    return .{
        .filename = out_filename,
        .headers = resp.headers,
    };
}

/// Default opener (module-level)
var default_opener: ?*OpenerDirector = null;

/// Install opener as the default for urlopen
pub fn install_opener(opener: ?*OpenerDirector) void {
    default_opener = opener;
}

/// Get the currently installed opener
pub fn get_opener() ?*OpenerDirector {
    return default_opener;
}

/// Build opener with handlers
pub fn build_opener(allocator: std.mem.Allocator) OpenerDirector {
    return OpenerDirector.init(allocator);
}
