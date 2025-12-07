//! Python 'configparser' module - Configuration file parser
//!
//! Provides ConfigParser for reading and writing INI-style configuration files.
//!
//! Mirrors: CPython Lib/configparser.py

const std = @import("std");

// ============================================================================
// Interpolation Classes
// ============================================================================

/// No interpolation
pub const BasicInterpolation = struct {
    pub fn beforeGet(self: *BasicInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8, defaults: anytype) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        _ = defaults;
        return value;
    }

    pub fn beforeSet(self: *BasicInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        return value;
    }
};

/// Extended interpolation with ${section:option} syntax
pub const ExtendedInterpolation = struct {
    pub fn beforeGet(self: *ExtendedInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8, defaults: anytype) ![]const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        _ = defaults;
        // Would perform ${section:option} interpolation
        return value;
    }

    pub fn beforeSet(self: *ExtendedInterpolation, parser: anytype, section: []const u8, option: []const u8, value: []const u8) []const u8 {
        _ = self;
        _ = parser;
        _ = section;
        _ = option;
        return value;
    }
};

// ============================================================================
// ConfigParser
// ============================================================================

/// Configuration file parser
pub const ConfigParser = struct {
    const Self = @This();

    pub const Options = struct {
        delimiters: []const u8 = "=:",
        comment_prefixes: []const u8 = "#;",
        inline_comment_prefixes: ?[]const u8 = null,
        strict: bool = true,
        empty_lines_in_values: bool = true,
        default_section: []const u8 = "DEFAULT",
        allow_no_value: bool = false,
    };

    allocator: std.mem.Allocator,
    sections: std.StringHashMap(std.StringHashMap([]const u8)),
    defaults: std.StringHashMap([]const u8),
    options: Options,

    pub fn init(allocator: std.mem.Allocator, options: Options) Self {
        return .{
            .allocator = allocator,
            .sections = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
            .defaults = std.StringHashMap([]const u8).init(allocator),
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.sections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.sections.deinit();
        self.defaults.deinit();
    }

    /// Read configuration from a file path
    pub fn read(self: *Self, filename: []const u8) !void {
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            if (err == error.FileNotFound) return; // Silent ignore like Python
            return err;
        };
        defer file.close();

        try self.readFile(file);
    }

    /// Read configuration from multiple file paths
    pub fn readMany(self: *Self, filenames: []const []const u8) ![]const []const u8 {
        var read_ok = std.ArrayList([]const u8).init(self.allocator);
        for (filenames) |filename| {
            const file = std.fs.cwd().openFile(filename, .{}) catch continue;
            defer file.close();
            self.readFile(file) catch continue;
            try read_ok.append(filename);
        }
        return read_ok.toOwnedSlice();
    }

    /// Read configuration from an open file
    pub fn readFile(self: *Self, file: std.fs.File) !void {
        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);
        try self.readString(content);
    }

    /// Read configuration from a string
    pub fn readString(self: *Self, content: []const u8) !void {
        var current_section: ?[]const u8 = null;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");

            // Skip empty lines and comments
            if (line.len == 0) continue;
            if (line[0] == '#' or line[0] == ';') continue;

            // Section header
            if (line[0] == '[') {
                if (std.mem.indexOfScalar(u8, line, ']')) |end| {
                    const section_name = line[1..end];
                    current_section = try self.allocator.dupe(u8, section_name);
                    if (!self.sections.contains(current_section.?)) {
                        try self.sections.put(current_section.?, std.StringHashMap([]const u8).init(self.allocator));
                    }
                }
                continue;
            }

            // Key-value pair
            if (current_section) |section| {
                if (std.mem.indexOfAny(u8, line, self.options.delimiters)) |delim_pos| {
                    const key = std.mem.trim(u8, line[0..delim_pos], " \t");
                    const value = std.mem.trim(u8, line[delim_pos + 1 ..], " \t");

                    const key_dup = try self.allocator.dupe(u8, key);
                    const value_dup = try self.allocator.dupe(u8, value);

                    if (self.sections.getPtr(section)) |section_map| {
                        try section_map.put(key_dup, value_dup);
                    }
                } else if (self.options.allow_no_value) {
                    const key = std.mem.trim(u8, line, " \t");
                    const key_dup = try self.allocator.dupe(u8, key);

                    if (self.sections.getPtr(section)) |section_map| {
                        try section_map.put(key_dup, "");
                    }
                }
            }
        }
    }

    /// Read configuration from a dict
    pub fn readDict(self: *Self, dictionary: std.StringHashMap(std.StringHashMap([]const u8))) !void {
        var iter = dictionary.iterator();
        while (iter.next()) |entry| {
            const section = entry.key_ptr.*;
            if (!self.sections.contains(section)) {
                try self.sections.put(section, std.StringHashMap([]const u8).init(self.allocator));
            }

            var val_iter = entry.value_ptr.iterator();
            while (val_iter.next()) |val_entry| {
                if (self.sections.getPtr(section)) |section_map| {
                    try section_map.put(val_entry.key_ptr.*, val_entry.value_ptr.*);
                }
            }
        }
    }

    /// Get a value from a section
    pub fn get(self: *Self, section: []const u8, option: []const u8) ![]const u8 {
        if (self.sections.get(section)) |section_map| {
            if (section_map.get(option)) |value| {
                return value;
            }
        }

        // Check defaults
        if (self.defaults.get(option)) |value| {
            return value;
        }

        return error.NoOption;
    }

    /// Get a value with a fallback
    pub fn getWithFallback(self: *Self, section: []const u8, option: []const u8, fallback: []const u8) []const u8 {
        return self.get(section, option) catch fallback;
    }

    /// Get an integer value
    pub fn getInt(self: *Self, section: []const u8, option: []const u8) !i64 {
        const value = try self.get(section, option);
        return std.fmt.parseInt(i64, value, 10);
    }

    /// Get a float value
    pub fn getFloat(self: *Self, section: []const u8, option: []const u8) !f64 {
        const value = try self.get(section, option);
        return std.fmt.parseFloat(f64, value);
    }

    /// Get a boolean value
    pub fn getBoolean(self: *Self, section: []const u8, option: []const u8) !bool {
        const value = try self.get(section, option);
        const lower = try self.toLower(value);
        defer self.allocator.free(lower);

        if (std.mem.eql(u8, lower, "true") or
            std.mem.eql(u8, lower, "yes") or
            std.mem.eql(u8, lower, "on") or
            std.mem.eql(u8, lower, "1"))
        {
            return true;
        }

        if (std.mem.eql(u8, lower, "false") or
            std.mem.eql(u8, lower, "no") or
            std.mem.eql(u8, lower, "off") or
            std.mem.eql(u8, lower, "0"))
        {
            return false;
        }

        return error.InvalidBoolean;
    }

    fn toLower(self: *Self, s: []const u8) ![]u8 {
        const result = try self.allocator.alloc(u8, s.len);
        for (s, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return result;
    }

    /// Set a value in a section
    pub fn set(self: *Self, section: []const u8, option: []const u8, value: []const u8) !void {
        if (!self.sections.contains(section)) {
            return error.NoSection;
        }

        const key_dup = try self.allocator.dupe(u8, option);
        const value_dup = try self.allocator.dupe(u8, value);

        if (self.sections.getPtr(section)) |section_map| {
            try section_map.put(key_dup, value_dup);
        }
    }

    /// Check if a section exists
    pub fn hasSection(self: *Self, section: []const u8) bool {
        return self.sections.contains(section);
    }

    /// Check if an option exists in a section
    pub fn hasOption(self: *Self, section: []const u8, option: []const u8) bool {
        if (self.sections.get(section)) |section_map| {
            return section_map.contains(option);
        }
        return self.defaults.contains(option);
    }

    /// Add a new section
    pub fn addSection(self: *Self, section: []const u8) !void {
        if (self.sections.contains(section)) {
            return error.DuplicateSection;
        }
        const section_dup = try self.allocator.dupe(u8, section);
        try self.sections.put(section_dup, std.StringHashMap([]const u8).init(self.allocator));
    }

    /// Remove a section
    pub fn removeSection(self: *Self, section: []const u8) bool {
        if (self.sections.fetchRemove(section)) |kv| {
            var map = kv.value;
            map.deinit();
            return true;
        }
        return false;
    }

    /// Remove an option from a section
    pub fn removeOption(self: *Self, section: []const u8, option: []const u8) bool {
        if (self.sections.getPtr(section)) |section_map| {
            return section_map.remove(option);
        }
        return false;
    }

    /// Get all section names
    pub fn getSections(self: *Self) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var iter = self.sections.keyIterator();
        while (iter.next()) |key| {
            try result.append(key.*);
        }
        return result.toOwnedSlice();
    }

    /// Get all options in a section
    pub fn getOptions(self: *Self, section: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);

        // Add defaults first
        var def_iter = self.defaults.keyIterator();
        while (def_iter.next()) |key| {
            try result.append(key.*);
        }

        // Add section-specific options
        if (self.sections.get(section)) |section_map| {
            var sec_iter = section_map.keyIterator();
            while (sec_iter.next()) |key| {
                try result.append(key.*);
            }
        } else {
            return error.NoSection;
        }

        return result.toOwnedSlice();
    }

    /// Get all items in a section
    pub fn items(self: *Self, section: []const u8) ![]struct { key: []const u8, value: []const u8 } {
        var result = std.ArrayList(struct { key: []const u8, value: []const u8 }).init(self.allocator);

        if (self.sections.get(section)) |section_map| {
            var iter = section_map.iterator();
            while (iter.next()) |entry| {
                try result.append(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
            }
        } else {
            return error.NoSection;
        }

        return result.toOwnedSlice();
    }

    /// Write configuration to a file
    pub fn write(self: *Self, file: std.fs.File) !void {
        var writer = file.writer();

        // Write defaults if any
        if (self.defaults.count() > 0) {
            try writer.print("[{s}]\n", .{self.options.default_section});
            var def_iter = self.defaults.iterator();
            while (def_iter.next()) |entry| {
                try writer.print("{s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try writer.writeByte('\n');
        }

        // Write sections
        var sec_iter = self.sections.iterator();
        while (sec_iter.next()) |sec_entry| {
            try writer.print("[{s}]\n", .{sec_entry.key_ptr.*});

            var opt_iter = sec_entry.value_ptr.iterator();
            while (opt_iter.next()) |opt_entry| {
                try writer.print("{s} = {s}\n", .{ opt_entry.key_ptr.*, opt_entry.value_ptr.* });
            }
            try writer.writeByte('\n');
        }
    }

    /// Clear all sections and options
    pub fn clear(self: *Self) void {
        var iter = self.sections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.sections.clearAndFree();
        self.defaults.clearAndFree();
    }
};

/// Raw config parser (no interpolation)
pub const RawConfigParser = ConfigParser;

/// Safe config parser (alias for ConfigParser)
pub const SafeConfigParser = ConfigParser;

// ============================================================================
// Errors
// ============================================================================

pub const Error = error{
    NoSection,
    DuplicateSection,
    DuplicateOption,
    NoOption,
    InterpolationError,
    InterpolationDepthError,
    InterpolationMissingOptionError,
    InterpolationSyntaxError,
    InvalidBoolean,
    ParsingError,
    MissingSectionHeader,
};

// ============================================================================
// Converters
// ============================================================================

/// Default converters for getint, getfloat, getboolean
pub const Converters = struct {
    pub fn int(value: []const u8) !i64 {
        return std.fmt.parseInt(i64, value, 10);
    }

    pub fn float(value: []const u8) !f64 {
        return std.fmt.parseFloat(f64, value);
    }

    pub fn boolean(value: []const u8) !bool {
        const lower = std.ascii.lowerString(@constCast(value), value);
        _ = lower;

        if (std.mem.eql(u8, value, "true") or
            std.mem.eql(u8, value, "yes") or
            std.mem.eql(u8, value, "on") or
            std.mem.eql(u8, value, "1"))
        {
            return true;
        }

        if (std.mem.eql(u8, value, "false") or
            std.mem.eql(u8, value, "no") or
            std.mem.eql(u8, value, "off") or
            std.mem.eql(u8, value, "0"))
        {
            return false;
        }

        return error.InvalidBoolean;
    }
};

// ============================================================================
// Constants
// ============================================================================

pub const DEFAULTSECT = "DEFAULT";
pub const MAX_INTERPOLATION_DEPTH = 10;

// ============================================================================
// Tests
// ============================================================================

test "ConfigParser init" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try std.testing.expect(!parser.hasSection("test"));
}

test "ConfigParser add section" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("test");
    try std.testing.expect(parser.hasSection("test"));
}

