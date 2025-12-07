//! CPython source: Lib/tarfile.py
//!
//! Provides tools to read and write tar archives, including
//! support for gzip, bz2 and lzma compression.
//!
//! Mirrors: CPython Lib/tarfile.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Block size for tar files
pub const BLOCKSIZE = 512;
pub const RECORDSIZE = BLOCKSIZE * 20;

/// File types
pub const REGTYPE: u8 = '0'; // regular file
pub const AREGTYPE: u8 = 0; // regular file (alternate)
pub const LNKTYPE: u8 = '1'; // link
pub const SYMTYPE: u8 = '2'; // symlink
pub const CHRTYPE: u8 = '3'; // character device
pub const BLKTYPE: u8 = '4'; // block device
pub const DIRTYPE: u8 = '5'; // directory
pub const FIFOTYPE: u8 = '6'; // fifo
pub const CONTTYPE: u8 = '7'; // contiguous file

/// GNU tar extensions
pub const GNUTYPE_LONGNAME: u8 = 'L';
pub const GNUTYPE_LONGLINK: u8 = 'K';
pub const GNUTYPE_SPARSE: u8 = 'S';

/// PAX extensions
pub const XHDTYPE: u8 = 'x'; // Extended header referring to next file
pub const XGLTYPE: u8 = 'g'; // Global extended header

/// USTAR magic
pub const USTAR_MAGIC: [6]u8 = .{ 'u', 's', 't', 'a', 'r', 0 };
pub const GNU_MAGIC: [8]u8 = .{ 'u', 's', 't', 'a', 'r', ' ', ' ', 0 };

/// Encoding
pub const ENCODING = "utf-8";

// ============================================================================
// TarInfo - Information about an archive member
// ============================================================================

/// Information about a member in a tar archive
pub const TarInfo = struct {
    const Self = @This();

    name: []const u8,
    mode: u32 = 0o644,
    uid: u32 = 0,
    gid: u32 = 0,
    size: u64 = 0,
    mtime: u64 = 0,
    chksum: u32 = 0,
    typeflag: u8 = REGTYPE,
    linkname: []const u8 = "",
    uname: []const u8 = "",
    gname: []const u8 = "",
    devmajor: u32 = 0,
    devminor: u32 = 0,
    offset: u64 = 0,
    offset_data: u64 = 0,
    pax_headers: ?std.StringHashMap([]const u8) = null,

    pub fn init(name: []const u8) Self {
        return .{ .name = name };
    }

    /// Check if this is a file
    pub fn isfile(self: Self) bool {
        return self.typeflag == REGTYPE or self.typeflag == AREGTYPE or self.typeflag == CONTTYPE;
    }

    /// Check if this is a directory
    pub fn isdir(self: Self) bool {
        return self.typeflag == DIRTYPE;
    }

    /// Check if this is a symbolic link
    pub fn issym(self: Self) bool {
        return self.typeflag == SYMTYPE;
    }

    /// Check if this is a hard link
    pub fn islnk(self: Self) bool {
        return self.typeflag == LNKTYPE;
    }

    /// Check if this is a character device
    pub fn ischr(self: Self) bool {
        return self.typeflag == CHRTYPE;
    }

    /// Check if this is a block device
    pub fn isblk(self: Self) bool {
        return self.typeflag == BLKTYPE;
    }

    /// Check if this is a FIFO
    pub fn isfifo(self: Self) bool {
        return self.typeflag == FIFOTYPE;
    }

    /// Check if this is a device
    pub fn isdev(self: Self) bool {
        return self.ischr() or self.isblk() or self.isfifo();
    }
};

// ============================================================================
// TarFile - Main tar archive handler
// ============================================================================

