//! PEP 440 Version Specifiers
//!
//! Parses Python version strings like ">=1.0,<2.0,!=1.5"
//!
//! ## Supported Operators
//! - `==` - Exact match (with wildcard: `==1.0.*`)
//! - `!=` - Exclusion
//! - `>=`, `<=`, `>`, `<` - Ordered comparison
//! - `~=` - Compatible release (`~=1.4.2` means `>=1.4.2,<1.5.0`)
//! - `===` - Arbitrary equality (string match)
//!
//! ## Version Format
//! `[N!]N(.N)*[{a|b|rc}N][.postN][.devN][+local]`
//!
//! Examples: `1.0`, `2.0.0`, `1.0a1`, `1.0.post1`, `1.0.dev1`, `1!2.0`
//!
//! Reference: https://peps.python.org/pep-0440/

const std = @import("std");

/// A parsed Python version (PEP 440)
pub const Version = struct {
    epoch: u32 = 0,
    release: []const u32, // Major, minor, patch, etc.
    pre: ?PreRelease = null,
    post: ?u32 = null,
    dev: ?u32 = null,
    local: ?[]const u8 = null,

    pub const PreRelease = struct {
        kind: PreKind,
        num: u32,

        pub const PreKind = enum { alpha, beta, rc };
    };

    /// Compare two versions. Returns .lt, .eq, or .gt
    pub fn compare(self: Version, other: Version) std.math.Order {
        // Epoch first
        if (self.epoch != other.epoch) {
            return std.math.order(self.epoch, other.epoch);
        }

        // Release segments
        const max_len = @max(self.release.len, other.release.len);
        for (0..max_len) |i| {
            const a = if (i < self.release.len) self.release[i] else 0;
            const b = if (i < other.release.len) other.release[i] else 0;
            if (a != b) return std.math.order(a, b);
        }

        // PEP 440 ordering (sorted from lowest to highest):
        // 1.0.dev456           (dev release, no pre, no post)
        // 1.0a1                (alpha pre-release)
        // 1.0a2.dev456         (alpha 2 with dev - dev before same pre)
        // 1.0a12               (alpha 12)
        // 1.0b1.dev456         (beta 1 with dev)
        // 1.0b2                (beta 2)
        // 1.0b2.post345.dev456 (beta 2 post 345 with dev)
        // 1.0b2.post345        (beta 2 post 345)
        // 1.0c1.dev456         (rc 1 with dev) <-- THIS IS AFTER b2.post345
        // 1.0c1                (rc 1)
        // 1.0                  (final release)
        // 1.0.post456.dev34    (post release with dev)
        // 1.0.post456          (post release)
        //
        // Order: dev-only < pre-releases (including their posts) < final < post-releases
        // Within pre-releases: alpha < beta < rc; then compare numbers; then post; then dev

        const self_has_pre = self.pre != null;
        const other_has_pre = other.pre != null;
        const self_has_post = self.post != null;
        const other_has_post = other.post != null;
        const self_dev_only = self.dev != null and !self_has_pre and !self_has_post;
        const other_dev_only = other.dev != null and !other_has_pre and !other_has_post;

        // dev-only (1.0.dev) is less than everything except another dev-only
        if (self_dev_only and !other_dev_only) return .lt;
        if (other_dev_only and !self_dev_only) return .gt;
        if (self_dev_only and other_dev_only) {
            return std.math.order(self.dev.?, other.dev.?);
        }

        // pre-release < final < post (when no pre)
        // final means: no pre and no post (and not dev-only, handled above)
        const self_is_final = !self_has_pre and !self_has_post;
        const other_is_final = !other_has_pre and !other_has_post;

        // pre-release (with or without post) < final
        if (self_has_pre and other_is_final) return .lt;
        if (other_has_pre and self_is_final) return .gt;

        // pre-release (with or without post) < post-only (no pre)
        if (self_has_pre and !other_has_pre and other_has_post) return .lt;
        if (other_has_pre and !self_has_pre and self_has_post) return .gt;

        // final < post-only
        if (self_is_final and other_has_post) return .lt;
        if (other_is_final and self_has_post) return .gt;

        // Both have pre-releases - compare pre first
        if (self_has_pre and other_has_pre) {
            const sp = self.pre.?;
            const op = other.pre.?;
            // Compare pre-release kind: alpha < beta < rc
            const kind_ord = std.math.order(@intFromEnum(sp.kind), @intFromEnum(op.kind));
            if (kind_ord != .eq) return kind_ord;
            // Same kind, compare number
            if (sp.num != op.num) return std.math.order(sp.num, op.num);
            // Same pre-release exactly (e.g., both are b2)
            // Now compare: dev < nothing < post.dev < post
            const self_has_dev = self.dev != null;
            const other_has_dev = other.dev != null;

            // First: if one has post and other doesn't
            if (self_has_post != other_has_post) {
                // pre.dev < pre < pre.post.dev < pre.post
                if (!self_has_post and !self_has_dev and other_has_post) return .lt; // pre < pre.post
                if (!other_has_post and !other_has_dev and self_has_post) return .gt;
                if (!self_has_post and self_has_dev and other_has_post) return .lt; // pre.dev < pre.post
                if (!other_has_post and other_has_dev and self_has_post) return .gt;
                if (self_has_post and !other_has_post) return .gt; // pre.post > pre
                if (other_has_post and !self_has_post) return .lt;
            }

            // Same post status
            if (self_has_post and other_has_post) {
                if (self.post.? != other.post.?) return std.math.order(self.post.?, other.post.?);
            }

            // Compare dev: with dev < without dev
            if (self_has_dev != other_has_dev) {
                return if (self_has_dev) .lt else .gt;
            }
            if (self.dev) |sd| {
                if (other.dev) |od| {
                    return std.math.order(sd, od);
                }
            }
            return .eq;
        }

        // Both are post-only releases (no pre)
        if (self_has_post and other_has_post) {
            if (self.post.? != other.post.?) return std.math.order(self.post.?, other.post.?);
            // Same post number, compare dev
            const self_has_dev = self.dev != null;
            const other_has_dev = other.dev != null;
            if (self_has_dev != other_has_dev) {
                return if (self_has_dev) .lt else .gt;
            }
            if (self.dev) |sd| {
                if (other.dev) |od| {
                    return std.math.order(sd, od);
                }
            }
            return .eq;
        }

        // Both are final releases (no pre, no post, no dev - since dev-only handled above)
        // Compare local versions if present
        return self.compareLocal(other);
    }

    /// Compare local version segments
    fn compareLocal(self: Version, other: Version) std.math.Order {
        // Per PEP 440, local versions are compared segment by segment
        // Each segment is either numeric (compared as integers) or alphanumeric (compared lexicographically)
        // Numeric segments always sort before string segments
        const self_local = self.local orelse return if (other.local != null) .lt else .eq;
        const other_local = other.local orelse return .gt;

        // Split by dots to get segments
        var self_segs = std.mem.splitScalar(u8, self_local, '.');
        var other_segs = std.mem.splitScalar(u8, other_local, '.');

        while (true) {
            const self_seg = self_segs.next();
            const other_seg = other_segs.next();

            if (self_seg == null and other_seg == null) return .eq;
            if (self_seg == null) return .lt;
            if (other_seg == null) return .gt;

            // Try to parse both as integers
            const self_num = std.fmt.parseInt(i64, self_seg.?, 10) catch null;
            const other_num = std.fmt.parseInt(i64, other_seg.?, 10) catch null;

            if (self_num != null and other_num != null) {
                // Both are integers - compare numerically
                if (self_num.? != other_num.?) {
                    return std.math.order(self_num.?, other_num.?);
                }
            } else if (self_num != null and other_num == null) {
                // string < integer (per PEP 440 - strings sort before integers in local versions)
                return .gt;
            } else if (self_num == null and other_num != null) {
                return .lt;
            } else {
                // Both strings - compare lexicographically (case insensitive per PEP 440 normalization)
                // Lower case for comparison
                const ord = std.ascii.orderIgnoreCase(self_seg.?, other_seg.?);
                if (ord != .eq) return ord;
            }
        }
    }

    /// Format version as string
    pub fn format(self: Version, writer: anytype) !void {
        if (self.epoch != 0) {
            try writer.print("{}!", .{self.epoch});
        }
        for (self.release, 0..) |seg, i| {
            if (i > 0) try writer.writeByte('.');
            try writer.print("{}", .{seg});
        }
        if (self.pre) |p| {
            const kind_str: []const u8 = switch (p.kind) {
                .alpha => "a",
                .beta => "b",
                .rc => "rc",
            };
            try writer.print("{s}{}", .{ kind_str, p.num });
        }
        if (self.post) |p| {
            try writer.print(".post{}", .{p});
        }
        if (self.dev) |d| {
            try writer.print(".dev{}", .{d});
        }
        if (self.local) |l| {
            try writer.print("+{s}", .{l});
        }
    }

    pub fn eql(self: Version, other: Version) bool {
        return self.compare(other) == .eq;
    }
};

