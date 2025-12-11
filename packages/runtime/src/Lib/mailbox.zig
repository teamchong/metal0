//! CPython source: Lib/mailbox.py
//!
//! Provides uniform access to mailboxes in different formats.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const MailboxError = error{
    /// Base mailbox error
    Error,
    /// Mailbox not found
    NoSuchMailboxError,
    /// Mailbox already exists
    ExternalClashError,
    /// Format error
    FormatError,
    /// Message not found
    NotEmptyError,
};

// ============================================================================
// Message
// ============================================================================

/// A message in a mailbox
pub const Message = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    headers: hashmap_helper.StringHashMap([]const u8),
    body: []const u8,
    flags: Flags,

    /// Message flags
    pub const Flags = struct {
        read: bool = false,
        replied: bool = false,
        flagged: bool = false,
        deleted: bool = false,
        draft: bool = false,
        recent: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .headers = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .body = "",
            .flags = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    /// Set a header
    pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    /// Get a header
    pub fn getHeader(self: *Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Get all headers
    pub fn getHeaders(self: *Self) hashmap_helper.StringHashMap([]const u8) {
        return self.headers;
    }

    /// Set body
    pub fn setBody(self: *Self, body: []const u8) void {
        self.body = body;
    }

    /// Get body
    pub fn getBody(self: *Self) []const u8 {
        return self.body;
    }

    /// Set flags
    pub fn setFlags(self: *Self, flags: Flags) void {
        self.flags = flags;
    }

    /// Get flags
    pub fn getFlags(self: *Self) Flags {
        return self.flags;
    }

    /// Convert to string representation
    pub fn asString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice(": ");
            try result.appendSlice(entry.value_ptr.*);
            try result.append('\n');
        }
        try result.append('\n');
        try result.appendSlice(self.body);

        return result.toOwnedSlice();
    }

    /// Parse from string
    pub fn fromString(allocator: std.mem.Allocator, data: []const u8) !Self {
        var self = Self.init(allocator);

        // Find header/body separator
        const sep_idx = std.mem.indexOf(u8, data, "\n\n") orelse data.len;

        // Parse headers
        const header_part = data[0..sep_idx];
        var lines = std.mem.splitScalar(u8, header_part, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, ": ")) |colon_idx| {
                const name = line[0..colon_idx];
                const value = line[colon_idx + 2 ..];
                try self.setHeader(name, value);
            }
        }

        // Set body
        if (sep_idx + 2 < data.len) {
            self.body = data[sep_idx + 2 ..];
        }

        return self;
    }
};

// ============================================================================
// Base Mailbox
// ============================================================================

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
                return MailboxError.Error;
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

// ============================================================================
// Mbox Mailbox
// ============================================================================

/// mbox format mailbox
pub const Mbox = struct {
    const Self = @This();

    base: Mailbox(MboxMessage),

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
            .base = try Mailbox(MboxMessage).init(allocator, path, factory, create),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn add(self: *Self, message: MboxMessage) !usize {
        return self.base.add(message);
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
    pub fn add(self: *Self, message: anytype) ![]const u8 {
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
        const T = @TypeOf(message);
        if (T == []const u8) {
            file.writeAll(message) catch return error.WriteError;
        } else if (@hasField(T, "data")) {
            file.writeAll(message.data) catch return error.WriteError;
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
                .sequences = std.ArrayList([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *MHMessage) void {
            self.base.deinit();
            self.sequences.deinit();
        }

        pub fn getSequences(self: *MHMessage) []const []const u8 {
            return self.sequences.items;
        }

        pub fn addSequence(self: *MHMessage, sequence: []const u8) !void {
            try self.sequences.append(sequence);
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
    pub fn add(self: *Self, message: anytype) !u32 {
        _ = self;
        _ = message;
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
// MMDF Mailbox
// ============================================================================

/// MMDF format mailbox (like mbox but with different separator)
pub const MMDF = struct {
    const Self = @This();

    base: Mailbox(MMDFMessage),

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
            .base = try Mailbox(MMDFMessage).init(allocator, path, factory, create),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn add(self: *Self, message: MMDFMessage) !usize {
        return self.base.add(message);
    }

    pub fn get(self: *Self, key: usize) ?MMDFMessage {
        return self.base.get(key);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// Babyl Mailbox
// ============================================================================

/// Babyl format mailbox (Emacs RMAIL)
pub const Babyl = struct {
    const Self = @This();

    base: Mailbox(BabylMessage),

    pub const BabylMessage = struct {
        base: Message,
        labels: std.ArrayList([]const u8),
        visible: bool,

        pub fn init(allocator: std.mem.Allocator) BabylMessage {
            return .{
                .base = Message.init(allocator),
                .labels = std.ArrayList([]const u8).init(allocator),
                .visible = true,
            };
        }

        pub fn deinit(self: *BabylMessage) void {
            self.base.deinit();
            self.labels.deinit();
        }

        pub fn getLabels(self: *BabylMessage) []const []const u8 {
            return self.labels.items;
        }

        pub fn addLabel(self: *BabylMessage, label: []const u8) !void {
            try self.labels.append(label);
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
            .base = try Mailbox(BabylMessage).init(allocator, path, factory, create),
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

    pub fn add(self: *Self, message: BabylMessage) !usize {
        return self.base.add(message);
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

test "Message init and headers" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.setHeader("From", "test@example.com");
    try msg.setHeader("Subject", "Test");

    try std.testing.expectEqualStrings("test@example.com", msg.getHeader("From").?);
    try std.testing.expectEqualStrings("Test", msg.getHeader("Subject").?);
}

test "Message body" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    msg.setBody("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", msg.getBody());
}

test "Message flags" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    msg.setFlags(.{ .read = true, .flagged = true });
    const flags = msg.getFlags();
    try std.testing.expect(flags.read);
    try std.testing.expect(flags.flagged);
    try std.testing.expect(!flags.deleted);
}

test "Mbox init" {
    const allocator = std.testing.allocator;
    var mbox = try Mbox.init(allocator, "/tmp/test.mbox", null, true);
    defer mbox.deinit();

    try std.testing.expectEqual(@as(usize, 0), mbox.len());
}

test "Maildir message subdir" {
    const allocator = std.testing.allocator;
    var msg = Maildir.MaildirMessage.init(allocator);
    defer msg.deinit();

    try std.testing.expectEqualStrings("new", msg.getSubdir());
    msg.setSubdir("cur");
    try std.testing.expectEqualStrings("cur", msg.getSubdir());
}

test "MH message sequences" {
    const allocator = std.testing.allocator;
    var msg = MH.MHMessage.init(allocator);
    defer msg.deinit();

    try msg.addSequence("unseen");
    try msg.addSequence("flagged");
    try std.testing.expectEqual(@as(usize, 2), msg.getSequences().len);
}

test "Babyl message labels" {
    const allocator = std.testing.allocator;
    var msg = Babyl.BabylMessage.init(allocator);
    defer msg.deinit();

    try msg.addLabel("answered");
    try std.testing.expectEqual(@as(usize, 1), msg.getLabels().len);
    try std.testing.expect(msg.getVisible());
}