test "ConfigParser set and get" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("section1");
    try parser.set("section1", "key1", "value1");

    const value = try parser.get("section1", "key1");
    try std.testing.expectEqualStrings("value1", value);
}

test "ConfigParser read string" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    const content =
        \\[section1]
        \\key1 = value1
        \\key2 = value2
        \\
        \\[section2]
        \\key3 = value3
    ;

    try parser.readString(content);

    try std.testing.expect(parser.hasSection("section1"));
    try std.testing.expect(parser.hasSection("section2"));

    const value1 = try parser.get("section1", "key1");
    try std.testing.expectEqualStrings("value1", value1);
}

test "ConfigParser getInt" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("numbers");
    try parser.set("numbers", "count", "42");

    const count = try parser.getInt("numbers", "count");
    try std.testing.expectEqual(@as(i64, 42), count);
}

test "ConfigParser getBoolean" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("flags");
    try parser.set("flags", "enabled", "true");
    try parser.set("flags", "disabled", "false");

    const enabled = try parser.getBoolean("flags", "enabled");
    const disabled = try parser.getBoolean("flags", "disabled");

    try std.testing.expect(enabled);
    try std.testing.expect(!disabled);
}

test "ConfigParser remove section" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("temp");
    try std.testing.expect(parser.hasSection("temp"));

    const removed = parser.removeSection("temp");
    try std.testing.expect(removed);
    try std.testing.expect(!parser.hasSection("temp"));
}
