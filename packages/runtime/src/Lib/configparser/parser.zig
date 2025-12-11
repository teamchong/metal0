//! CPython source: Lib/configparser.py
//!
//! Core ConfigParser implementation.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const io = @import("io.zig");
const query = @import("query.zig");
const sections = @import("sections.zig");

/// Configuration file parser
pub const ConfigParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    sections: hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8)),
    defaults: hashmap_helper.StringHashMap([]const u8),
    options: types.Options,

    pub fn init(allocator: std.mem.Allocator, options: types.Options) Self {
        return .{
            .allocator = allocator,
            .sections = hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8)).init(allocator),
            .defaults = hashmap_helper.StringHashMap([]const u8).init(allocator),
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

    // ============================================================================
    // I/O Operations
    // ============================================================================

    /// Read configuration from a file path
    pub fn read(self: *Self, filename: []const u8) !void {
        return io.read(self, filename);
    }

    /// Read configuration from multiple file paths
    pub fn readMany(self: *Self, filenames: []const []const u8) ![]const []const u8 {
        return io.readMany(self, filenames);
    }

    /// Read configuration from an open file
    pub fn readFile(self: *Self, file: std.fs.File) !void {
        return io.readFile(self, file);
    }

    /// Read configuration from a string
    pub fn readString(self: *Self, content: []const u8) !void {
        return io.readString(self, content);
    }

    /// Read configuration from a dict
    pub fn readDict(self: *Self, dictionary: hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8))) !void {
        return io.readDict(self, dictionary);
    }

    /// Write configuration to a file
    pub fn write(self: *Self, file: std.fs.File) !void {
        return io.write(self, file);
    }

    // ============================================================================
    // Query Operations
    // ============================================================================

    /// Get a value from a section
    pub fn get(self: *Self, section: []const u8, option: []const u8) ![]const u8 {
        return query.get(self, section, option);
    }

    /// Get a value with a fallback
    pub fn getWithFallback(self: *Self, section: []const u8, option: []const u8, fallback: []const u8) []const u8 {
        return query.getWithFallback(self, section, option, fallback);
    }

    /// Get an integer value
    pub fn getInt(self: *Self, section: []const u8, option: []const u8) !i64 {
        return query.getInt(self, section, option);
    }

    /// Get a float value
    pub fn getFloat(self: *Self, section: []const u8, option: []const u8) !f64 {
        return query.getFloat(self, section, option);
    }

    /// Get a boolean value
    pub fn getBoolean(self: *Self, section: []const u8, option: []const u8) !bool {
        return query.getBoolean(self, section, option);
    }

    /// Set a value in a section
    pub fn set(self: *Self, section: []const u8, option: []const u8, value: []const u8) !void {
        return query.set(self, section, option, value);
    }

    /// Check if an option exists in a section
    pub fn hasOption(self: *Self, section: []const u8, option: []const u8) bool {
        return query.hasOption(self, section, option);
    }

    /// Get all options in a section
    pub fn getOptions(self: *Self, section: []const u8) ![][]const u8 {
        return query.getOptions(self, section);
    }

    /// Get all items in a section
    pub fn items(self: *Self, section: []const u8) ![]struct { key: []const u8, value: []const u8 } {
        return query.items(self, section);
    }

    /// Remove an option from a section
    pub fn removeOption(self: *Self, section: []const u8, option: []const u8) bool {
        return query.removeOption(self, section, option);
    }

    // ============================================================================
    // Section Operations
    // ============================================================================

    /// Check if a section exists
    pub fn hasSection(self: *Self, section: []const u8) bool {
        return sections.hasSection(self, section);
    }

    /// Add a new section
    pub fn addSection(self: *Self, section: []const u8) !void {
        return sections.addSection(self, section);
    }

    /// Remove a section
    pub fn removeSection(self: *Self, section: []const u8) bool {
        return sections.removeSection(self, section);
    }

    /// Get all section names
    pub fn getSections(self: *Self) ![][]const u8 {
        return sections.getSections(self);
    }

    /// Clear all sections and options
    pub fn clear(self: *Self) void {
        sections.clear(self);
    }
};

/// Raw config parser (no interpolation)
pub const RawConfigParser = ConfigParser;

/// Safe config parser (alias for ConfigParser)
pub const SafeConfigParser = ConfigParser;
