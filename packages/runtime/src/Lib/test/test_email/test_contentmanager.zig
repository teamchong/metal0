//! test.test_email.test_contentmanager - Content manager tests
const std = @import("std");

pub const ContentManager = struct {
    handlers: std.StringHashMap(Handler),
    allocator: std.mem.Allocator,
    
    pub const Handler = struct {
        get_content: ?*const fn (*Message) []const u8 = null,
        set_content: ?*const fn (*Message, []const u8) void = null,
    };
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        var self = @This(){
            .allocator = allocator,
            .handlers = std.StringHashMap(Handler).init(allocator),
        };
        self.registerDefaults() catch {};
        return self;
    }
    
    pub fn deinit(self: *@This()) void {
        self.handlers.deinit();
    }
    
    fn registerDefaults(self: *@This()) !void {
        try self.handlers.put("text/plain", .{});
        try self.handlers.put("text/html", .{});
        try self.handlers.put("application/octet-stream", .{});
    }
    
    pub fn getContent(self: @This(), msg: *Message) []const u8 {
        const ct = msg.getContentType() orelse "text/plain";
        if (self.handlers.get(ct)) |h| {
            if (h.get_content) |f| return f(msg);
        }
        return msg.body;
    }
    
    pub fn setContent(self: @This(), msg: *Message, content: []const u8) void {
        const ct = msg.getContentType() orelse "text/plain";
        if (self.handlers.get(ct)) |h| {
            if (h.set_content) |f| {
                f(msg, content);
                return;
            }
        }
        msg.body = content;
    }
    
    pub fn addHandler(self: *@This(), content_type: []const u8, handler: Handler) !void {
        try self.handlers.put(content_type, handler);
    }
};

pub const Message = struct {
    headers: std.StringHashMap([]const u8),
    body: []const u8 = "",
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.headers.deinit();
    }
    
    pub fn getContentType(self: @This()) ?[]const u8 {
        return self.headers.get("Content-Type");
    }
};

test "content_manager_init" {
    var cm = ContentManager.init(std.testing.allocator);
    defer cm.deinit();
    try std.testing.expect(cm.handlers.contains("text/plain"));
}

test "content_manager_get_content" {
    var cm = ContentManager.init(std.testing.allocator);
    defer cm.deinit();
    var msg = Message.init(std.testing.allocator);
    defer msg.deinit();
    msg.body = "Test content";
    try std.testing.expectEqualStrings("Test content", cm.getContent(&msg));
}
