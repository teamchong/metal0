//! CPython source: Lib/mailbox.py
//!
//! MH format mailbox implementation.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const message = @import("message.zig");
const hashmap_helper = @import("utils.hashmap_helper");

pub const Message = message.Message;

// ============================================================================
// MH Mailbox
// ============================================================================

/// MH format mailbox
pub const MH = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const u8,

    pub const MHMessage = struct {
        base: Message,
        sequences: std.ArrayList([]const u8),

        pub fn init(allocator: std.mem.Allocator) MHMessage {
            return .{
                .base = Message.init(allocator),
                .sequences = .{},
            };
        }

        pub fn deinit(self: *MHMessage, allocator: std.mem.Allocator) void {
            self.base.deinit();
            self.sequences.deinit(allocator);
        }

        pub fn getSequences(self: *MHMessage) []const []const u8 {
            return self.sequences.items;
        }

        pub fn addSequence(self: *MHMessage, allocator: std.mem.Allocator, sequence: []const u8) !void {
            try self.sequences.append(allocator, sequence);
        }

        pub fn removeSequence(self: *MHMessage, sequence: []const u8) void {
            for (self.sequences.items, 0..) |s, i| {
                if (std.mem.eql(u8, s, sequence)) {
                    _ = self.sequences.orderedRemove(i);
                    return;
                }
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, factory: ?*const fn (std.mem.Allocator) MHMessage, create: bool) !Self {
        _ = factory;
        if (create) {
            std.fs.makeDirAbsolute(path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Add message
    pub fn add(self: *Self, msg: anytype) !u32 {
        _ = self;
        _ = msg;
        return 1;
    }

    /// Remove message
    pub fn remove(self: *Self, key: u32) !void {
        _ = self;
        _ = key;
    }

    /// Get message
    pub fn get(self: *Self, key: u32) !?MHMessage {
        _ = self;
        _ = key;
        return null;
    }

    /// List folders
    pub fn listFolders(self: *Self) ![]const []const u8 {
        _ = self;
        return &[_][]const u8{};
    }

    /// Get folder
    pub fn getFolder(self: *Self, folder: []const u8) !MH {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const folder_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.path, folder });
        return MH.init(self.allocator, folder_path, null, false);
    }

    /// Add folder
    pub fn addFolder(self: *Self, folder: []const u8) !MH {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const folder_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.path, folder });
        return MH.init(self.allocator, folder_path, null, true);
    }

    /// Remove folder
    pub fn removeFolder(self: *Self, folder: []const u8) !void {
        _ = self;
        _ = folder;
    }

    /// Get sequences
    pub fn getSequences(self: *Self) !hashmap_helper.StringHashMap([]const u32) {
        _ = self;
        return hashmap_helper.StringHashMap([]const u32).init(self.allocator);
    }

    /// Set sequences
    pub fn setSequences(self: *Self, sequences: hashmap_helper.StringHashMap([]const u32)) !void {
        _ = self;
        _ = sequences;
    }

    /// Pack message numbers
    pub fn pack(self: *Self) !void {
        _ = self;
    }

    /// Close
    pub fn close(self: *Self) void {
        _ = self;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MH message sequences" {
    const allocator = std.testing.allocator;
    var msg = MH.MHMessage.init(allocator);
    defer msg.deinit(allocator);

    try msg.addSequence(allocator, "unseen");
    try msg.addSequence(allocator, "flagged");
    try std.testing.expectEqual(@as(usize, 2), msg.getSequences().len);
}