/// Version specifier operator
pub const Operator = enum {
    eq, // ==
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
    compatible, // ~=
    arbitrary, // ===

    pub fn fromStr(s: []const u8) ?Operator {
        return if (std.mem.eql(u8, s, "=="))
            .eq
        else if (std.mem.eql(u8, s, "!="))
            .ne
        else if (std.mem.eql(u8, s, "<"))
            .lt
        else if (std.mem.eql(u8, s, "<="))
            .le
        else if (std.mem.eql(u8, s, ">"))
            .gt
        else if (std.mem.eql(u8, s, ">="))
            .ge
        else if (std.mem.eql(u8, s, "~="))
            .compatible
        else if (std.mem.eql(u8, s, "==="))
            .arbitrary
        else
            null;
    }
};

/// A single version constraint like ">=1.0" or "!=1.5"
pub const VersionConstraint = struct {
    op: Operator,
    version: Version,
    wildcard: bool = false, // For == with wildcard like "==1.0.*"

    /// Check if a version matches this constraint
    pub fn matches(self: VersionConstraint, v: Version) bool {
        const ord = v.compare(self.version);

        return switch (self.op) {
            .eq => if (self.wildcard) self.matchesWildcard(v) else ord == .eq,
            .ne => if (self.wildcard) !self.matchesWildcard(v) else ord != .eq,
            .lt => ord == .lt,
            .le => ord == .lt or ord == .eq,
            .gt => ord == .gt,
            .ge => ord == .gt or ord == .eq,
            .compatible => self.matchesCompatible(v),
            .arbitrary => false, // String comparison, not version
        };
    }

    fn matchesWildcard(self: VersionConstraint, v: Version) bool {
        // ==1.0.* matches 1.0.0, 1.0.1, 1.0.99, but not 1.1.0
        if (v.epoch != self.version.epoch) return false;
        if (v.release.len < self.version.release.len) return false;

        for (self.version.release, 0..) |seg, i| {
            if (v.release[i] != seg) return false;
        }
        return true;
    }

    fn matchesCompatible(self: VersionConstraint, v: Version) bool {
        // ~=1.4.2 means >=1.4.2,<1.5.0
        // First check >=
        if (v.compare(self.version) == .lt) return false;

        // Then check < next minor/major
        if (self.version.release.len < 2) return true;

        // Build upper bound: increment second-to-last segment
        const upper_len = self.version.release.len - 1;
        for (0..upper_len) |i| {
            const self_seg = self.version.release[i];
            const v_seg = if (i < v.release.len) v.release[i] else 0;

            if (i == upper_len - 1) {
                // This is the segment we compare against (incremented)
                if (v_seg >= self_seg + 1) return false;
                if (v_seg < self_seg) return true;
            } else {
                if (v_seg != self_seg) return v_seg < self_seg;
            }
        }
        return true;
    }
};

