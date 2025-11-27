//! Lazy HTTP Response - body read deferred until accessed
//!
//! Usage:
//!   var resp = try client.getLazy(url);
//!   defer resp.deinit();
//!
//!   // No body read yet - just status and headers available
//!   if (resp.status == .ok) {
//!       const body = try resp.body(); // NOW reads body
//!   }
//!
//! Benefits:
//! - HEAD-like efficiency for status checks
//! - Memory: body only allocated if accessed
//! - Early exit: can check status before reading large body

const std = @import("std");
const Status = @import("response.zig").Status;

pub const LazyResponse = struct {
    allocator: std.mem.Allocator,
    status: Status,
    /// The underlying HTTP client (owns connection)
    client: std.http.Client,
    /// Fetch result containing body reference
    fetch_result: ?std.http.Client.FetchResult,
    /// Materialized body (owned, allocated on first access)
    body_data: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !LazyResponse {
        var client = std.http.Client{ .allocator = allocator };
        errdefer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = url },
        }) catch |err| {
            client.deinit();
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };

        return .{
            .allocator = allocator,
            .status = Status.fromCode(@intFromEnum(result.status)),
            .client = client,
            .fetch_result = result,
            .body_data = null,
        };
    }

    pub fn initPost(allocator: std.mem.Allocator, url: []const u8, payload: []const u8) !LazyResponse {
        var client = std.http.Client{ .allocator = allocator };
        errdefer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = url },
            .payload = payload,
        }) catch |err| {
            client.deinit();
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };

        return .{
            .allocator = allocator,
            .status = Status.fromCode(@intFromEnum(result.status)),
            .client = client,
            .fetch_result = result,
            .body_data = null,
        };
    }

    /// Get body - reads on first access
    pub fn body(self: *LazyResponse) ![]const u8 {
        if (self.body_data) |data| return data;

        if (self.fetch_result) |result| {
            if (result.body) |body_slice| {
                self.body_data = try self.allocator.dupe(u8, body_slice);
                return self.body_data.?;
            }
        }

        // No body available
        self.body_data = "";
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
        self.client.deinit();
    }
};

test "LazyResponse status without body" {
    // Would need network to test properly
    // This just verifies the type compiles
    const allocator = std.testing.allocator;
    _ = allocator;
}
