//! CPython source: Lib/configparser.py
//!
//! File I/O operations for reading and writing configuration files.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

/// Read configuration from a file path
pub fn read(parser: anytype, filename: []const u8) !void {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        if (err == error.FileNotFound) return; // Silent ignore like Python
        return err;
    };
    defer file.close();

    try readFile(parser, file);
}

/// Read configuration from multiple file paths
pub fn readMany(parser: anytype, filenames: []const []const u8) ![]const []const u8 {
    var read_ok: std.ArrayList([]const u8) = .{};
    for (filenames) |filename| {
        const file = std.fs.cwd().openFile(filename, .{}) catch continue;
        defer file.close();
        readFile(parser, file) catch continue;
        try read_ok.append(parser.allocator, filename);
    }
    return read_ok.toOwnedSlice(parser.allocator);
}

/// Read configuration from an open file
pub fn readFile(parser: anytype, file: std.fs.File) !void {
    const content = try file.readToEndAlloc(parser.allocator, 10 * 1024 * 1024);
    defer parser.allocator.free(content);
    try readString(parser, content);
}

/// Read configuration from a string
pub fn readString(parser: anytype, content: []const u8) !void {
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
                current_section = try parser.allocator.dupe(u8, section_name);
                if (!parser.sections.contains(current_section.?)) {
                    try parser.sections.put(current_section.?, hashmap_helper.StringHashMap([]const u8).init(parser.allocator));
                }
            }
            continue;
        }

        // Key-value pair
        if (current_section) |section| {
            if (std.mem.indexOfAny(u8, line, parser.options.delimiters)) |delim_pos| {
                const key = std.mem.trim(u8, line[0..delim_pos], " \t");
                const value = std.mem.trim(u8, line[delim_pos + 1 ..], " \t");

                const key_dup = try parser.allocator.dupe(u8, key);
                const value_dup = try parser.allocator.dupe(u8, value);

                if (parser.sections.getPtr(section)) |section_map| {
                    try section_map.put(key_dup, value_dup);
                }
            } else if (parser.options.allow_no_value) {
                const key = std.mem.trim(u8, line, " \t");
                const key_dup = try parser.allocator.dupe(u8, key);

                if (parser.sections.getPtr(section)) |section_map| {
                    try section_map.put(key_dup, "");
                }
            }
        }
    }
}

/// Read configuration from a dict
pub fn readDict(parser: anytype, dictionary: hashmap_helper.StringHashMap(hashmap_helper.StringHashMap([]const u8))) !void {
    var iter = dictionary.iterator();
    while (iter.next()) |entry| {
        const section = entry.key_ptr.*;
        if (!parser.sections.contains(section)) {
            try parser.sections.put(section, hashmap_helper.StringHashMap([]const u8).init(parser.allocator));
        }

        var val_iter = entry.value_ptr.iterator();
        while (val_iter.next()) |val_entry| {
            if (parser.sections.getPtr(section)) |section_map| {
                try section_map.put(val_entry.key_ptr.*, val_entry.value_ptr.*);
            }
        }
    }
}

/// Write configuration to a file
pub fn write(parser: anytype, file: std.fs.File) !void {
    var writer = file.writer();

    // Write defaults if any
    if (parser.defaults.count() > 0) {
        try writer.print("[{s}]\n", .{parser.options.default_section});
        var def_iter = parser.defaults.iterator();
        while (def_iter.next()) |entry| {
            try writer.print("{s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeByte('\n');
    }

    // Write sections
    var sec_iter = parser.sections.iterator();
    while (sec_iter.next()) |sec_entry| {
        try writer.print("[{s}]\n", .{sec_entry.key_ptr.*});

        var opt_iter = sec_entry.value_ptr.iterator();
        while (opt_iter.next()) |opt_entry| {
            try writer.print("{s} = {s}\n", .{ opt_entry.key_ptr.*, opt_entry.value_ptr.* });
        }
        try writer.writeByte('\n');
    }
}