/// A class for reading and writing tar archives
pub const TarFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: Mode,
    name: ?[]const u8 = null,
    file: ?std.fs.File = null,
    members: std.ArrayList(TarInfo),
    format: Format = .USTAR,
    encoding: []const u8 = ENCODING,
    errors: []const u8 = "surrogateescape",
    closed: bool = false,
    offset: u64 = 0,

    pub const Mode = enum {
        read,
        write,
        append,
    };

    pub const Format = enum {
        USTAR,
        GNU,
        PAX,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Self {
        return .{
            .allocator = allocator,
            .mode = mode,
            .members = std.ArrayList(TarInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.members.deinit();
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open a tar file
    pub fn open(self: *Self, name: []const u8) !void {
        self.name = name;
        switch (self.mode) {
            .read => {
                self.file = try std.fs.cwd().openFile(name, .{});
                try self.readMembers();
            },
            .write => {
                self.file = try std.fs.cwd().createFile(name, .{});
            },
            .append => {
                self.file = std.fs.cwd().openFile(name, .{ .mode = .read_write }) catch |err| {
                    if (err == error.FileNotFound) {
                        self.file = try std.fs.cwd().createFile(name, .{});
                        return;
                    }
                    return err;
                };
                try self.file.?.seekFromEnd(0);
            },
        }
    }

    /// Read all members from the archive
    fn readMembers(self: *Self) !void {
        if (self.file == null) return;

        while (true) {
            const info = self.readHeader() catch |err| {
                if (err == error.EndOfArchive) break;
                return err;
            };
            try self.members.append(info);

            // Skip to next header (aligned to BLOCKSIZE)
            const blocks = (info.size + BLOCKSIZE - 1) / BLOCKSIZE;
            try self.file.?.seekBy(@intCast(blocks * BLOCKSIZE));
        }
    }

    /// Read a tar header
    fn readHeader(self: *Self) !TarInfo {
        if (self.file == null) return error.FileNotOpen;

        var header: [BLOCKSIZE]u8 = undefined;
        const bytes_read = try self.file.?.readAll(&header);

        if (bytes_read == 0 or std.mem.allEqual(u8, &header, 0)) {
            return error.EndOfArchive;
        }

        // Parse header
        const name = std.mem.trimRight(u8, header[0..100], &[_]u8{0});
        const mode = parseOctal(header[100..108]);
        const uid = parseOctal(header[108..116]);
        const gid = parseOctal(header[116..124]);
        const size = parseOctal(header[124..136]);
        const mtime = parseOctal(header[136..148]);
        const typeflag = header[156];
        const linkname = std.mem.trimRight(u8, header[157..257], &[_]u8{0});

        var info = TarInfo.init(name);
        info.mode = @intCast(mode);
        info.uid = @intCast(uid);
        info.gid = @intCast(gid);
        info.size = size;
        info.mtime = mtime;
        info.typeflag = typeflag;
        info.linkname = linkname;
        info.offset = try self.file.?.getPos() - BLOCKSIZE;
        info.offset_data = try self.file.?.getPos();

        // Parse USTAR fields if present
        if (std.mem.eql(u8, header[257..263], &USTAR_MAGIC)) {
            info.uname = std.mem.trimRight(u8, header[265..297], &[_]u8{0});
            info.gname = std.mem.trimRight(u8, header[297..329], &[_]u8{0});
            info.devmajor = @intCast(parseOctal(header[329..337]));
            info.devminor = @intCast(parseOctal(header[337..345]));
        }

        return info;
    }

    /// Parse an octal field from the header
    fn parseOctal(bytes: []const u8) u64 {
        var result: u64 = 0;
        for (bytes) |c| {
            if (c >= '0' and c <= '7') {
                result = result * 8 + (c - '0');
            } else if (c == ' ' or c == 0) {
                continue;
            } else {
                break;
            }
        }
        return result;
    }

    /// Get list of member names
    pub fn getnames(self: Self) ![][]const u8 {
        var names = try self.allocator.alloc([]const u8, self.members.items.len);
        for (self.members.items, 0..) |info, i| {
            names[i] = info.name;
        }
        return names;
    }

    /// Get list of members
    pub fn getmembers(self: Self) []TarInfo {
        return self.members.items;
    }

    /// Get a specific member
    pub fn getmember(self: Self, name: []const u8) ?TarInfo {
        for (self.members.items) |info| {
            if (std.mem.eql(u8, info.name, name)) {
                return info;
            }
        }
        return null;
    }

    /// Extract a member's content
    pub fn extractfile(self: *Self, member: TarInfo) ![]u8 {
        if (self.file == null) return error.FileNotOpen;
        if (!member.isfile()) return error.NotAFile;

        try self.file.?.seekTo(member.offset_data);

        const content = try self.allocator.alloc(u8, @intCast(member.size));
        _ = try self.file.?.readAll(content);

        return content;
    }

    /// Add a file to the archive
    pub fn addfile(self: *Self, info: TarInfo, data: ?[]const u8) !void {
        if (self.mode == .read) return error.InvalidMode;
        if (self.file == null) return error.FileNotOpen;

        // Build header
        var header: [BLOCKSIZE]u8 = [_]u8{0} ** BLOCKSIZE;

        // Name (100 bytes)
        const name_len = @min(info.name.len, 100);
        @memcpy(header[0..name_len], info.name[0..name_len]);

        // Mode (8 bytes)
        writeOctal(header[100..108], info.mode, 7);

        // UID (8 bytes)
        writeOctal(header[108..116], info.uid, 7);

        // GID (8 bytes)
        writeOctal(header[116..124], info.gid, 7);

        // Size (12 bytes)
        const size = if (data) |d| d.len else info.size;
        writeOctal(header[124..136], @intCast(size), 11);

        // Mtime (12 bytes)
        writeOctal(header[136..148], @intCast(info.mtime), 11);

        // Typeflag
        header[156] = info.typeflag;

        // Linkname (100 bytes)
        const link_len = @min(info.linkname.len, 100);
        @memcpy(header[157 .. 157 + link_len], info.linkname[0..link_len]);

        // USTAR magic
        @memcpy(header[257..263], &USTAR_MAGIC);
        header[263] = '0';
        header[264] = '0';

        // Calculate checksum (8 bytes, filled with spaces initially)
        @memset(header[148..156], ' ');
        var chksum: u32 = 0;
        for (header) |b| {
            chksum += b;
        }
        writeOctal(header[148..155], chksum, 6);
        header[155] = 0;

        // Write header
        try self.file.?.writeAll(&header);

        // Write data
        if (data) |d| {
            try self.file.?.writeAll(d);

            // Pad to block boundary
            const padding = BLOCKSIZE - (d.len % BLOCKSIZE);
            if (padding < BLOCKSIZE) {
                const zeros = [_]u8{0} ** BLOCKSIZE;
                try self.file.?.writeAll(zeros[0..padding]);
            }
        }

        var mutable_info = info;
        mutable_info.size = size;
        try self.members.append(mutable_info);
    }

    /// Write octal value to header
    fn writeOctal(buf: []u8, value: u64, width: usize) void {
        var v = value;
        var i = width;
        while (i > 0) : (i -= 1) {
            buf[i - 1] = @intCast('0' + (v % 8));
            v /= 8;
        }
    }

    /// Close the archive
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode != .read and self.file != null) {
            // Write two zero blocks as end marker
            const zeros = [_]u8{0} ** BLOCKSIZE;
            try self.file.?.writeAll(&zeros);
            try self.file.?.writeAll(&zeros);
        }

        if (self.file) |*f| {
            f.close();
            self.file = null;
        }

        self.closed = true;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Open a tar file (convenience wrapper)
pub fn openTar(allocator: std.mem.Allocator, name: []const u8, mode: []const u8) !TarFile {
    const tar_mode: TarFile.Mode = if (std.mem.eql(u8, mode, "r"))
        .read
    else if (std.mem.eql(u8, mode, "w"))
        .write
    else if (std.mem.eql(u8, mode, "a"))
        .append
    else
        return error.InvalidMode;

    var tf = TarFile.init(allocator, tar_mode);
    try tf.open(name);
    return tf;
}

/// Check if a file is a valid tar file
pub fn isTarfile(name: []const u8) bool {
    const file = std.fs.cwd().openFile(name, .{}) catch return false;
    defer file.close();

    // Read enough to check for USTAR magic
    var buf: [263]u8 = undefined;
    _ = file.readAll(&buf) catch return false;

    return std.mem.eql(u8, buf[257..263], &USTAR_MAGIC) or
        std.mem.eql(u8, buf[257..263], GNU_MAGIC[0..6]);
}

// ============================================================================
// Exceptions
// ============================================================================

pub const TarError = error.TarError;
pub const ReadError = error.ReadError;
pub const CompressionError = error.CompressionError;
pub const StreamError = error.StreamError;
pub const ExtractError = error.ExtractError;
pub const HeaderError = error.HeaderError;

// ============================================================================
// Tests
// ============================================================================

test "TarInfo" {
    var info = TarInfo.init("test.txt");

    try std.testing.expectEqualStrings("test.txt", info.name);
    try std.testing.expect(info.isfile());
    try std.testing.expect(!info.isdir());

    info.typeflag = DIRTYPE;
    try std.testing.expect(info.isdir());
    try std.testing.expect(!info.isfile());
}

test "TarFile init" {
    const allocator = std.testing.allocator;

    var tf = TarFile.init(allocator, .write);
    defer tf.deinit();

    try std.testing.expect(!tf.closed);
    try std.testing.expectEqual(TarFile.Mode.write, tf.mode);
}

test "constants" {
    try std.testing.expectEqual(@as(usize, 512), BLOCKSIZE);
    try std.testing.expectEqual(@as(u8, '0'), REGTYPE);
    try std.testing.expectEqual(@as(u8, '5'), DIRTYPE);
}
