//! CPython source: Lib/mailbox.py
//!
//! Maildir format mailbox implementation.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const message = @import("message.zig");

pub const Message = message.Message;

// ============================================================================
// Maildir Mailbox
// ============================================================================

/// Maildir format mailbox
pub const Maildir = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const u8,
    colon: u8,

    pub const MaildirMessage = struct {
        base: Message,
        subdir: []const u8,
        info: []const u8,
        date: i64,

        pub fn init(allocator: std.mem.Allocator) MaildirMessage {
            return .{
                .base = Message.init(allocator),
                .subdir = "new",
                .info = "",
                .date = 0,
            };
        }

        pub fn deinit(self: *MaildirMessage) void {
            self.base.deinit();
        }

        pub fn getSubdir(self: *MaildirMessage) []const u8 {
            return self.subdir;
        }

        pub fn setSubdir(self: *MaildirMessage, subdir: []const u8) void {
            self.subdir = subdir;
        }

        pub fn getInfo(self: *MaildirMessage) []const u8 {
            return self.info;
        }

        pub fn setInfo(self: *MaildirMessage, info: []const u8) void {
            self.info = info;
        }

        pub fn getDate(self: *MaildirMessage) i64 {
            return self.date;
        }

        pub fn setDate(self: *MaildirMessage, date: i64) void {
            self.date = date;
        }

        /// Get flags from info string
        pub fn getFlags(self: *MaildirMessage) []const u8 {
            if (std.mem.indexOf(u8, self.info, "2,")) |idx| {
                return self.info[idx + 2 ..];
            }
            return "";
        }

        /// Set flags in info string (Maildir flags: D=Draft, F=Flagged, P=Passed, R=Replied, S=Seen, T=Trashed)
        pub fn setFlags(self: *MaildirMessage, flags: []const u8) void {
            // Info string format: "2,<flags>" where flags are sorted uppercase letters
            var new_info: [32]u8 = undefined;
            var len: usize = 2;
            new_info[0] = '2';
            new_info[1] = ',';

            // Sort flags alphabetically
            var sorted_flags: [6]u8 = undefined;
            var flag_count: usize = 0;
            for (flags) |f| {
                const upper = std.ascii.toUpper(f);
                if (upper == 'D' or upper == 'F' or upper == 'P' or upper == 'R' or upper == 'S' or upper == 'T') {
                    sorted_flags[flag_count] = upper;
                    flag_count += 1;
                }
            }
            std.mem.sort(u8, sorted_flags[0..flag_count], {}, std.sort.asc(u8));
            for (sorted_flags[0..flag_count]) |f| {
                new_info[len] = f;
                len += 1;
            }

            self.info = new_info[0..len];
        }

        /// Add a flag to the message
        pub fn addFlag(self: *MaildirMessage, flag: u8) void {
            const upper = std.ascii.toUpper(flag);
            if (self.info) |info| {
                // Check if flag already present
                if (std.mem.indexOf(u8, info, &[_]u8{upper}) != null) return;

                // Add flag and re-sort
                var current_flags: [7]u8 = undefined;
                var count: usize = 0;
                for (info) |c| {
                    if (std.ascii.isUpper(c)) {
                        current_flags[count] = c;
                        count += 1;
                    }
                }
                current_flags[count] = upper;
                count += 1;
                self.setFlags(current_flags[0..count]);
            } else {
                self.setFlags(&[_]u8{upper});
            }
        }

        /// Remove a flag from the message
        pub fn removeFlag(self: *MaildirMessage, flag: u8) void {
            const upper = std.ascii.toUpper(flag);
            if (self.info) |info| {
                var new_flags: [6]u8 = undefined;
                var count: usize = 0;
                for (info) |c| {
                    if (std.ascii.isUpper(c) and c != upper) {
                        new_flags[count] = c;
                        count += 1;
                    }
                }
                if (count > 0) {
                    self.setFlags(new_flags[0..count]);
                } else {
                    self.info = "2,";
                }
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, dirname: []const u8, factory: ?*const fn (std.mem.Allocator) MaildirMessage, create: bool) !Self {
        _ = factory;

        if (create) {
            // Create maildir structure
            var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            var cur_path_buf: [std.fs.max_path_bytes]u8 = undefined;

            const tmp_path = try std.fmt.bufPrint(&tmp_path_buf, "{s}/tmp", .{dirname});
            const new_path = try std.fmt.bufPrint(&new_path_buf, "{s}/new", .{dirname});
            const cur_path = try std.fmt.bufPrint(&cur_path_buf, "{s}/cur", .{dirname});

            std.fs.makeDirAbsolute(dirname) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
            std.fs.makeDirAbsolute(tmp_path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
            std.fs.makeDirAbsolute(new_path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
            std.fs.makeDirAbsolute(cur_path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        return .{
            .allocator = allocator,
            .path = dirname,
            .colon = ':',
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Add a message - writes to tmp/ then moves to new/
    pub fn add(self: *Self, msg: anytype) ![]const u8 {
        // Generate unique filename
        const timestamp = std.time.timestamp();
        var rng = std.Random.DefaultPrng.init(@intCast(timestamp));
        const random = rng.random().int(u32);

        var filename_buf: [128]u8 = undefined;
        const filename = std.fmt.bufPrint(&filename_buf, "{d}.{d}.{d}", .{
            timestamp,
            std.Thread.getCurrentId(),
            random,
        }) catch return error.InvalidPath;

        // Write to tmp/
        var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "{s}/tmp/{s}", .{ self.path, filename }) catch return error.InvalidPath;

        const file = std.fs.createFileAbsolute(tmp_path, .{}) catch return error.FileNotFound;
        defer file.close();

        // Write message content
        const T = @TypeOf(msg);
        if (T == []const u8) {
            file.writeAll(msg) catch return error.WriteError;
        } else if (@hasField(T, "data")) {
            file.writeAll(msg.data) catch return error.WriteError;
        }

        // Move to new/
        var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const new_path = std.fmt.bufPrint(&new_path_buf, "{s}/new/{s}", .{ self.path, filename }) catch return error.InvalidPath;

        std.fs.renameAbsolute(tmp_path, new_path) catch return error.RenameError;

        // Return the key (filename without info)
        return self.allocator.dupe(u8, filename) catch return error.OutOfMemory;
    }

    /// Remove a message by deleting the file
    pub fn remove(self: *Self, key: []const u8) !void {
        // Try cur/ first, then new/
        var cur_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;

        const cur_path = std.fmt.bufPrint(&cur_path_buf, "{s}/cur/{s}", .{ self.path, key }) catch return;
        const new_path = std.fmt.bufPrint(&new_path_buf, "{s}/new/{s}", .{ self.path, key }) catch return;

        std.fs.deleteFileAbsolute(cur_path) catch {
            std.fs.deleteFileAbsolute(new_path) catch return error.KeyError;
        };
    }

    /// Get a message
    pub fn get(self: *Self, key: []const u8) !?MaildirMessage {
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
    pub fn getFolder(self: *Self, folder: []const u8) !Maildir {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const folder_path = try std.fmt.bufPrint(&path_buf, "{s}/.{s}", .{ self.path, folder });
        return Maildir.init(self.allocator, folder_path, null, false);
    }

    /// Add folder
    pub fn addFolder(self: *Self, folder: []const u8) !Maildir {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const folder_path = try std.fmt.bufPrint(&path_buf, "{s}/.{s}", .{ self.path, folder });
        return Maildir.init(self.allocator, folder_path, null, true);
    }

    /// Remove folder by deleting the folder directory
    pub fn removeFolder(self: *Self, folder: []const u8) !void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const folder_path = std.fmt.bufPrint(&path_buf, "{s}/.{s}", .{ self.path, folder }) catch return;

        // Delete all subdirs (tmp, new, cur) then the folder itself
        const subdirs = [_][]const u8{ "tmp", "new", "cur" };
        for (subdirs) |subdir| {
            var sub_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const sub_path = std.fmt.bufPrint(&sub_path_buf, "{s}/{s}", .{ folder_path, subdir }) catch continue;
            std.fs.deleteTreeAbsolute(sub_path) catch {};
        }
        std.fs.deleteDirAbsolute(folder_path) catch {};
    }

    /// Clean tmp directory - remove files older than 36 hours
    pub fn clean(self: *Self) void {
        var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "{s}/tmp", .{self.path}) catch return;

        const now = std.time.timestamp();
        const threshold = now - (36 * 60 * 60); // 36 hours ago

        var dir = std.fs.openDirAbsolute(tmp_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .file) continue;

            // Get file mtime
            const stat = dir.statFile(entry.name) catch continue;
            const mtime: i64 = @intCast(stat.mtime / std.time.ns_per_s);

            if (mtime < threshold) {
                dir.deleteFile(entry.name) catch {};
            }
        }
    }

    /// Flush changes
    pub fn flush(self: *Self) !void {
        _ = self;
    }

    /// Close maildir
    pub fn close(self: *Self) void {
        _ = self;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Maildir message subdir" {
    const allocator = std.testing.allocator;
    var msg = Maildir.MaildirMessage.init(allocator);
    defer msg.deinit();

    try std.testing.expectEqualStrings("new", msg.getSubdir());
    msg.setSubdir("cur");
    try std.testing.expectEqualStrings("cur", msg.getSubdir());
}
