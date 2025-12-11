//! CPython source: Lib/mailbox.py
//!
//! MMDF format mailbox implementation.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const message = @import("message.zig");
const mailbox_base = @import("mailbox_base.zig");

pub const Message = message.Message;

// ============================================================================
// MMDF Mailbox
// ============================================================================

/// MMDF format mailbox (like mbox but with different separator)
pub const MMDF = struct {
    const Self = @This();

    base: mailbox_base.Mailbox(MMDFMessage),

    pub const MMDFMessage = struct {
        base: Message,

        pub fn init(allocator: std.mem.Allocator) MMDFMessage {
            return .{
                .base = Message.init(allocator),
            };
        }

        pub fn deinit(self: *MMDFMessage) void {
            self.base.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, factory: ?*const fn (std.mem.Allocator) MMDFMessage, create: bool) !Self {
        return .{
            .base = try mailbox_base.Mailbox(MMDFMessage).init(allocator, path, factory, create),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn add(self: *Self, msg: MMDFMessage) !usize {
        return self.base.add(msg);
    }

    pub fn get(self: *Self, key: usize) ?MMDFMessage {
        return self.base.get(key);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};
