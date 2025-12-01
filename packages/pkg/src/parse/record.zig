//! RECORD Parser (CSV)
//!
//! Parses dist-info/RECORD files that list all installed files.
//!
//! ## Format (CSV)
//! ```
//! path,hash,size
//! numpy/__init__.py,sha256=abc123,1234
//! numpy/core/_multiarray.so,sha256=def456,567890
//! numpy-1.24.0.dist-info/RECORD,,
//! ```
//!
//! Reference: https://packaging.python.org/en/latest/specifications/recording-installed-packages/

const std = @import("std");

/// A single installed file entry
pub const InstalledFile = struct {
    path: []const u8,
    hash: ?Hash = null,
    size: ?u64 = null,

    pub const Hash = struct {
        algorithm: Algorithm,
        digest: []const u8,

        pub const Algorithm = enum {
            sha256,
            sha384,
            sha512,
            md5, // Deprecated but still seen

            pub fn fromStr(s: []const u8) ?Algorithm {
                if (std.ascii.eqlIgnoreCase(s, "sha256")) return .sha256;
                if (std.ascii.eqlIgnoreCase(s, "sha384")) return .sha384;
                if (std.ascii.eqlIgnoreCase(s, "sha512")) return .sha512;
                if (std.ascii.eqlIgnoreCase(s, "md5")) return .md5;
                return null;
            }
        };

        /// Verify this hash against file content
        pub fn verify(self: Hash, content: []const u8) bool {
            return switch (self.algorithm) {
                .sha256 => verifySha256(self.digest, content),
                .sha384 => verifySha384(self.digest, content),
                .sha512 => verifySha512(self.digest, content),
                .md5 => verifyMd5(self.digest, content),
            };
        }
    };

    /// Check if this is a Python source file
    pub fn isPythonSource(self: InstalledFile) bool {
        return std.mem.endsWith(u8, self.path, ".py");
    }

    /// Check if this is a native extension
    pub fn isNativeExtension(self: InstalledFile) bool {
        return std.mem.endsWith(u8, self.path, ".so") or
            std.mem.endsWith(u8, self.path, ".dylib") or
            std.mem.endsWith(u8, self.path, ".pyd") or
            std.mem.endsWith(u8, self.path, ".dll");
    }

    /// Check if this is metadata
    pub fn isMetadata(self: InstalledFile) bool {
        return std.mem.indexOf(u8, self.path, ".dist-info/") != null or
            std.mem.indexOf(u8, self.path, ".egg-info/") != null;
    }
};

