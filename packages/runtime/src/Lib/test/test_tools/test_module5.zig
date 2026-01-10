//! test.test_tools.test_patchcheck - Patch checking testing
//! Tests for Python's patch validation and code review tools
//! that verify patches conform to coding standards.

const std = @import("std");

/// Represents a unified diff hunk
pub const DiffHunk = struct {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    lines: []const DiffLine,
    header: ?[]const u8 = null,

    pub const DiffLine = struct {
        kind: Kind,
        content: []const u8,
        old_lineno: ?usize = null,
        new_lineno: ?usize = null,

        pub const Kind = enum {
            context,
            addition,
            deletion,
        };
    };

    pub fn additions(self: DiffHunk) usize {
        var count: usize = 0;
        for (self.lines) |line| {
            if (line.kind == .addition) count += 1;
        }
        return count;
    }

    pub fn deletions(self: DiffHunk) usize {
        var count: usize = 0;
        for (self.lines) |line| {
            if (line.kind == .deletion) count += 1;
        }
        return count;
    }

    pub fn contextLines(self: DiffHunk) usize {
        var count: usize = 0;
        for (self.lines) |line| {
            if (line.kind == .context) count += 1;
        }
        return count;
    }
};

/// Represents a file diff
pub const FileDiff = struct {
    old_path: []const u8,
    new_path: []const u8,
    hunks: []const DiffHunk,
    is_binary: bool = false,
    is_new_file: bool = false,
    is_deleted_file: bool = false,
    old_mode: ?u32 = null,
    new_mode: ?u32 = null,

    pub fn totalAdditions(self: FileDiff) usize {
        var count: usize = 0;
        for (self.hunks) |hunk| {
            count += hunk.additions();
        }
        return count;
    }

    pub fn totalDeletions(self: FileDiff) usize {
        var count: usize = 0;
        for (self.hunks) |hunk| {
            count += hunk.deletions();
        }
        return count;
    }

    pub fn isPythonFile(self: FileDiff) bool {
        return std.mem.endsWith(u8, self.new_path, ".py") or
            std.mem.endsWith(u8, self.old_path, ".py");
    }

    pub fn isCFile(self: FileDiff) bool {
        return std.mem.endsWith(u8, self.new_path, ".c") or
            std.mem.endsWith(u8, self.new_path, ".h") or
            std.mem.endsWith(u8, self.old_path, ".c") or
            std.mem.endsWith(u8, self.old_path, ".h");
    }

    pub fn isDocFile(self: FileDiff) bool {
        return std.mem.endsWith(u8, self.new_path, ".rst") or
            std.mem.endsWith(u8, self.new_path, ".md");
    }
};

/// Patch parser for unified diff format
pub const PatchParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PatchParser {
        return .{ .allocator = allocator };
    }

    pub fn parseHunkHeader(self: PatchParser, line: []const u8) !HunkHeader {
        _ = self;
        // Parse @@ -old_start,old_count +new_start,new_count @@
        if (!std.mem.startsWith(u8, line, "@@ ")) {
            return error.InvalidHunkHeader;
        }

        var header = HunkHeader{};

        const at_end = std.mem.indexOf(u8, line[3..], " @@") orelse return error.InvalidHunkHeader;
        const range_part = line[3 .. 3 + at_end];

        // Parse old range
        if (std.mem.indexOf(u8, range_part, " +")) |plus_idx| {
            const old_part = range_part[1..plus_idx];
            const new_part = range_part[plus_idx + 2 ..];

            if (std.mem.indexOf(u8, old_part, ",")) |comma| {
                header.old_start = std.fmt.parseInt(usize, old_part[0..comma], 10) catch 0;
                header.old_count = std.fmt.parseInt(usize, old_part[comma + 1 ..], 10) catch 0;
            } else {
                header.old_start = std.fmt.parseInt(usize, old_part, 10) catch 0;
                header.old_count = 1;
            }

            if (std.mem.indexOf(u8, new_part, ",")) |comma| {
                header.new_start = std.fmt.parseInt(usize, new_part[0..comma], 10) catch 0;
                header.new_count = std.fmt.parseInt(usize, new_part[comma + 1 ..], 10) catch 0;
            } else {
                header.new_start = std.fmt.parseInt(usize, new_part, 10) catch 0;
                header.new_count = 1;
            }
        }

        return header;
    }

    pub const HunkHeader = struct {
        old_start: usize = 0,
        old_count: usize = 0,
        new_start: usize = 0,
        new_count: usize = 0,
    };
};

