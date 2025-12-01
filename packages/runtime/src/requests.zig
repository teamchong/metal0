//! Python requests library implementation
//! Uses unified h2 client (HTTP/1.1 for http://, HTTP/2 for https://)

const std = @import("std");
const runtime = @import("runtime.zig");
const h2 = @import("h2");

/// Thread-local allocator for requests (set by generated main)
var _allocator: ?std.mem.Allocator = null;

/// Initialize requests module with allocator (called from generated main)
pub fn init(allocator: std.mem.Allocator) void {
    _allocator = allocator;
}

fn getAllocator() std.mem.Allocator {
    return _allocator orelse std.heap.page_allocator;
}

/// Response object mimicking Python requests.Response
pub const Response = struct {
    allocator: std.mem.Allocator,
    status_code: u16,
    text: []const u8,
    ok: bool, // True if status_code is 200-299
    _json_cache: ?*runtime.PyObject,

    pub fn create(allocator: std.mem.Allocator, status_code: u16, body: []const u8) !*Response {
        const resp = try allocator.create(Response);
        resp.* = .{
            .allocator = allocator,
            .status_code = status_code,
            .text = try allocator.dupe(u8, body),
            .ok = status_code >= 200 and status_code < 300,
            ._json_cache = null,
        };
        return resp;
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.text);
        if (self._json_cache) |cache| {
            runtime.decref(cache, self.allocator);
        }
        self.allocator.destroy(self);
    }

    /// Parse body as JSON (mimics response.json())
    pub fn json(self: *Response) !*runtime.PyObject {
        if (self._json_cache) |cache| return cache;

        const result = try runtime.json.loads(self.allocator, self.text);
        self._json_cache = result;
        return result;
    }
};

/// HTTP GET request (mimics requests.get)
pub fn get(url: []const u8) !*Response {
    const allocator = getAllocator();

    var client = h2.Client.init(allocator);
    defer client.deinit();

    var response = client.get(url) catch |err| {
        std.debug.print("HTTP GET error: {}\n", .{err});
        return error.ConnectionFailed;
    };
    defer response.deinit();

    return try Response.create(allocator, response.status, response.body);
}

/// HTTP POST request (mimics requests.post)
pub fn post(url: []const u8, data: ?[]const u8) !*Response {
    const allocator = getAllocator();

    var client = h2.Client.init(allocator);
    defer client.deinit();

    var response = client.post(url, data orelse "", "application/x-www-form-urlencoded") catch |err| {
        std.debug.print("HTTP POST error: {}\n", .{err});
        return error.ConnectionFailed;
    };
    defer response.deinit();

    return try Response.create(allocator, response.status, response.body);
}

/// HTTP PUT request (mimics requests.put)
pub fn put(url: []const u8, data: ?[]const u8) !*Response {
    const allocator = getAllocator();

    var client = h2.Client.init(allocator);
    defer client.deinit();

    var response = client.request("PUT", url, &[_]h2.ExtraHeader{}, data) catch |err| {
        std.debug.print("HTTP PUT error: {}\n", .{err});
        return error.ConnectionFailed;
    };
    defer response.deinit();

    return try Response.create(allocator, response.status, response.body);
}

/// HTTP DELETE request (mimics requests.delete)
pub fn delete(url: []const u8) !*Response {
    const allocator = getAllocator();

    var client = h2.Client.init(allocator);
    defer client.deinit();

    var response = client.request("DELETE", url, &[_]h2.ExtraHeader{}, null) catch |err| {
        std.debug.print("HTTP DELETE error: {}\n", .{err});
        return error.ConnectionFailed;
    };
    defer response.deinit();

    return try Response.create(allocator, response.status, response.body);
}