/// Parsed RECORD file
pub const Record = struct {
    files: []const InstalledFile,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Record) void {
        self.allocator.free(self.files);
    }

    /// Find a file by path
    pub fn findByPath(self: Record, path: []const u8) ?InstalledFile {
        for (self.files) |f| {
            if (std.mem.eql(u8, f.path, path)) return f;
        }
        return null;
    }

    /// Get all native extensions
    pub fn nativeExtensions(self: Record, allocator: std.mem.Allocator) ![]const InstalledFile {
        var result = std.ArrayList(InstalledFile){};
        errdefer result.deinit(allocator);

        for (self.files) |f| {
            if (f.isNativeExtension()) {
                try result.append(allocator, f);
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Get all Python source files
    pub fn pythonFiles(self: Record, allocator: std.mem.Allocator) ![]const InstalledFile {
        var result = std.ArrayList(InstalledFile){};
        errdefer result.deinit(allocator);

        for (self.files) |f| {
            if (f.isPythonSource()) {
                try result.append(allocator, f);
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Get total size of all files
    pub fn totalSize(self: Record) u64 {
        var total: u64 = 0;
        for (self.files) |f| {
            if (f.size) |s| total += s;
        }
        return total;
    }
};

pub const ParseError = error{
    InvalidFormat,
    InvalidHash,
    OutOfMemory,
};

/// Parse RECORD file content
pub fn parse(allocator: std.mem.Allocator, content: []const u8) ParseError!Record {
    var files = std.ArrayList(InstalledFile){};
    errdefer files.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (line.len == 0) continue;

        const file = try parseLine(line);
        try files.append(allocator, file);
    }

    return .{
        .files = try files.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn parseLine(line: []const u8) ParseError!InstalledFile {
    var file = InstalledFile{ .path = "" };

    // CSV format: path,hash,size
    // Handle quoted paths (rare but possible)
    var fields: [3][]const u8 = .{ "", "", "" };
    var field_idx: usize = 0;
    var start: usize = 0;
    var in_quotes = false;

    for (line, 0..) |c, i| {
        if (c == '"') {
            in_quotes = !in_quotes;
        } else if (c == ',' and !in_quotes) {
            if (field_idx < 3) {
                fields[field_idx] = unquote(line[start..i]);
                field_idx += 1;
                start = i + 1;
            }
        }
    }
    // Last field
    if (field_idx < 3 and start <= line.len) {
        fields[field_idx] = unquote(line[start..]);
    }

    file.path = fields[0];
    if (file.path.len == 0) return ParseError.InvalidFormat;

    // Parse hash (format: algorithm=digest)
    if (fields[1].len > 0) {
        if (std.mem.indexOf(u8, fields[1], "=")) |eq_pos| {
            const algo_str = fields[1][0..eq_pos];
            const digest = fields[1][eq_pos + 1 ..];

            if (InstalledFile.Hash.Algorithm.fromStr(algo_str)) |algo| {
                file.hash = .{
                    .algorithm = algo,
                    .digest = digest,
                };
            } else {
                return ParseError.InvalidHash;
            }
        }
    }

    // Parse size
    if (fields[2].len > 0) {
        file.size = std.fmt.parseInt(u64, fields[2], 10) catch null;
    }

    return file;
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') {
        return s[1 .. s.len - 1];
    }
    return s;
}

// Hash verification helpers
fn verifySha256(expected: []const u8, content: []const u8) bool {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});
    const actual = std.fmt.bytesToHex(hash, .lower);
    return std.mem.eql(u8, expected, &actual);
}

fn verifySha384(expected: []const u8, content: []const u8) bool {
    var hash: [48]u8 = undefined;
    std.crypto.hash.sha2.Sha384.hash(content, &hash, .{});
    const actual = std.fmt.bytesToHex(hash, .lower);
    return std.mem.eql(u8, expected, &actual);
}

fn verifySha512(expected: []const u8, content: []const u8) bool {
    var hash: [64]u8 = undefined;
    std.crypto.hash.sha2.Sha512.hash(content, &hash, .{});
    const actual = std.fmt.bytesToHex(hash, .lower);
    return std.mem.eql(u8, expected, &actual);
}

fn verifyMd5(expected: []const u8, content: []const u8) bool {
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(content, &hash, .{});
    const actual = std.fmt.bytesToHex(hash, .lower);
    return std.mem.eql(u8, expected, &actual);
}

/// Parse RECORD from a file path
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !Record {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    return parse(allocator, content);
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple record" {
    const allocator = std.testing.allocator;

    const content =
        \\numpy/__init__.py,sha256=abc123def456,1234
        \\numpy/core/_multiarray.so,sha256=def456abc789,567890
        \\numpy-1.24.0.dist-info/RECORD,,
    ;

    var rec = try parse(allocator, content);
    defer rec.deinit();

    try std.testing.expectEqual(@as(usize, 3), rec.files.len);
    try std.testing.expectEqualStrings("numpy/__init__.py", rec.files[0].path);
    try std.testing.expectEqual(InstalledFile.Hash.Algorithm.sha256, rec.files[0].hash.?.algorithm);
    try std.testing.expectEqual(@as(u64, 1234), rec.files[0].size.?);
}

test "identify file types" {
    const allocator = std.testing.allocator;

    const content =
        \\numpy/__init__.py,sha256=abc,100
        \\numpy/core/_multiarray.cpython-311-x86_64-linux-gnu.so,sha256=def,200
        \\numpy-1.24.0.dist-info/METADATA,sha256=ghi,300
    ;

    var rec = try parse(allocator, content);
    defer rec.deinit();

    try std.testing.expect(rec.files[0].isPythonSource());
    try std.testing.expect(!rec.files[0].isNativeExtension());

    try std.testing.expect(!rec.files[1].isPythonSource());
    try std.testing.expect(rec.files[1].isNativeExtension());

    try std.testing.expect(rec.files[2].isMetadata());
}

test "get native extensions" {
    const allocator = std.testing.allocator;

    const content =
        \\numpy/__init__.py,sha256=abc,100
        \\numpy/core/_multiarray.so,sha256=def,200
        \\numpy/linalg/_umath_linalg.so,sha256=ghi,300
    ;

    var rec = try parse(allocator, content);
    defer rec.deinit();

    const exts = try rec.nativeExtensions(allocator);
    defer allocator.free(exts);

    try std.testing.expectEqual(@as(usize, 2), exts.len);
    try std.testing.expect(std.mem.endsWith(u8, exts[0].path, ".so"));
    try std.testing.expect(std.mem.endsWith(u8, exts[1].path, ".so"));
}

test "total size" {
    const allocator = std.testing.allocator;

    const content =
        \\file1.py,sha256=abc,100
        \\file2.py,sha256=def,200
        \\file3.py,sha256=ghi,300
    ;

    var rec = try parse(allocator, content);
    defer rec.deinit();

    try std.testing.expectEqual(@as(u64, 600), rec.totalSize());
}

test "parse empty hash and size" {
    const allocator = std.testing.allocator;

    const content =
        \\package-1.0.dist-info/RECORD,,
    ;

    var rec = try parse(allocator, content);
    defer rec.deinit();

    try std.testing.expectEqual(@as(usize, 1), rec.files.len);
    try std.testing.expect(rec.files[0].hash == null);
    try std.testing.expect(rec.files[0].size == null);
}