/// Patch checker that validates patches against coding standards
pub const PatchChecker = struct {
    allocator: std.mem.Allocator,
    checks: std.ArrayList(Check),
    issues: std.ArrayList(Issue),
    config: Config,

    pub const Config = struct {
        check_whitespace: bool = true,
        check_pep8: bool = true,
        check_news: bool = true,
        check_docs: bool = true,
        max_line_length: usize = 79,
        ignore_patterns: []const []const u8 = &.{},
    };

    pub const Check = struct {
        name: []const u8,
        description: []const u8,
        severity: Severity,
        enabled: bool = true,
    };

    pub const Severity = enum {
        error_sev,
        warning,
        info,
    };

    pub const Issue = struct {
        check_name: []const u8,
        file_path: []const u8,
        line: ?usize,
        column: ?usize,
        message: []const u8,
        severity: Severity,

        pub fn format(self: Issue, allocator: std.mem.Allocator) ![]u8 {
            var result = std.ArrayList(u8).init(allocator);
            errdefer result.deinit();

            try result.appendSlice(self.file_path);
            if (self.line) |l| {
                try result.append(':');
                var buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&buf, "{d}", .{l}) catch "?";
                try result.appendSlice(line_str);
            }
            try result.appendSlice(": ");
            try result.appendSlice(@tagName(self.severity));
            try result.appendSlice(": ");
            try result.appendSlice(self.message);

            return result.toOwnedSlice();
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) PatchChecker {
        var self = PatchChecker{
            .allocator = allocator,
            .checks = std.ArrayList(Check).init(allocator),
            .issues = std.ArrayList(Issue).init(allocator),
            .config = config,
        };
        self.registerDefaultChecks() catch {};
        return self;
    }

    pub fn deinit(self: *PatchChecker) void {
        self.checks.deinit();
        self.issues.deinit();
    }

    fn registerDefaultChecks(self: *PatchChecker) !void {
        try self.checks.append(.{
            .name = "trailing_whitespace",
            .description = "Check for trailing whitespace",
            .severity = .warning,
        });
        try self.checks.append(.{
            .name = "tabs",
            .description = "Check for tab characters in Python files",
            .severity = .warning,
        });
        try self.checks.append(.{
            .name = "line_length",
            .description = "Check for lines exceeding max length",
            .severity = .warning,
        });
        try self.checks.append(.{
            .name = "news_entry",
            .description = "Check for NEWS entry",
            .severity = .info,
        });
    }

    pub fn checkLine(self: *PatchChecker, file_path: []const u8, line_num: usize, content: []const u8) !void {
        // Check trailing whitespace
        if (self.config.check_whitespace) {
            if (content.len > 0 and (content[content.len - 1] == ' ' or content[content.len - 1] == '\t')) {
                try self.issues.append(.{
                    .check_name = "trailing_whitespace",
                    .file_path = file_path,
                    .line = line_num,
                    .column = content.len,
                    .message = "trailing whitespace",
                    .severity = .warning,
                });
            }
        }

        // Check line length
        if (content.len > self.config.max_line_length) {
            try self.issues.append(.{
                .check_name = "line_length",
                .file_path = file_path,
                .line = line_num,
                .column = self.config.max_line_length,
                .message = "line too long",
                .severity = .warning,
            });
        }

        // Check for tabs in Python files
        if (std.mem.endsWith(u8, file_path, ".py")) {
            if (std.mem.indexOf(u8, content, "\t") != null) {
                try self.issues.append(.{
                    .check_name = "tabs",
                    .file_path = file_path,
                    .line = line_num,
                    .column = null,
                    .message = "tab character in Python file",
                    .severity = .warning,
                });
            }
        }
    }

    pub fn checkFileDiff(self: *PatchChecker, diff: FileDiff) !void {
        for (diff.hunks) |hunk| {
            for (hunk.lines) |line| {
                if (line.kind == .addition) {
                    if (line.new_lineno) |lineno| {
                        try self.checkLine(diff.new_path, lineno, line.content);
                    }
                }
            }
        }
    }

    pub fn hasErrors(self: PatchChecker) bool {
        for (self.issues.items) |issue| {
            if (issue.severity == .error_sev) return true;
        }
        return false;
    }

    pub fn hasWarnings(self: PatchChecker) bool {
        for (self.issues.items) |issue| {
            if (issue.severity == .warning) return true;
        }
        return false;
    }

    pub fn countByType(self: PatchChecker, severity: Severity) usize {
        var count: usize = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == severity) count += 1;
        }
        return count;
    }
};

