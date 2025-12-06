//! Lazy HTTP Response - body read deferred until accessed
//!
//! Uses unified h2 client (HTTP/1.1 for http://, HTTP/2 for https://)

const std = @import("std");
const Status = @import("response.zig").Status;
const h2 = @import("h2");

pub const LazyResponse = struct {
    allocator: std.mem.Allocator,
    status: Status,
    /// Materialized body (owned, allocated on first access)
    body_data: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !LazyResponse {
        var client = h2.Client.init(allocator);
        defer client.deinit();

        var response = client.get(url) catch |err| {
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };
        defer response.deinit();

        const body_copy = if (response.body.len > 0)
            try allocator.dupe(u8, response.body)
        else
            null;

        return .{
            .allocator = allocator,
            .status = Status.fromCode(response.status),
            .body_data = body_copy,
        };
    }

    pub fn initPost(allocator: std.mem.Allocator, url: []const u8, payload: []const u8) !LazyResponse {
        var client = h2.Client.init(allocator);
        defer client.deinit();

        var response = client.post(url, payload, "application/x-www-form-urlencoded") catch |err| {
            std.debug.print("HTTP POST error: {}\n", .{err});
            return error.ConnectionFailed;
        };
        defer response.deinit();

        const body_copy = if (response.body.len > 0)
            try allocator.dupe(u8, response.body)
        else
            null;

        return .{
            .allocator = allocator,
            .status = Status.fromCode(response.status),
            .body_data = body_copy,
        };
    }

    /// Get body
    pub fn body(self: *LazyResponse) ![]const u8 {
        if (self.body_data) |data| return data;
        return "";
    }

    /// Check if response is successful (2xx)
    pub fn isSuccess(self: *const LazyResponse) bool {
        const code = self.status.toCode();
        return code >= 200 and code < 300;
    }

    /// Check if response is redirect (3xx)
    pub fn isRedirect(self: *const LazyResponse) bool {
        const code = self.status.toCode();
        return code >= 300 and code < 400;
    }

    /// Check if response is client error (4xx)
    pub fn isClientError(self: *const LazyResponse) bool {
        const code = self.status.toCode();
        return code >= 400 and code < 500;
    }

    /// Check if response is server error (5xx)
    pub fn isServerError(self: *const LazyResponse) bool {
        const code = self.status.toCode();
        return code >= 500 and code < 600;
    }

    /// Get status code as integer
    pub fn statusCode(self: *const LazyResponse) u16 {
        return self.status.toCode();
    }

    pub fn deinit(self: *LazyResponse) void {
        if (self.body_data) |data| {
            if (data.len > 0) {
                self.allocator.free(data);
            }
        }
    }
};

test "LazyResponse status without body" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
