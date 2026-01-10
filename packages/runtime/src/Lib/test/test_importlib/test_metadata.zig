//! test.test_importlib.test_metadata - Tests for importlib.metadata
//! Reference: cpython/Lib/test/test_importlib/test_metadata.py

const std = @import("std");

pub const Distribution = struct {
    const Self = @This();
    
    name: []const u8,
    version: []const u8 = "0.0.0",
    metadata: std.StringHashMap([]const u8),
    files: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .metadata = std.StringHashMap([]const u8).init(allocator),
            .files = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.metadata.deinit();
        self.files.deinit();
    }
    
    pub fn read_text(self: *Self, filename: []const u8) ?[]const u8 {
        _ = self; _ = filename;
        return null;
    }
    
    pub fn locate_file(self: *Self, path: []const u8) ?[]const u8 {
        for (self.files.items) |f| {
            if (std.mem.eql(u8, f, path)) return f;
        }
        return null;
    }
};

pub const PackageMetadata = struct {
    name: []const u8,
    version: []const u8 = "0.0.0",
    summary: ?[]const u8 = null,
    author: ?[]const u8 = null,
    author_email: ?[]const u8 = null,
    license: ?[]const u8 = null,
    requires_python: ?[]const u8 = null,
    classifiers: std.ArrayList([]const u8),
    requires_dist: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .classifiers = std.ArrayList([]const u8).init(allocator),
            .requires_dist = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.classifiers.deinit();
        self.requires_dist.deinit();
    }
};

pub const EntryPoint = struct {
    name: []const u8,
    value: []const u8,
    group: []const u8,
    
    pub fn init(name: []const u8, value: []const u8, group: []const u8) @This() {
        return .{ .name = name, .value = value, .group = group };
    }
    
    pub fn load(self: @This()) !*anyopaque {
        _ = self;
        return error.NotImplemented;
    }
};

pub fn version(package: []const u8) ![]const u8 {
    _ = package;
    return error.PackageNotFound;
}

pub fn metadata(package: []const u8) !PackageMetadata {
    _ = package;
    return error.PackageNotFound;
}

pub fn files(package: []const u8) ![]const []const u8 {
    _ = package;
    return error.PackageNotFound;
}

pub fn requires(package: []const u8) ![]const []const u8 {
    _ = package;
    return error.PackageNotFound;
}

fn testDistribution() !void {
    const allocator = std.testing.allocator;
    var dist = Distribution.init(allocator, "test-package");
    defer dist.deinit();
    
    try std.testing.expectEqualStrings("test-package", dist.name);
    try std.testing.expectEqualStrings("0.0.0", dist.version);
}

fn testPackageMetadata() !void {
    const allocator = std.testing.allocator;
    var meta = PackageMetadata.init(allocator, "mypackage");
    defer meta.deinit();
    
    try std.testing.expectEqualStrings("mypackage", meta.name);
    try meta.classifiers.append("Development Status :: 3 - Alpha");
    try std.testing.expectEqual(@as(usize, 1), meta.classifiers.items.len);
}

fn testEntryPoint() !void {
    const ep = EntryPoint.init("console_script", "mypackage.cli:main", "console_scripts");
    try std.testing.expectEqualStrings("console_script", ep.name);
    try std.testing.expectEqualStrings("console_scripts", ep.group);
}

test "distribution" { try testDistribution(); }
test "package_metadata" { try testPackageMetadata(); }
test "entry_point" { try testEntryPoint(); }