/// A complete version specifier like ">=1.0,<2.0,!=1.5"
pub const VersionSpec = struct {
    constraints: []const VersionConstraint,

    /// Check if a version satisfies all constraints
    pub fn satisfies(self: VersionSpec, v: Version) bool {
        for (self.constraints) |c| {
            if (!c.matches(v)) return false;
        }
        return true;
    }
};

pub const ParseError = error{
    InvalidVersion,
    InvalidOperator,
    InvalidSpecifier,
    OutOfMemory,
};

/// Parse a version string like "1.0.0", "2.0a1", "1!3.0.post1"
pub fn parseVersion(allocator: std.mem.Allocator, input: []const u8) ParseError!Version {
    var s = input;
    var version = Version{ .release = &[_]u32{} };

    // Trim whitespace
    s = std.mem.trim(u8, s, " \t");
    if (s.len == 0) return ParseError.InvalidVersion;

    // Parse epoch (N!)
    if (std.mem.indexOf(u8, s, "!")) |bang_pos| {
        version.epoch = std.fmt.parseInt(u32, s[0..bang_pos], 10) catch return ParseError.InvalidVersion;
        s = s[bang_pos + 1 ..];
    }

    // Parse local version (+local)
    if (std.mem.indexOf(u8, s, "+")) |plus_pos| {
        const local = s[plus_pos + 1 ..];
        // Validate local version - must be alphanumeric with dots/hyphens/underscores as separators
        // Cannot start or end with separator, cannot have consecutive separators
        if (local.len == 0) return ParseError.InvalidVersion;
        var prev_sep = true; // Start true to catch leading separator
        for (local) |c| {
            const is_sep = c == '.' or c == '-' or c == '_';
            if (is_sep) {
                if (prev_sep) return ParseError.InvalidVersion; // consecutive or leading separator
                prev_sep = true;
            } else if (!std.ascii.isAlphanumeric(c)) {
                return ParseError.InvalidVersion; // invalid character
            } else {
                prev_sep = false;
            }
        }
        if (prev_sep) return ParseError.InvalidVersion; // trailing separator
        version.local = local;
        s = s[0..plus_pos];
    }

    // Parse dev (.devN)
    if (std.mem.indexOf(u8, s, ".dev")) |dev_pos| {
        const dev_str = s[dev_pos + 4 ..];
        version.dev = if (dev_str.len == 0) 0 else std.fmt.parseInt(u32, dev_str, 10) catch return ParseError.InvalidVersion;
        s = s[0..dev_pos];
    }

    // Parse post (.postN or .N after release for implicit post)
    if (std.mem.indexOf(u8, s, ".post")) |post_pos| {
        const post_str = s[post_pos + 5 ..];
        version.post = if (post_str.len == 0) 0 else std.fmt.parseInt(u32, post_str, 10) catch return ParseError.InvalidVersion;
        s = s[0..post_pos];
    }

    // Parse pre-release (aN, bN, rcN, alphaN, betaN)
    const pre_markers = [_]struct { marker: []const u8, kind: Version.PreRelease.PreKind }{
        .{ .marker = "rc", .kind = .rc },
        .{ .marker = "alpha", .kind = .alpha },
        .{ .marker = "beta", .kind = .beta },
        .{ .marker = "a", .kind = .alpha },
        .{ .marker = "b", .kind = .beta },
        .{ .marker = "c", .kind = .rc }, // c is alias for rc
    };

    for (pre_markers) |pm| {
        if (findPreRelease(s, pm.marker)) |pre_pos| {
            const num_start = pre_pos + pm.marker.len;
            const num_str = s[num_start..];
            const num = if (num_str.len == 0) 0 else std.fmt.parseInt(u32, num_str, 10) catch return ParseError.InvalidVersion;
            version.pre = .{ .kind = pm.kind, .num = num };
            // Strip any separator before the pre-release marker
            var end = pre_pos;
            if (end > 0 and (s[end - 1] == '.' or s[end - 1] == '-' or s[end - 1] == '_')) {
                end -= 1;
            }
            s = s[0..end];
            break;
        }
    }

    // Parse release segments (N.N.N...)
    var segments = std.ArrayList(u32){};
    defer segments.deinit(allocator);

    var iter = std.mem.splitScalar(u8, s, '.');
    while (iter.next()) |seg| {
        if (seg.len == 0) continue;
        const num = std.fmt.parseInt(u32, seg, 10) catch return ParseError.InvalidVersion;
        try segments.append(allocator, num);
    }

    if (segments.items.len == 0) return ParseError.InvalidVersion;

    version.release = try segments.toOwnedSlice(allocator);
    return version;
}

