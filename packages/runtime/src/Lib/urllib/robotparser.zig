//! Python 'urllib.robotparser' module - robots.txt parser
//!
//! Provides RobotFileParser class for parsing and interpreting robots.txt files.
//!
//! Mirrors: CPython Lib/urllib/robotparser.py

const std = @import("std");
const parse = @import("parse.zig");

pub const RobotFileParser = struct {
    allocator: std.mem.Allocator,
    url: ?[]const u8,
    disallow_all: bool,
    allow_all: bool,
    rules: std.ArrayList(Rule),

    const Rule = struct {
        useragent: []const u8,
        disallow: std.ArrayList([]const u8),
        allow: std.ArrayList([]const u8),
    };

    pub fn init(allocator: std.mem.Allocator, url: ?[]const u8) RobotFileParser {
        return .{
            .allocator = allocator,
            .url = url,
            .disallow_all = false,
            .allow_all = false,
            .rules = .{},
        };
    }

    pub fn deinit(self: *RobotFileParser) void {
        for (self.rules.items) |*rule| {
            rule.disallow.deinit(self.allocator);
            rule.allow.deinit(self.allocator);
        }
        self.rules.deinit(self.allocator);
    }

    pub fn setUrl(self: *RobotFileParser, url: []const u8) void {
        self.url = url;
    }

    pub fn read(self: *RobotFileParser) !void {
        if (self.url) |url| {
            // Fetch robots.txt using HTTP
            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit();

            const uri = std.Uri.parse(url) catch return;
            var req = client.open(.GET, uri, .{}) catch return;
            defer req.deinit();

            req.send() catch return;
            req.wait() catch return;

            // Read response body
            var body_buf: [64 * 1024]u8 = undefined;
            const body_len = req.reader().readAll(&body_buf) catch return;
            const body = body_buf[0..body_len];

            // Split into lines and parse
            var lines: std.ArrayList([]const u8) = .{};
            defer lines.deinit(self.allocator);

            var iter = std.mem.splitScalar(u8, body, '\n');
            while (iter.next()) |line| {
                lines.append(self.allocator, line) catch unreachable;
            }

            try self.parseLines(lines.items);
        }
    }

    pub fn parseLines(self: *RobotFileParser, lines: []const []const u8) !void {
        var current_useragent: ?[]const u8 = null;
        var current_rule: ?*Rule = null;

        for (lines) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                const key = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                const value = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t");

                if (std.ascii.eqlIgnoreCase(key, "user-agent")) {
                    current_useragent = value;
                    try self.rules.append(self.allocator, .{
                        .useragent = value,
                        .disallow = .{},
                        .allow = .{},
                    });
                    current_rule = &self.rules.items[self.rules.items.len - 1];
                } else if (current_rule) |rule| {
                    if (std.ascii.eqlIgnoreCase(key, "disallow")) {
                        try rule.disallow.append(self.allocator, value);
                    } else if (std.ascii.eqlIgnoreCase(key, "allow")) {
                        try rule.allow.append(self.allocator, value);
                    }
                }
            }
        }
        _ = current_useragent;
    }

    pub fn canFetch(self: *RobotFileParser, useragent: []const u8, url: []const u8) bool {
        if (self.disallow_all) return false;
        if (self.allow_all) return true;

        const parsed = parse.urlparse(url);

        for (self.rules.items) |rule| {
            if (std.mem.eql(u8, rule.useragent, "*") or
                std.mem.indexOf(u8, useragent, rule.useragent) != null)
            {
                // Check allow first
                for (rule.allow.items) |pattern| {
                    if (std.mem.startsWith(u8, parsed.path, pattern)) {
                        return true;
                    }
                }
                // Then disallow
                for (rule.disallow.items) |pattern| {
                    if (pattern.len == 0) continue;
                    if (std.mem.startsWith(u8, parsed.path, pattern)) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    pub fn mtime(self: *RobotFileParser) ?i64 {
        _ = self;
        return null;
    }

    pub fn modified(self: *RobotFileParser) void {
        _ = self;
        // Update mtime
    }
};
