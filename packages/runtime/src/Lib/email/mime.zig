//! MIME message classes
//!
//! Provides MIME message types for creating various types of email messages.

const std = @import("std");
const Message = @import("message.zig").Message;

/// MIME text message
pub const MIMEText = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, text: []const u8, subtype: []const u8, charset: []const u8) !MIMEText {
        var msg = Message.init(allocator);

        // Build Content-Type header
        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "text/{s}; charset=\"{s}\"", .{ subtype, charset });
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");
        try msg.setPayload(text);

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEText) void {
        self.message.deinit();
    }
};

/// MIME multipart message
pub const MIMEMultipart = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, subtype: []const u8, boundary: ?[]const u8) !MIMEMultipart {
        var msg = Message.init(allocator);

        // Generate boundary if not provided
        const actual_boundary = boundary orelse "===============boundary===============";

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "multipart/{s}; boundary=\"{s}\"", .{ subtype, actual_boundary });
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");

        // Initialize as multipart
        msg.payload = .{ .parts = .{} };

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEMultipart) void {
        self.message.deinit();
    }

    pub fn attach(self: *MIMEMultipart, part: *Message) !void {
        try self.message.attach(part);
    }
};

/// MIME base message
pub const MIMEBase = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, maintype: []const u8, subtype: []const u8) !MIMEBase {
        var msg = Message.init(allocator);

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "{s}/{s}", .{ maintype, subtype });
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEBase) void {
        self.message.deinit();
    }
};

/// MIME application message
pub const MIMEApplication = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEApplication {
        var msg = Message.init(allocator);

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "application/{s}", .{subtype});
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");
        try msg.set("Content-Transfer-Encoding", "base64");
        try msg.setPayload(data);

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEApplication) void {
        self.message.deinit();
    }
};

/// MIME image message
pub const MIMEImage = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEImage {
        var msg = Message.init(allocator);

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "image/{s}", .{subtype});
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");
        try msg.set("Content-Transfer-Encoding", "base64");
        try msg.setPayload(data);

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEImage) void {
        self.message.deinit();
    }
};

/// MIME audio message
pub const MIMEAudio = struct {
    message: Message,

    pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEAudio {
        var msg = Message.init(allocator);

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "audio/{s}", .{subtype});
        try msg.set("Content-Type", ct);
        try msg.set("MIME-Version", "1.0");
        try msg.set("Content-Transfer-Encoding", "base64");
        try msg.setPayload(data);

        return .{ .message = msg };
    }

    pub fn deinit(self: *MIMEAudio) void {
        self.message.deinit();
    }
};