fn findPreRelease(s: []const u8, marker: []const u8) ?usize {
    // Find marker that's preceded by a digit or separator (end of release) and followed by digit or end
    // PEP 440 allows separators like '.', '-', '_' before pre-release tags
    var i: usize = 1; // Start at 1 since we need something before
    while (i + marker.len <= s.len) : (i += 1) {
        const prev = s[i - 1];
        const is_valid_before = std.ascii.isDigit(prev) or prev == '.' or prev == '-' or prev == '_';
        if (is_valid_before) {
            if (std.mem.startsWith(u8, s[i..], marker)) {
                const after = i + marker.len;
                if (after >= s.len or std.ascii.isDigit(s[after])) {
                    return i;
                }
            }
        }
    }
    return null;
}

/// Parse a version specifier like ">=1.0,<2.0"
pub fn parseSpec(allocator: std.mem.Allocator, input: []const u8) ParseError!VersionSpec {
    var constraints = std.ArrayList(VersionConstraint){};
    defer constraints.deinit(allocator);

    // Split by comma
    var iter = std.mem.splitScalar(u8, input, ',');
    while (iter.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;

        const constraint = try parseConstraint(allocator, trimmed);
        try constraints.append(allocator, constraint);
    }

    return .{ .constraints = try constraints.toOwnedSlice(allocator) };
}

