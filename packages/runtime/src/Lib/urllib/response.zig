//! Python 'urllib.response' module - Response class
//!
//! Provides HTTP response handling.
//!
//! Mirrors: CPython Lib/urllib/response.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// HTTP response
pub const Response = struct {
    url: []const u8,
    status: u16,
    reason: []const u8,
    headers: hashmap_helper.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn read(self: *Response) []const u8 {
        return self.body;
    }

    pub fn getcode(self: *Response) u16 {
        return self.status;
    }

    pub fn getheader(self: *Response, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn geturl(self: *Response) []const u8 {
        return self.url;
    }

    pub fn close(self: *Response) void {
        self.allocator.free(self.body);
        self.allocator.free(self.url);
        self.headers.deinit();
    }
};
