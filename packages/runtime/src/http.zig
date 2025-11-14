const std = @import("std");
const runtime = @import("runtime.zig");

pub const HttpResponse = struct {
    status: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HttpResponse) void {
        self.allocator.free(self.body);
    }
};

/// Async HTTP GET request
pub fn get(allocator: std.mem.Allocator, url: []const u8) !HttpResponse {
    // Parse URL
    const uri = try std.Uri.parse(url);

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Build request
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = try allocator.alloc(u8, 8192),
    });
    defer req.deinit();
    defer allocator.free(req.server_header_buffer);

    // Send request and wait for response
    try req.send();
    try req.finish();
    try req.wait();

    // Read response body
    var body = std.ArrayList(u8){};
    defer body.deinit(allocator);

    const reader = req.reader();
    try reader.readAllArrayList(&body, allocator, 10 * 1024 * 1024); // 10MB max

    return HttpResponse{
        .status = @intFromEnum(req.response.status),
        .body = try body.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Create PyString from HTTP response body
pub fn getAsPyString(allocator: std.mem.Allocator, url: []const u8) !*runtime.PyObject {
    var response = try get(allocator, url);
    defer response.deinit();

    return try runtime.PyString.create(allocator, response.body);
}

/// Create PyTuple of (status_code, body)
pub fn getAsResponse(allocator: std.mem.Allocator, url: []const u8) !*runtime.PyObject {
    var response = try get(allocator, url);
    defer response.deinit();

    // Create tuple: (status, body)
    const status_obj = try runtime.PyInt.create(allocator, @intCast(response.status));
    const body_obj = try runtime.PyString.create(allocator, response.body);

    const items = [_]*runtime.PyObject{ status_obj, body_obj };
    return try runtime.PyTuple.create(allocator, &items);
}