fn parseConstraint(allocator: std.mem.Allocator, input: []const u8) ParseError!VersionConstraint {
    var s = input;
    var wildcard = false;

    // Extract operator
    const op_end: usize = blk: {
        if (std.mem.startsWith(u8, s, "===")) break :blk 3;
        if (std.mem.startsWith(u8, s, "~=")) break :blk 2;
        if (std.mem.startsWith(u8, s, "==")) break :blk 2;
        if (std.mem.startsWith(u8, s, "!=")) break :blk 2;
        if (std.mem.startsWith(u8, s, ">=")) break :blk 2;
        if (std.mem.startsWith(u8, s, "<=")) break :blk 2;
        if (std.mem.startsWith(u8, s, ">")) break :blk 1;
        if (std.mem.startsWith(u8, s, "<")) break :blk 1;
        break :blk 0;
    };

    const op = if (op_end > 0)
        Operator.fromStr(s[0..op_end]) orelse return ParseError.InvalidOperator
    else
        Operator.eq; // Default to == if no operator

    s = std.mem.trim(u8, s[op_end..], " \t");

    // For arbitrary equality (===), accept any string as "version"
    if (op == .arbitrary) {
        // Store the arbitrary string in local field since it's not a real version
        // Allocate a dummy release array so freeVersion can free it
        const release = try allocator.alloc(u32, 1);
        release[0] = 0;
        return .{
            .op = op,
            .version = .{
                .release = release,
                .local = s, // Store arbitrary string here
            },
            .wildcard = false,
        };
    }

    // Check for wildcard (only valid with == and !=)
    if (std.mem.endsWith(u8, s, ".*")) {
        if (op != .eq and op != .ne) {
            return ParseError.InvalidOperator; // Wildcard only allowed with == or !=
        }
        wildcard = true;
        s = s[0 .. s.len - 2];
    }

    const version = try parseVersion(allocator, s);

    // Local versions are only valid with == and != (PEP 440)
    if (version.local != null and op != .eq and op != .ne) {
        freeVersion(allocator, @constCast(&version));
        return ParseError.InvalidOperator;
    }

    return .{
        .op = op,
        .version = version,
        .wildcard = wildcard,
    };
}