/// News file checker for Misc/NEWS.d
pub const NewsChecker = struct {
    allocator: std.mem.Allocator,
    valid_sections: []const []const u8,
    issues: std.ArrayList(NewsIssue),

    pub const NewsIssue = struct {
        message: []const u8,
        file: ?[]const u8 = null,
        severity: PatchChecker.Severity,
    };

    pub fn init(allocator: std.mem.Allocator) NewsChecker {
        return .{
            .allocator = allocator,
            .valid_sections = &[_][]const u8{
                "Security",
                "Core and Builtins",
                "Library",
                "Documentation",
                "Tests",
                "Build",
                "Windows",
                "macOS",
                "IDLE",
                "Tools/Demos",
                "C API",
            },
            .issues = std.ArrayList(NewsIssue).init(allocator),
        };
    }

    pub fn deinit(self: *NewsChecker) void {
        self.issues.deinit();
    }

    pub fn checkNewsEntry(self: *NewsChecker, content: []const u8, filename: []const u8) !void {
        // Check for bpo/gh reference
        const has_bpo = std.mem.indexOf(u8, content, "bpo-") != null;
        const has_gh = std.mem.indexOf(u8, content, "gh-") != null;

        if (!has_bpo and !has_gh) {
            try self.issues.append(.{
                .message = "NEWS entry missing issue reference (bpo-XXXXX or gh-XXXXX)",
                .file = filename,
                .severity = .warning,
            });
        }

        // Check filename format: YYYY-MM-DD-XX-XX-XX.bpo-XXXXX.XXXXXX.rst
        if (!std.mem.endsWith(u8, filename, ".rst")) {
            try self.issues.append(.{
                .message = "NEWS entry must be a .rst file",
                .file = filename,
                .severity = .error_sev,
            });
        }
    }

    pub fn isValidSection(self: NewsChecker, section: []const u8) bool {
        for (self.valid_sections) |valid| {
            if (std.mem.eql(u8, section, valid)) return true;
        }
        return false;
    }

    pub fn hasIssues(self: NewsChecker) bool {
        return self.issues.items.len > 0;
    }
};

/// Documentation checker
pub const DocChecker = struct {
    allocator: std.mem.Allocator,
    issues: std.ArrayList(DocIssue),

    pub const DocIssue = struct {
        kind: Kind,
        file: []const u8,
        line: ?usize,
        message: []const u8,

        pub const Kind = enum {
            missing_versionadded,
            missing_versionchanged,
            broken_link,
            invalid_directive,
            spelling,
        };
    };

    pub fn init(allocator: std.mem.Allocator) DocChecker {
        return .{
            .allocator = allocator,
            .issues = std.ArrayList(DocIssue).init(allocator),
        };
    }

    pub fn deinit(self: *DocChecker) void {
        self.issues.deinit();
    }

    pub fn checkRstLine(self: *DocChecker, file: []const u8, line_num: usize, content: []const u8) !void {
        // Check for common RST issues
        if (std.mem.indexOf(u8, content, ".. versionadded::")) |_| {
            // Check version format
            if (std.mem.indexOf(u8, content, "::") == null) {
                try self.issues.append(.{
                    .kind = .invalid_directive,
                    .file = file,
                    .line = line_num,
                    .message = "Invalid versionadded directive format",
                });
            }
        }

        // Check for broken internal references
        if (std.mem.indexOf(u8, content, ":ref:`")) |ref_start| {
            const after_ref = content[ref_start + 6 ..];
            if (std.mem.indexOf(u8, after_ref, "`") == null) {
                try self.issues.append(.{
                    .kind = .broken_link,
                    .file = file,
                    .line = line_num,
                    .message = "Unclosed reference",
                });
            }
        }
    }

    pub fn hasIssues(self: DocChecker) bool {
        return self.issues.items.len > 0;
    }
};

/// Whitespace normalizer
pub const WhitespaceNormalizer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WhitespaceNormalizer {
        return .{ .allocator = allocator };
    }

    pub fn stripTrailing(self: WhitespaceNormalizer, content: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var lines = std.mem.split(u8, content, "\n");
        var first = true;
        while (lines.next()) |line| {
            if (!first) {
                try result.append('\n');
            }
            first = false;

            const trimmed = std.mem.trimRight(u8, line, " \t\r");
            try result.appendSlice(trimmed);
        }

        return result.toOwnedSlice();
    }

    pub fn tabsToSpaces(self: WhitespaceNormalizer, content: []const u8, tab_width: usize) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var col: usize = 0;
        for (content) |c| {
            if (c == '\t') {
                const spaces_needed = tab_width - (col % tab_width);
                var i: usize = 0;
                while (i < spaces_needed) : (i += 1) {
                    try result.append(' ');
                }
                col += spaces_needed;
            } else if (c == '\n') {
                try result.append(c);
                col = 0;
            } else {
                try result.append(c);
                col += 1;
            }
        }

        return result.toOwnedSlice();
    }

    pub fn ensureNewlineAtEnd(self: WhitespaceNormalizer, content: []const u8) ![]u8 {
        if (content.len == 0 or content[content.len - 1] != '\n') {
            var result = std.ArrayList(u8).init(self.allocator);
            errdefer result.deinit();
            try result.appendSlice(content);
            try result.append('\n');
            return result.toOwnedSlice();
        }
        return self.allocator.dupe(u8, content);
    }
};

