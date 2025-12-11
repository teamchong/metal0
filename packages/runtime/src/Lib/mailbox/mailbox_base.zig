//! CPython source: Lib/mailbox.py
//!
//! Base Mailbox interface for uniform access to mailboxes in different formats.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const errors = @import("errors.zig");

/// Base mailbox interface
pub fn Mailbox(comptime MessageType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        path: []const u8,
        messages: std.ArrayList(MessageType),
        factory: ?*const fn (std.mem.Allocator) MessageType,
        file: ?std.fs.File = null,
        is_locked: bool = false,
        modified: bool = false,

        pub fn init(allocator: std.mem.Allocator, path: []const u8, factory: ?*const fn (std.mem.Allocator) MessageType, create: bool) !Self {
            var self = Self{
                .allocator = allocator,
                .path = path,
                .messages = std.ArrayList(MessageType).init(allocator),
                .factory = factory,
                .file = null,
                .is_locked = false,
                .modified = false,
            };

            // Try to open existing file or create new one
            if (create) {
                self.file = std.fs.cwd().createFile(path, .{ .read = true }) catch null;
            } else {
                self.file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch null;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.messages.deinit();
        }

        /// Add a message
        pub fn add(self: *Self, message: MessageType) !usize {
            try self.messages.append(message);
            self.modified = true;
            return self.messages.items.len - 1;
        }

        /// Remove a message
        pub fn remove(self: *Self, key: usize) !void {
            if (key >= self.messages.items.len) {
                return errors.MailboxError.Error;
            }
            _ = self.messages.orderedRemove(key);
            self.modified = true;
        }

        /// Get a message
        pub fn get(self: *Self, key: usize) ?MessageType {
            if (key >= self.messages.items.len) return null;
            return self.messages.items[key];
        }

        /// Get message as string
        pub fn getString(self: *Self, key: usize) ?[]const u8 {
            if (key >= self.messages.items.len) return null;
            const msg = &self.messages.items[key];
            // Return the message body - for full conversion use asString()
            return msg.base.body;
        }

        /// Get number of messages
        pub fn len(self: *Self) usize {
            return self.messages.items.len;
        }

        /// Check if empty
        pub fn isEmpty(self: *Self) bool {
            return self.messages.items.len == 0;
        }

        /// Clear all messages
        pub fn clear(self: *Self) void {
            self.messages.clearRetainingCapacity();
        }

        /// Get all keys
        pub fn keys(self: *Self) ![]usize {
            var result = try self.allocator.alloc(usize, self.messages.items.len);
            for (0..self.messages.items.len) |i| {
                result[i] = i;
            }
            return result;
        }

        /// Iterate over values
        pub fn values(self: *Self) []MessageType {
            return self.messages.items;
        }

        /// Lock the mailbox using file locking
        pub fn lock(self: *Self) !void {
            if (self.is_locked) return;
            if (self.file) |f| {
                // Use exclusive lock on the file
                f.lock(.exclusive) catch |err| {
                    // If locking not supported, continue without lock
                    if (err != error.FileLocksNotSupported) return err;
                };
                self.is_locked = true;
            }
        }

        /// Unlock the mailbox
        pub fn unlock(self: *Self) !void {
            if (!self.is_locked) return;
            if (self.file) |f| {
                f.unlock();
                self.is_locked = false;
            }
        }

        /// Flush changes to disk
        pub fn flush(self: *Self) !void {
            if (!self.modified) return;
            if (self.file) |f| {
                // Seek to beginning and write all messages
                try f.seekTo(0);

                var writer = f.writer();
                for (self.messages.items) |*msg| {
                    // Write headers
                    var iter = msg.base.headers.iterator();
                    while (iter.next()) |entry| {
                        try writer.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
                    }
                    try writer.writeAll("\n");
                    // Write body
                    try writer.writeAll(msg.base.body);
                    try writer.writeAll("\n");
                }

                // Sync to disk
                try f.sync();
                self.modified = false;
            }
        }

        /// Close the mailbox
        pub fn close(self: *Self) void {
            self.flush() catch {};
            self.unlock() catch {};
            if (self.file) |f| {
                f.close();
                self.file = null;
            }
        }
    };
}