/// Free a parsed version
pub fn freeVersion(allocator: std.mem.Allocator, v: *Version) void {
    if (v.release.len > 0) {
        allocator.free(v.release);
    }
}

/// Free a parsed spec
pub fn freeSpec(allocator: std.mem.Allocator, spec: *VersionSpec) void {
    // Need to use @constCast because constraints is []const
    const mutable_constraints = @constCast(spec.constraints);
    for (mutable_constraints) |*c| {
        freeVersion(allocator, &c.version);
    }
    if (spec.constraints.len > 0) {
        allocator.free(spec.constraints);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple versions" {
    const allocator = std.testing.allocator;

    var v1 = try parseVersion(allocator, "1.0");
    defer freeVersion(allocator, &v1);
    try std.testing.expectEqual(@as(u32, 1), v1.release[0]);
    try std.testing.expectEqual(@as(u32, 0), v1.release[1]);

    var v2 = try parseVersion(allocator, "2.3.4");
    defer freeVersion(allocator, &v2);
    try std.testing.expectEqual(@as(usize, 3), v2.release.len);
    try std.testing.expectEqual(@as(u32, 2), v2.release[0]);
    try std.testing.expectEqual(@as(u32, 3), v2.release[1]);
    try std.testing.expectEqual(@as(u32, 4), v2.release[2]);
}

test "parse version with epoch" {
    const allocator = std.testing.allocator;

    var v = try parseVersion(allocator, "1!2.0.0");
    defer freeVersion(allocator, &v);
    try std.testing.expectEqual(@as(u32, 1), v.epoch);
    try std.testing.expectEqual(@as(u32, 2), v.release[0]);
}

test "parse version with pre-release" {
    const allocator = std.testing.allocator;

    var v1 = try parseVersion(allocator, "1.0a1");
    defer freeVersion(allocator, &v1);
    try std.testing.expect(v1.pre != null);
    try std.testing.expectEqual(Version.PreRelease.PreKind.alpha, v1.pre.?.kind);
    try std.testing.expectEqual(@as(u32, 1), v1.pre.?.num);

    var v2 = try parseVersion(allocator, "2.0rc3");
    defer freeVersion(allocator, &v2);
    try std.testing.expect(v2.pre != null);
    try std.testing.expectEqual(Version.PreRelease.PreKind.rc, v2.pre.?.kind);
    try std.testing.expectEqual(@as(u32, 3), v2.pre.?.num);
}

test "parse version with post/dev" {
    const allocator = std.testing.allocator;

    var v1 = try parseVersion(allocator, "1.0.post1");
    defer freeVersion(allocator, &v1);
    try std.testing.expectEqual(@as(u32, 1), v1.post.?);

    var v2 = try parseVersion(allocator, "1.0.dev5");
    defer freeVersion(allocator, &v2);
    try std.testing.expectEqual(@as(u32, 5), v2.dev.?);
}

test "version comparison" {
    const allocator = std.testing.allocator;

    var v1 = try parseVersion(allocator, "1.0");
    defer freeVersion(allocator, &v1);
    var v2 = try parseVersion(allocator, "2.0");
    defer freeVersion(allocator, &v2);
    var v3 = try parseVersion(allocator, "1.0.0");
    defer freeVersion(allocator, &v3);

    try std.testing.expectEqual(std.math.Order.lt, v1.compare(v2));
    try std.testing.expectEqual(std.math.Order.gt, v2.compare(v1));
    try std.testing.expectEqual(std.math.Order.eq, v1.compare(v3)); // 1.0 == 1.0.0
}

test "pre-release ordering" {
    const allocator = std.testing.allocator;

    var v_dev = try parseVersion(allocator, "1.0.dev1");
    defer freeVersion(allocator, &v_dev);
    var v_alpha = try parseVersion(allocator, "1.0a1");
    defer freeVersion(allocator, &v_alpha);
    var v_release = try parseVersion(allocator, "1.0");
    defer freeVersion(allocator, &v_release);
    var v_post = try parseVersion(allocator, "1.0.post1");
    defer freeVersion(allocator, &v_post);

    // dev < alpha < release < post
    try std.testing.expectEqual(std.math.Order.lt, v_dev.compare(v_alpha));
    try std.testing.expectEqual(std.math.Order.lt, v_alpha.compare(v_release));
    try std.testing.expectEqual(std.math.Order.lt, v_release.compare(v_post));
}

test "parse version specifier" {
    const allocator = std.testing.allocator;

    var spec = try parseSpec(allocator, ">=1.0,<2.0");
    defer freeSpec(allocator, &spec);

    try std.testing.expectEqual(@as(usize, 2), spec.constraints.len);
    try std.testing.expectEqual(Operator.ge, spec.constraints[0].op);
    try std.testing.expectEqual(Operator.lt, spec.constraints[1].op);
}

test "version satisfies spec" {
    const allocator = std.testing.allocator;

    var spec = try parseSpec(allocator, ">=1.0,<2.0,!=1.5");
    defer freeSpec(allocator, &spec);

    var v_ok = try parseVersion(allocator, "1.4");
    defer freeVersion(allocator, &v_ok);
    var v_excluded = try parseVersion(allocator, "1.5");
    defer freeVersion(allocator, &v_excluded);
    var v_too_low = try parseVersion(allocator, "0.9");
    defer freeVersion(allocator, &v_too_low);
    var v_too_high = try parseVersion(allocator, "2.1");
    defer freeVersion(allocator, &v_too_high);

    try std.testing.expect(spec.satisfies(v_ok));
    try std.testing.expect(!spec.satisfies(v_excluded));
    try std.testing.expect(!spec.satisfies(v_too_low));
    try std.testing.expect(!spec.satisfies(v_too_high));
}

test "wildcard matching" {
    const allocator = std.testing.allocator;

    var spec = try parseSpec(allocator, "==1.0.*");
    defer freeSpec(allocator, &spec);

    var v1 = try parseVersion(allocator, "1.0.0");
    defer freeVersion(allocator, &v1);
    var v2 = try parseVersion(allocator, "1.0.5");
    defer freeVersion(allocator, &v2);
    var v3 = try parseVersion(allocator, "1.1.0");
    defer freeVersion(allocator, &v3);

    try std.testing.expect(spec.satisfies(v1));
    try std.testing.expect(spec.satisfies(v2));
    try std.testing.expect(!spec.satisfies(v3));
}

test "compatible release ~=" {
    const allocator = std.testing.allocator;

    var spec = try parseSpec(allocator, "~=1.4.2");
    defer freeSpec(allocator, &spec);

    var v_exact = try parseVersion(allocator, "1.4.2");
    defer freeVersion(allocator, &v_exact);
    var v_patch = try parseVersion(allocator, "1.4.9");
    defer freeVersion(allocator, &v_patch);
    var v_minor = try parseVersion(allocator, "1.5.0");
    defer freeVersion(allocator, &v_minor);
    var v_old = try parseVersion(allocator, "1.4.1");
    defer freeVersion(allocator, &v_old);

    try std.testing.expect(spec.satisfies(v_exact)); // ~=1.4.2 matches 1.4.2
    try std.testing.expect(spec.satisfies(v_patch)); // ~=1.4.2 matches 1.4.9
    try std.testing.expect(!spec.satisfies(v_minor)); // ~=1.4.2 does NOT match 1.5.0
    try std.testing.expect(!spec.satisfies(v_old)); // ~=1.4.2 does NOT match 1.4.1
}
