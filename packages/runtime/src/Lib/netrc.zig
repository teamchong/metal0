//! CPython source: Lib/netrc.py
//!
//! Provides netrc file parsing functionality.
//!
//! Mirrors: CPython Lib/netrc.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const NetrcParseError = error{
    /// Bad machine name
    BadMachineName,
    /// Bad default entry
    BadDefaultEntry,
    /// Missing account name
    MissingAccount,
    /// Bad toplevel token
    BadTopLevelToken,
    /// File not found
    FileNotFound,
    /// Parse error
    ParseError,
    /// Premature EOF
    PrematureEof,
};

// ============================================================================
// Authenticator
// ============================================================================

/// Authentication info for a host
pub const Authenticator = struct {
    login: []const u8,
    account: ?[]const u8,
    password: []const u8,
};

// ============================================================================
// Netrc
// ============================================================================

/// Parser for .netrc files
pub const Netrc = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    hosts: hashmap_helper.StringHashMap(Authenticator),
    macros: hashmap_helper.StringHashMap([]const u8),
    default_entry: ?Authenticator,

    pub fn init(allocator: std.mem.Allocator, file: ?[]const u8) !Self {
        var self = Self{
            .allocator = allocator,
            .hosts = hashmap_helper.StringHashMap(Authenticator).init(allocator),
            .macros = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .default_entry = null,
        };

        const filename = file orelse try self.getDefaultFile();
        try self.parse(filename);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.hosts.deinit();
        self.macros.deinit();
    }

    /// Get default netrc file path
    fn getDefaultFile(self: *Self) ![]const u8 {
        _ = self;
        // Check $NETRC first
        if (std.posix.getenv("NETRC")) |netrc| {
            return netrc;
        }
        // Fall back to ~/.netrc
        if (std.posix.getenv("HOME")) |home| {
            _ = home;
            return "~/.netrc";
        }
        return NetrcParseError.FileNotFound;
    }

    /// Parse a netrc file
    fn parse(self: *Self, filename: []const u8) !void {
        // Expand ~ in path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var actual_path: []const u8 = filename;

        if (std.mem.startsWith(u8, filename, "~/")) {
            if (std.posix.getenv("HOME")) |home| {
                actual_path = try std.fmt.bufPrint(&path_buf, "{s}{s}", .{ home, filename[1..] });
            }
        }

        const file = std.fs.openFileAbsolute(actual_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        var line_buf: [4096]u8 = undefined;
        var current_machine: ?[]const u8 = null;
        var current_login: ?[]const u8 = null;
        var current_account: ?[]const u8 = null;
        var current_password: ?[]const u8 = null;
        var in_macro: bool = false;
        var macro_name: ?[]const u8 = null;
        var macro_lines = std.ArrayList(u8).init(self.allocator);
        defer macro_lines.deinit();

        while (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch null) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            // Skip comments
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Handle macros
            if (in_macro) {
                if (trimmed.len == 0) {
                    // End of macro
                    if (macro_name) |name| {
                        try self.macros.put(name, try macro_lines.toOwnedSlice());
                    }
                    in_macro = false;
                    macro_name = null;
                } else {
                    try macro_lines.appendSlice(trimmed);
                    try macro_lines.append('\n');
                }
                continue;
            }

            var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
            while (tokens.next()) |token| {
                if (std.mem.eql(u8, token, "machine")) {
                    // Save previous entry
                    if (current_machine) |machine| {
                        if (current_login) |login| {
                            try self.hosts.put(machine, .{
                                .login = login,
                                .account = current_account,
                                .password = current_password orelse "",
                            });
                        }
                    }
                    current_machine = tokens.next();
                    current_login = null;
                    current_account = null;
                    current_password = null;
                } else if (std.mem.eql(u8, token, "default")) {
                    // Save previous entry
                    if (current_machine) |machine| {
                        if (current_login) |login| {
                            try self.hosts.put(machine, .{
                                .login = login,
                                .account = current_account,
                                .password = current_password orelse "",
                            });
                        }
                    }
                    current_machine = null;
                    current_login = null;
                    current_account = null;
                    current_password = null;
                } else if (std.mem.eql(u8, token, "login")) {
                    current_login = tokens.next();
                } else if (std.mem.eql(u8, token, "password") or std.mem.eql(u8, token, "passwd")) {
                    current_password = tokens.next();
                } else if (std.mem.eql(u8, token, "account")) {
                    current_account = tokens.next();
                } else if (std.mem.eql(u8, token, "macdef")) {
                    macro_name = tokens.next();
                    in_macro = true;
                    macro_lines.clearRetainingCapacity();
                }
            }
        }

        // Save last entry
        if (current_machine) |machine| {
            if (current_login) |login| {
                try self.hosts.put(machine, .{
                    .login = login,
                    .account = current_account,
                    .password = current_password orelse "",
                });
            }
        } else if (current_login != null) {
            // Default entry
            self.default_entry = .{
                .login = current_login.?,
                .account = current_account,
                .password = current_password orelse "",
            };
        }
    }

    /// Get authenticator for a host
    pub fn authenticators(self: *Self, host: []const u8) ?Authenticator {
        if (self.hosts.get(host)) |auth| {
            return auth;
        }
        return self.default_entry;
    }

    /// Get hosts dictionary
    pub fn getHosts(self: *Self) hashmap_helper.StringHashMap(Authenticator) {
        return self.hosts;
    }

    /// Get macros dictionary
    pub fn getMacros(self: *Self) hashmap_helper.StringHashMap([]const u8) {
        return self.macros;
    }

    /// Format as string (for writing back)
    pub fn format(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var it = self.hosts.iterator();
        while (it.next()) |entry| {
            try result.appendSlice("machine ");
            try result.appendSlice(entry.key_ptr.*);
            try result.append('\n');
            try result.appendSlice("\tlogin ");
            try result.appendSlice(entry.value_ptr.login);
            try result.append('\n');
            if (entry.value_ptr.account) |account| {
                try result.appendSlice("\taccount ");
                try result.appendSlice(account);
                try result.append('\n');
            }
            try result.appendSlice("\tpassword ");
            try result.appendSlice(entry.value_ptr.password);
            try result.append('\n');
        }

        if (self.default_entry) |def| {
            try result.appendSlice("default\n");
            try result.appendSlice("\tlogin ");
            try result.appendSlice(def.login);
            try result.append('\n');
            if (def.account) |account| {
                try result.appendSlice("\taccount ");
                try result.appendSlice(account);
                try result.append('\n');
            }
            try result.appendSlice("\tpassword ");
            try result.appendSlice(def.password);
            try result.append('\n');
        }

        var macro_it = self.macros.iterator();
        while (macro_it.next()) |entry| {
            try result.appendSlice("macdef ");
            try result.appendSlice(entry.key_ptr.*);
            try result.append('\n');
            try result.appendSlice(entry.value_ptr.*);
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Parse netrc file and return Netrc instance
pub fn netrc(allocator: std.mem.Allocator, file: ?[]const u8) !Netrc {
    return Netrc.init(allocator, file);
}

// ============================================================================
// Tests
// ============================================================================

test "Netrc init without file" {
    const allocator = std.testing.allocator;
    var n = try Netrc.init(allocator, null);
    defer n.deinit();
    // Should not error even if file doesn't exist
}

test "Authenticator structure" {
    const auth = Authenticator{
        .login = "user",
        .account = "acct",
        .password = "pass",
    };
    try std.testing.expectEqualStrings("user", auth.login);
    try std.testing.expectEqualStrings("acct", auth.account.?);
    try std.testing.expectEqualStrings("pass", auth.password);
}

test "Authenticator without account" {
    const auth = Authenticator{
        .login = "user",
        .account = null,
        .password = "pass",
    };
    try std.testing.expect(auth.account == null);
}

test "Netrc format" {
    const allocator = std.testing.allocator;
    var n = try Netrc.init(allocator, null);
    defer n.deinit();

    try n.hosts.put("example.com", .{
        .login = "testuser",
        .account = null,
        .password = "testpass",
    });

    const formatted = try n.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "machine example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "login testuser") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "password testpass") != null);
}
