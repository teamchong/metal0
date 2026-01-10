//! test.test_pathlib - Path manipulation tests
const std = @import("std");

pub const PurePath = struct {
    path: []const u8,
    
    pub fn init(path: []const u8) @This() {
        return .{ .path = path };
    }
    
    pub fn parts(self: @This()) std.mem.SplitIterator(u8, .scalar) {
        return std.mem.splitScalar(u8, self.path, '/');
    }
    
    pub fn parent(self: @This()) @This() {
        if (std.mem.lastIndexOf(u8, self.path, "/")) |idx| {
            return .{ .path = if (idx == 0) "/" else self.path[0..idx] };
        }
        return .{ .path = "." };
    }
    
    pub fn name(self: @This()) []const u8 {
        if (std.mem.lastIndexOf(u8, self.path, "/")) |idx| {
            return self.path[idx+1..];
        }
        return self.path;
    }
    
    pub fn stem(self: @This()) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |idx| {
            if (idx > 0) return n[0..idx];
        }
        return n;
    }
    
    pub fn suffix(self: @This()) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |idx| {
            return n[idx..];
        }
        return "";
    }
    
    pub fn isAbsolute(self: @This()) bool {
        return self.path.len > 0 and self.path[0] == '/';
    }
    
    pub fn joinpath(self: @This(), allocator: std.mem.Allocator, other: []const u8) !@This() {
        if (other.len > 0 and other[0] == '/') {
            return .{ .path = other };
        }
        const result = try std.fmt.allocPrint(allocator, "{s}/{s}", .{self.path, other});
        return .{ .path = result };
    }
    
    pub fn withName(self: @This(), allocator: std.mem.Allocator, new_name: []const u8) !@This() {
        const p = self.parent();
        return p.joinpath(allocator, new_name);
    }
    
    pub fn withSuffix(self: @This(), allocator: std.mem.Allocator, new_suffix: []const u8) !@This() {
        const s = self.stem();
        const p = self.parent();
        const new_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{s, new_suffix});
        return p.joinpath(allocator, new_name);
    }
};

pub const Path = struct {
    pure: PurePath,
    
    pub fn init(path: []const u8) @This() {
        return .{ .pure = PurePath.init(path) };
    }
    
    pub fn exists(self: @This()) bool {
        std.fs.cwd().access(self.pure.path, .{}) catch return false;
        return true;
    }
    
    pub fn isFile(self: @This()) bool {
        const stat = std.fs.cwd().statFile(self.pure.path) catch return false;
        return stat.kind == .file;
    }
    
    pub fn isDir(self: @This()) bool {
        const stat = std.fs.cwd().statFile(self.pure.path) catch return false;
        return stat.kind == .directory;
    }
    
    pub fn readText(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        return std.fs.cwd().readFileAlloc(allocator, self.pure.path, 1024 * 1024);
    }
    
    pub fn writeText(self: @This(), data: []const u8) !void {
        const file = try std.fs.cwd().createFile(self.pure.path, .{});
        defer file.close();
        try file.writeAll(data);
    }
};

test "pure_path_name" {
    const p = PurePath.init("/home/user/file.txt");
    try std.testing.expectEqualStrings("file.txt", p.name());
}

test "pure_path_stem" {
    const p = PurePath.init("/home/user/file.txt");
    try std.testing.expectEqualStrings("file", p.stem());
}

test "pure_path_suffix" {
    const p = PurePath.init("/home/user/file.txt");
    try std.testing.expectEqualStrings(".txt", p.suffix());
}

test "pure_path_parent" {
    const p = PurePath.init("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user", p.parent().path);
}

test "pure_path_is_absolute" {
    try std.testing.expect(PurePath.init("/home").isAbsolute());
    try std.testing.expect(!PurePath.init("home").isAbsolute());
}

test "pure_path_joinpath" {
    const p = PurePath.init("/home/user");
    const joined = try p.joinpath(std.testing.allocator, "file.txt");
    defer std.testing.allocator.free(joined.path);
    try std.testing.expectEqualStrings("/home/user/file.txt", joined.path);
}
