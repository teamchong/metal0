//! test.test_zipfile - ZIP archive tests
const std = @import("std");

pub const ZipFile = struct {
    path: []const u8,
    mode: Mode = .read,
    compression: Compression = .stored,
    files: std.ArrayList(ZipInfo),
    allocator: std.mem.Allocator,
    
    pub const Mode = enum { read, write, append };
    pub const Compression = enum { stored, deflated, bzip2, lzma };
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8, mode: Mode) @This() {
        return .{
            .allocator = allocator,
            .path = path,
            .mode = mode,
            .files = std.ArrayList(ZipInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.files.deinit();
    }
    
    pub fn namelist(self: @This()) []const []const u8 {
        var names: [][]const u8 = self.allocator.alloc([]const u8, self.files.items.len) catch return &.{};
        for (self.files.items, 0..) |f, i| names[i] = f.filename;
        return names;
    }
    
    pub fn infolist(self: @This()) []const ZipInfo {
        return self.files.items;
    }
    
    pub fn getinfo(self: @This(), name: []const u8) ?ZipInfo {
        for (self.files.items) |f| {
            if (std.mem.eql(u8, f.filename, name)) return f;
        }
        return null;
    }
    
    pub fn read(self: @This(), name: []const u8) ![]const u8 {
        _ = self; _ = name;
        return error.FileNotFound;
    }
    
    pub fn write(self: *@This(), arcname: []const u8, data: []const u8) !void {
        try self.files.append(.{
            .filename = arcname,
            .file_size = data.len,
            .compress_size = data.len,
        });
    }
    
    pub fn writestr(self: *@This(), info: ZipInfo, data: []const u8) !void {
        _ = data;
        try self.files.append(info);
    }
    
    pub fn close(self: *@This()) void {
        _ = self;
    }
    
    pub fn testzip(self: @This()) ?[]const u8 {
        _ = self;
        return null;
    }
};

pub const ZipInfo = struct {
    filename: []const u8 = "",
    date_time: [6]u16 = .{0, 0, 0, 0, 0, 0},
    compress_type: ZipFile.Compression = .stored,
    comment: []const u8 = "",
    extra: []const u8 = "",
    create_system: u8 = 0,
    create_version: u8 = 20,
    extract_version: u8 = 20,
    flag_bits: u16 = 0,
    volume: u16 = 0,
    internal_attr: u16 = 0,
    external_attr: u32 = 0,
    header_offset: u64 = 0,
    crc: u32 = 0,
    compress_size: usize = 0,
    file_size: usize = 0,
    
    pub fn isDir(self: @This()) bool {
        return self.filename.len > 0 and self.filename[self.filename.len - 1] == '/';
    }
};

pub fn is_zipfile(path: []const u8) bool {
    _ = path;
    return false;
}

test "zipfile_init" {
    var zf = ZipFile.init(std.testing.allocator, "test.zip", .write);
    defer zf.deinit();
    try std.testing.expectEqualStrings("test.zip", zf.path);
}

test "zipfile_write" {
    var zf = ZipFile.init(std.testing.allocator, "test.zip", .write);
    defer zf.deinit();
    try zf.write("file.txt", "content");
    try std.testing.expectEqual(@as(usize, 1), zf.files.items.len);
}

test "zipinfo_isdir" {
    const dir = ZipInfo{ .filename = "mydir/" };
    const file = ZipInfo{ .filename = "myfile.txt" };
    try std.testing.expect(dir.isDir());
    try std.testing.expect(!file.isDir());
}

test "zipfile_getinfo" {
    var zf = ZipFile.init(std.testing.allocator, "test.zip", .write);
    defer zf.deinit();
    try zf.write("hello.txt", "world");
    if (zf.getinfo("hello.txt")) |info| {
        try std.testing.expectEqualStrings("hello.txt", info.filename);
    } else {
        return error.FileNotFound;
    }
}
