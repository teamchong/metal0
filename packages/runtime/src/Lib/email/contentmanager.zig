//! email.contentmanager - Content manager for getting/setting message content
//! Reference: cpython/Lib/email/contentmanager.py
//!
//! CPython __all__: ['ContentManager', 'raw_data_manager']

const std = @import("std");
const Message = @import("message.zig").Message;
const charset_mod = @import("charset.zig");

// ============================================================================
// ContentManager
// ============================================================================

/// ContentManager - Manages getting and setting message content
/// CPython: class ContentManager
pub const ContentManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    get_handlers: std.ArrayList(GetHandler),
    set_handlers: std.ArrayList(SetHandler),

    pub const GetHandler = struct {
        content_type: []const u8,
        handler: *const fn (*Message) anyerror![]u8,
    };

    pub const SetHandler = struct {
        type_name: []const u8,
        handler: *const fn (*Message, []const u8) anyerror!void,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .get_handlers = .{},
            .set_handlers = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.get_handlers.deinit(self.allocator);
        self.set_handlers.deinit(self.allocator);
    }

    /// Register a get handler for a content type
    /// CPython: def add_get_handler(self, key, handler)
    pub fn addGetHandler(self: *Self, content_type: []const u8, handler: *const fn (*Message) anyerror![]u8) !void {
        try self.get_handlers.append(self.allocator, .{
            .content_type = content_type,
            .handler = handler,
        });
    }

    /// Register a set handler for a type
    /// CPython: def add_set_handler(self, typekey, handler)
    pub fn addSetHandler(self: *Self, type_name: []const u8, handler: *const fn (*Message, []const u8) anyerror!void) !void {
        try self.set_handlers.append(self.allocator, .{
            .type_name = type_name,
            .handler = handler,
        });
    }

    /// Get content from message
    /// CPython: def get_content(self, msg, *args, **kw)
    pub fn getContent(self: *Self, msg: *Message) !?[]u8 {
        const content_type = msg.getContentType();

        // Look for matching handler
        for (self.get_handlers.items) |h| {
            if (std.mem.eql(u8, h.content_type, content_type)) {
                return h.handler(msg);
            }
        }

        // Default: return payload as-is
        if (msg.getPayload()) |payload| {
            return self.allocator.dupe(u8, payload);
        }
        return null;
    }

    /// Set content on message
    /// CPython: def set_content(self, msg, obj, *args, **kw)
    pub fn setContent(self: *Self, msg: *Message, content: []const u8, options: SetContentOptions) !void {
        // Set content type if provided
        if (options.maintype) |maintype| {
            const subtype = options.subtype orelse "plain";
            var ct_buf: [128]u8 = undefined;
            const ct = std.fmt.bufPrint(&ct_buf, "{s}/{s}", .{ maintype, subtype }) catch "text/plain";
            try msg.set("Content-Type", ct);
        }

        // Set disposition if provided
        if (options.disposition) |disp| {
            var disp_buf: [256]u8 = undefined;
            if (options.filename) |filename| {
                const disp_str = std.fmt.bufPrint(&disp_buf, "{s}; filename=\"{s}\"", .{ disp, filename }) catch disp;
                try msg.set("Content-Disposition", disp_str);
            } else {
                try msg.set("Content-Disposition", disp);
            }
        }

        // Set charset if provided
        if (options.charset) |cs| {
            if (msg.get("Content-Type")) |ct| {
                var new_ct_buf: [256]u8 = undefined;
                const new_ct = std.fmt.bufPrint(&new_ct_buf, "{s}; charset=\"{s}\"", .{ ct, cs }) catch ct;
                try msg.set("Content-Type", new_ct);
            }
        }

        // Set payload
        try msg.setPayload(content);
    }
};

/// Options for setContent
pub const SetContentOptions = struct {
    maintype: ?[]const u8 = null,
    subtype: ?[]const u8 = null,
    charset: ?[]const u8 = null,
    disposition: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    cid: ?[]const u8 = null,
    params: ?[]const HeaderParam = null,
};

pub const HeaderParam = struct {
    name: []const u8,
    value: []const u8,
};

// ============================================================================
// Default Content Manager
// ============================================================================

/// Default raw data manager
/// CPython: raw_data_manager = ContentManager()
var _raw_data_manager: ?ContentManager = null;

pub fn raw_data_manager(allocator: std.mem.Allocator) *ContentManager {
    if (_raw_data_manager == null) {
        _raw_data_manager = ContentManager.init(allocator);
    }
    return &_raw_data_manager.?;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get message content as string
/// CPython: def get_text_content(msg)
pub fn getTextContent(msg: *Message) ?[]const u8 {
    return msg.getPayload();
}

/// Get message content as bytes
/// CPython: def get_non_text_content(msg)
pub fn getNonTextContent(allocator: std.mem.Allocator, msg: *Message) !?[]u8 {
    if (msg.getPayload()) |payload| {
        return allocator.dupe(u8, payload);
    }
    return null;
}

/// Set text content
/// CPython: def set_text_content(msg, string, subtype='plain', charset='utf-8')
pub fn setTextContent(msg: *Message, content: []const u8, subtype: []const u8, _charset: []const u8) !void {
    var ct_buf: [128]u8 = undefined;
    const ct = std.fmt.bufPrint(&ct_buf, "text/{s}; charset=\"utf-8\"", .{subtype}) catch "text/plain; charset=\"utf-8\"";
    try msg.set("Content-Type", ct);
    try msg.setPayload(content);
}

/// Set binary content
/// CPython: def set_bytes_content(msg, data, maintype, subtype)
pub fn setBytesContent(msg: *Message, content: []const u8, maintype: []const u8, subtype: []const u8) !void {
    var ct_buf: [128]u8 = undefined;
    const ct = std.fmt.bufPrint(&ct_buf, "{s}/{s}", .{ maintype, subtype }) catch "application/octet-stream";
    try msg.set("Content-Type", ct);
    try msg.set("Content-Transfer-Encoding", "base64");
    try msg.setPayload(content);
}

// ============================================================================
// Tests
// ============================================================================

test "ContentManager init" {
    const allocator = std.testing.allocator;
    var cm = ContentManager.init(allocator);
    defer cm.deinit();
}

test "setTextContent" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    try setTextContent(&msg, "Hello, World!", "plain", "utf-8");
    try std.testing.expectEqualStrings("Hello, World!", msg.getPayload().?);
}
