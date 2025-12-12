//! CPython source: Lib/mailbox.py
//!
//! Babyl format mailbox implementation (Emacs RMAIL).
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const message = @import("message.zig");
const mailbox_base = @import("mailbox_base.zig");

pub const Message = message.Message;

// ============================================================================
// Babyl Mailbox
// ============================================================================

/// Babyl format mailbox (Emacs RMAIL)
pub const Babyl = struct {
    const Self = @This();

    base: mailbox_base.Mailbox(BabylMessage),

    pub const BabylMessage = struct {
        base: Message,
        labels: std.ArrayList([]const u8),
        visible: bool,

        pub fn init(allocator: std.mem.Allocator) BabylMessage {
            return .{
                .base = Message.init(allocator),
                .labels = .{},
                .visible = true,
            };
        }

        pub fn deinit(self: *BabylMessage, allocator: std.mem.Allocator) void {
            self.base.deinit();
            self.labels.deinit(allocator);
        }

        pub fn getLabels(self: *BabylMessage) []const []const u8 {
            return self.labels.items;
        }

        pub fn addLabel(self: *BabylMessage, allocator: std.mem.Allocator, label: []const u8) !void {
            try self.labels.append(allocator, label);
        }

        pub fn removeLabel(self: *BabylMessage, label: []const u8) void {
            for (self.labels.items, 0..) |l, i| {
                if (std.mem.eql(u8, l, label)) {
                    _ = self.labels.orderedRemove(i);
                    return;
                }
            }
        }

        pub fn setVisible(self: *BabylMessage, visible: bool) void {
            self.visible = visible;
        }

        pub fn getVisible(self: *BabylMessage) bool {
            return self.visible;
        }
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, factory: ?*const fn (std.mem.Allocator) BabylMessage, create: bool) !Self {
        return .{
            .base = try mailbox_base.Mailbox(BabylMessage).init(allocator, path, factory, create),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// Get defined labels
    pub fn getLabels(self: *Self) []const []const u8 {
        _ = self;
        return &[_][]const u8{};
    }

    pub fn add(self: *Self, msg: BabylMessage) !usize {
        return self.base.add(msg);
    }

    pub fn get(self: *Self, key: usize) ?BabylMessage {
        return self.base.get(key);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Babyl message labels" {
    const allocator = std.testing.allocator;
    var msg = Babyl.BabylMessage.init(allocator);
    defer msg.deinit(allocator);

    try msg.addLabel(allocator, "answered");
    try std.testing.expectEqual(@as(usize, 1), msg.getLabels().len);
    try std.testing.expect(msg.getVisible());
}