/// Patch statistics
pub const PatchStats = struct {
    files_changed: usize = 0,
    insertions: usize = 0,
    deletions: usize = 0,
    python_files: usize = 0,
    c_files: usize = 0,
    doc_files: usize = 0,
    test_files: usize = 0,

    pub fn addFileDiff(self: *PatchStats, diff: FileDiff) void {
        self.files_changed += 1;
        self.insertions += diff.totalAdditions();
        self.deletions += diff.totalDeletions();

        if (diff.isPythonFile()) self.python_files += 1;
        if (diff.isCFile()) self.c_files += 1;
        if (diff.isDocFile()) self.doc_files += 1;
        if (std.mem.indexOf(u8, diff.new_path, "test") != null) self.test_files += 1;
    }

    pub fn netChange(self: PatchStats) i64 {
        return @as(i64, @intCast(self.insertions)) - @as(i64, @intCast(self.deletions));
    }

    pub fn format(self: PatchStats, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var buf: [128]u8 = undefined;
        const summary = std.fmt.bufPrint(&buf, "{d} files changed, {d} insertions(+), {d} deletions(-)", .{
            self.files_changed,
            self.insertions,
            self.deletions,
        }) catch "stats unavailable";

        try result.appendSlice(summary);
        return result.toOwnedSlice();
    }
};

// Tests
test "diff_hunk_counts" {
    const hunk = DiffHunk{
        .old_start = 1,
        .old_count = 5,
        .new_start = 1,
        .new_count = 7,
        .lines = &[_]DiffHunk.DiffLine{
            .{ .kind = .context, .content = " line1" },
            .{ .kind = .deletion, .content = "-removed" },
            .{ .kind = .addition, .content = "+added1" },
            .{ .kind = .addition, .content = "+added2" },
            .{ .kind = .context, .content = " line2" },
        },
    };

    try std.testing.expectEqual(@as(usize, 2), hunk.additions());
    try std.testing.expectEqual(@as(usize, 1), hunk.deletions());
    try std.testing.expectEqual(@as(usize, 2), hunk.contextLines());
}

test "file_diff_totals" {
    const hunk1 = DiffHunk{
        .old_start = 1,
        .old_count = 1,
        .new_start = 1,
        .new_count = 2,
        .lines = &[_]DiffHunk.DiffLine{
            .{ .kind = .addition, .content = "+new" },
        },
    };
    const hunk2 = DiffHunk{
        .old_start = 10,
        .old_count = 2,
        .new_start = 11,
        .new_count = 1,
        .lines = &[_]DiffHunk.DiffLine{
            .{ .kind = .deletion, .content = "-old" },
            .{ .kind = .deletion, .content = "-old2" },
        },
    };

    const diff = FileDiff{
        .old_path = "test.py",
        .new_path = "test.py",
        .hunks = &[_]DiffHunk{ hunk1, hunk2 },
    };

    try std.testing.expectEqual(@as(usize, 1), diff.totalAdditions());
    try std.testing.expectEqual(@as(usize, 2), diff.totalDeletions());
    try std.testing.expect(diff.isPythonFile());
}

test "file_diff_types" {
    const py_diff = FileDiff{ .old_path = "foo.py", .new_path = "foo.py", .hunks = &.{} };
    try std.testing.expect(py_diff.isPythonFile());
    try std.testing.expect(!py_diff.isCFile());

    const c_diff = FileDiff{ .old_path = "module.c", .new_path = "module.c", .hunks = &.{} };
    try std.testing.expect(c_diff.isCFile());
    try std.testing.expect(!c_diff.isPythonFile());

    const doc_diff = FileDiff{ .old_path = "doc.rst", .new_path = "doc.rst", .hunks = &.{} };
    try std.testing.expect(doc_diff.isDocFile());
}

