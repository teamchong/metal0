//! PEP 440 Version type for PubGrub
//! Provides ordering and comparison for Python package versions

const std = @import("std");
const pep440 = @import("../parse/pep440.zig");

/// A version following PEP 440 semantics
/// Wraps the existing pep440 parser with PubGrub-compatible interface
pub const Version = struct {
    inner: pep440.Version,
    /// Track if we own the release array (for proper cleanup)
    owns_memory: bool,
    allocator: ?std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, str: []const u8) !Version {
        const inner = try pep440.parseVersion(allocator, str);
        return .{
            .inner = inner,
            .owns_memory = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Version, allocator: std.mem.Allocator) void {
        if (self.owns_memory) {
            // Free the release array
            if (self.inner.release.len > 0) {
                allocator.free(self.inner.release);
            }
            // Free local if present
            if (self.inner.local) |local| {
                allocator.free(local);
            }
        }
    }

    pub fn clone(self: Version, allocator: std.mem.Allocator) !Version {
        // Clone the release array
        const new_release = try allocator.dupe(u32, self.inner.release);

        // Clone local if present
        const new_local: ?[]const u8 = if (self.inner.local) |local|
            try allocator.dupe(u8, local)
        else
            null;

        return .{
            .inner = .{
                .epoch = self.inner.epoch,
                .release = new_release,
                .pre = self.inner.pre,
                .post = self.inner.post,
                .dev = self.inner.dev,
                .local = new_local,
            },
            .owns_memory = true,
            .allocator = allocator,
        };
    }

    pub fn format(self: Version, allocator: std.mem.Allocator) ![]const u8 {
        // Build version string
        var parts = std.ArrayList(u8){};
        defer parts.deinit(allocator);

        // Epoch
        if (self.inner.epoch > 0) {
            var buf: [32]u8 = undefined;
            const epoch_str = std.fmt.bufPrint(&buf, "{}!", .{self.inner.epoch}) catch return error.FormatError;
            try parts.appendSlice(allocator, epoch_str);
        }

        // Release segments
        for (self.inner.release, 0..) |seg, i| {
            if (i > 0) try parts.append(allocator, '.');
            var buf: [32]u8 = undefined;
            const seg_str = std.fmt.bufPrint(&buf, "{}", .{seg}) catch return error.FormatError;
            try parts.appendSlice(allocator, seg_str);
        }

        // Pre-release
        if (self.inner.pre) |pre| {
            const prefix: []const u8 = switch (pre.kind) {
                .alpha => "a",
                .beta => "b",
                .rc => "rc",
            };
            try parts.appendSlice(allocator, prefix);
            var buf: [32]u8 = undefined;
            const num_str = std.fmt.bufPrint(&buf, "{}", .{pre.num}) catch return error.FormatError;
            try parts.appendSlice(allocator, num_str);
        }

        // Post
        if (self.inner.post) |post| {
            try parts.appendSlice(allocator, ".post");
            var buf: [32]u8 = undefined;
            const post_str = std.fmt.bufPrint(&buf, "{}", .{post}) catch return error.FormatError;
            try parts.appendSlice(allocator, post_str);
        }

        // Dev
        if (self.inner.dev) |dev| {
            try parts.appendSlice(allocator, ".dev");
            var buf: [32]u8 = undefined;
            const dev_str = std.fmt.bufPrint(&buf, "{}", .{dev}) catch return error.FormatError;
            try parts.appendSlice(allocator, dev_str);
        }

        // Local
        if (self.inner.local) |local| {
            try parts.append(allocator, '+');
            try parts.appendSlice(allocator, local);
        }

        return try parts.toOwnedSlice(allocator);
    }

    /// Compare two versions
    /// Returns: .lt, .eq, or .gt
    pub fn order(self: Version, other: Version) std.math.Order {
        return self.inner.compare(other.inner);
    }

    pub fn eql(self: Version, other: Version) bool {
        return self.order(other) == .eq;
    }

    pub fn lessThan(self: Version, other: Version) bool {
        return self.order(other) == .lt;
    }

    pub fn greaterThan(self: Version, other: Version) bool {
        return self.order(other) == .gt;
    }

    pub fn lessThanOrEqual(self: Version, other: Version) bool {
        const o = self.order(other);
        return o == .lt or o == .eq;
    }

    pub fn greaterThanOrEqual(self: Version, other: Version) bool {
        const o = self.order(other);
        return o == .gt or o == .eq;
    }
};

test "version parsing and comparison" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    var v2 = try Version.parse(allocator, "2.0.0");
    defer v2.deinit(allocator);

    var v3 = try Version.parse(allocator, "1.0.0");
    defer v3.deinit(allocator);

    try std.testing.expect(v1.lessThan(v2));
    try std.testing.expect(v2.greaterThan(v1));
    try std.testing.expect(v1.eql(v3));
}

test "version cloning" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.2.3");
    defer v1.deinit(allocator);

    var v2 = try v1.clone(allocator);
    defer v2.deinit(allocator);

    try std.testing.expect(v1.eql(v2));
}

test "version format" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.2.3");
    defer v1.deinit(allocator);

    const str = try v1.format(allocator);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("1.2.3", str);
}
