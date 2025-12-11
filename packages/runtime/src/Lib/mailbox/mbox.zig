//! CPython source: Lib/mailbox.py
//!
//! mbox format mailbox implementation.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const message = @import("message.zig");
const mailbox_base = @import("mailbox_base.zig");

pub const Message = message.Message;

// ============================================================================
// Mbox Mailbox
// ============================================================================

/// mbox format mailbox
pub const Mbox = struct {
    const Self = @This();

    base: mailbox_base.Mailbox(MboxMessage),

    pub const MboxMessage = struct {
        base: Message,
        from_line: []const u8,

        pub fn init(allocator: std.mem.Allocator) MboxMessage {
            return .{
                .base = Message.init(allocator),
                .from_line = "",
            };
        }

        pub fn deinit(self: *MboxMessage) void {
            self.base.deinit();
        }

        pub fn setFrom(self: *MboxMessage, from_line: []const u8) void {
            self.from_line = from_line;
        }

        pub fn getFrom(self: *MboxMessage) []const u8 {
            return self.from_line;
        }
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, factory: ?*const fn (std.mem.Allocator) MboxMessage, create: bool) !Self {
        return .{
            .base = try mailbox_base.Mailbox(MboxMessage).init(allocator, path, factory, create),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn add(self: *Self, msg: MboxMessage) !usize {
        return self.base.add(msg);
    }

    pub fn get(self: *Self, key: usize) ?MboxMessage {
        return self.base.get(key);
    }

    pub fn remove(self: *Self, key: usize) !void {
        return self.base.remove(key);
    }

    pub fn len(self: *Self) usize {
        return self.base.len();
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Mbox init" {
    const allocator = std.testing.allocator;
    var mbox = try Mbox.init(allocator, "/tmp/test.mbox", null, true);
    defer mbox.deinit();

    try std.testing.expectEqual(@as(usize, 0), mbox.len());
}