test "patch_parser_hunk_header" {
    const parser = PatchParser.init(std.testing.allocator);

    const header = try parser.parseHunkHeader("@@ -1,5 +1,7 @@ def foo():");
    try std.testing.expectEqual(@as(usize, 1), header.old_start);
    try std.testing.expectEqual(@as(usize, 5), header.old_count);
    try std.testing.expectEqual(@as(usize, 1), header.new_start);
    try std.testing.expectEqual(@as(usize, 7), header.new_count);
}

test "patch_checker_whitespace" {
    var checker = PatchChecker.init(std.testing.allocator, .{});
    defer checker.deinit();

    try checker.checkLine("test.py", 1, "valid line");
    try std.testing.expectEqual(@as(usize, 0), checker.issues.items.len);

    try checker.checkLine("test.py", 2, "trailing space ");
    try std.testing.expectEqual(@as(usize, 1), checker.issues.items.len);
    try std.testing.expect(checker.hasWarnings());
}

test "patch_checker_line_length" {
    var checker = PatchChecker.init(std.testing.allocator, .{ .max_line_length = 10 });
    defer checker.deinit();

    try checker.checkLine("test.py", 1, "short");
    try std.testing.expectEqual(@as(usize, 0), checker.issues.items.len);

    try checker.checkLine("test.py", 2, "this line is way too long");
    try std.testing.expectEqual(@as(usize, 1), checker.issues.items.len);
}

test "news_checker" {
    var checker = NewsChecker.init(std.testing.allocator);
    defer checker.deinit();

    try checker.checkNewsEntry("Fixed a bug in module.", "entry.rst");
    try std.testing.expect(checker.hasIssues());

    checker.issues.clearRetainingCapacity();

    try checker.checkNewsEntry("Fixed bpo-12345: a bug in module.", "entry.rst");
    try std.testing.expect(!checker.hasIssues());
}

test "news_checker_sections" {
    const checker = NewsChecker.init(std.testing.allocator);

    try std.testing.expect(checker.isValidSection("Library"));
    try std.testing.expect(checker.isValidSection("Core and Builtins"));
    try std.testing.expect(!checker.isValidSection("Invalid Section"));
}

test "doc_checker" {
    var checker = DocChecker.init(std.testing.allocator);
    defer checker.deinit();

    try checker.checkRstLine("doc.rst", 1, "Normal text");
    try std.testing.expect(!checker.hasIssues());
}

test "whitespace_normalizer_strip" {
    const normalizer = WhitespaceNormalizer.init(std.testing.allocator);

    const input = "line1   \nline2\t\nline3";
    const result = try normalizer.stripTrailing(input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("line1\nline2\nline3", result);
}

test "whitespace_normalizer_tabs" {
    const normalizer = WhitespaceNormalizer.init(std.testing.allocator);

    const input = "\thello";
    const result = try normalizer.tabsToSpaces(input, 4);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("    hello", result);
}

test "whitespace_normalizer_newline" {
    const normalizer = WhitespaceNormalizer.init(std.testing.allocator);

    const without = try normalizer.ensureNewlineAtEnd("content");
    defer std.testing.allocator.free(without);
    try std.testing.expectEqualStrings("content\n", without);

    const with = try normalizer.ensureNewlineAtEnd("content\n");
    defer std.testing.allocator.free(with);
    try std.testing.expectEqualStrings("content\n", with);
}

test "patch_stats" {
    var stats = PatchStats{};

    const diff = FileDiff{
        .old_path = "test.py",
        .new_path = "test.py",
        .hunks = &[_]DiffHunk{
            .{
                .old_start = 1,
                .old_count = 1,
                .new_start = 1,
                .new_count = 3,
                .lines = &[_]DiffHunk.DiffLine{
                    .{ .kind = .addition, .content = "+a" },
                    .{ .kind = .addition, .content = "+b" },
                },
            },
        },
    };

    stats.addFileDiff(diff);

    try std.testing.expectEqual(@as(usize, 1), stats.files_changed);
    try std.testing.expectEqual(@as(usize, 2), stats.insertions);
    try std.testing.expectEqual(@as(usize, 1), stats.python_files);
    try std.testing.expectEqual(@as(i64, 2), stats.netChange());
}

test "issue_format" {
    const issue = PatchChecker.Issue{
        .check_name = "trailing_whitespace",
        .file_path = "test.py",
        .line = 42,
        .column = 80,
        .message = "trailing whitespace",
        .severity = .warning,
    };

    const formatted = try issue.format(std.testing.allocator);
    defer std.testing.allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning") != null);
}
