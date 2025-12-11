//! HTMLParser - Event-driven HTML/XHTML parser
//!
//! Provides a basic HTML parser with callback-based event handling.

const std = @import("std");
const utils = @import("utils.zig");

// ============================================================================
// HTMLParser - Basic HTML/XHTML parser
// ============================================================================

/// Event-driven HTML parser
pub const HTMLParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    strict: bool,
    convert_charrefs: bool,

    // Handler callbacks (set by subclass/user)
    handle_starttag: ?*const fn (tag: []const u8, attrs: []const Attribute) void = null,
    handle_endtag: ?*const fn (tag: []const u8) void = null,
    handle_data: ?*const fn (data: []const u8) void = null,
    handle_comment: ?*const fn (data: []const u8) void = null,
    handle_decl: ?*const fn (decl: []const u8) void = null,
    handle_pi: ?*const fn (data: []const u8) void = null,

    pub const Attribute = struct {
        name: []const u8,
        value: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator, convert_charrefs: bool) Self {
        return .{
            .allocator = allocator,
            .strict = false,
            .convert_charrefs = convert_charrefs,
        };
    }

    /// Feed data to the parser
    pub fn feed(self: *Self, data: []const u8) !void {
        var i: usize = 0;

        while (i < data.len) {
            if (data[i] == '<') {
                // Start of tag
                if (i + 1 < data.len) {
                    if (data[i + 1] == '/') {
                        // End tag
                        const tag_end = std.mem.indexOfScalarPos(u8, data, i + 2, '>') orelse break;
                        const tag_name = std.mem.trim(u8, data[i + 2 .. tag_end], " \t\n\r");
                        if (self.handle_endtag) |handler| {
                            handler(tag_name);
                        }
                        i = tag_end + 1;
                        continue;
                    } else if (data[i + 1] == '!') {
                        // Comment or declaration
                        if (i + 4 < data.len and std.mem.eql(u8, data[i + 2 .. i + 4], "--")) {
                            // Comment
                            if (std.mem.indexOf(u8, data[i + 4 ..], "-->")) |comment_end| {
                                const comment = data[i + 4 .. i + 4 + comment_end];
                                if (self.handle_comment) |handler| {
                                    handler(comment);
                                }
                                i = i + 4 + comment_end + 3;
                                continue;
                            }
                        } else {
                            // Declaration
                            const decl_end = std.mem.indexOfScalarPos(u8, data, i + 2, '>') orelse break;
                            const decl = data[i + 2 .. decl_end];
                            if (self.handle_decl) |handler| {
                                handler(decl);
                            }
                            i = decl_end + 1;
                            continue;
                        }
                    } else if (data[i + 1] == '?') {
                        // Processing instruction
                        if (std.mem.indexOf(u8, data[i + 2 ..], "?>")) |pi_end| {
                            const pi = data[i + 2 .. i + 2 + pi_end];
                            if (self.handle_pi) |handler| {
                                handler(pi);
                            }
                            i = i + 2 + pi_end + 2;
                            continue;
                        }
                    } else {
                        // Start tag
                        const tag_end = std.mem.indexOfScalarPos(u8, data, i + 1, '>') orelse break;
                        const tag_content = data[i + 1 .. tag_end];

                        // Parse tag name and attributes
                        var parts = std.mem.tokenizeAny(u8, tag_content, " \t\n\r");
                        const tag_name = parts.next() orelse {
                            i = tag_end + 1;
                            continue;
                        };

                        // Check for self-closing
                        const is_self_closing = tag_content.len > 0 and tag_content[tag_content.len - 1] == '/';
                        const clean_tag = if (is_self_closing and tag_name.len > 0 and tag_name[tag_name.len - 1] == '/')
                            tag_name[0 .. tag_name.len - 1]
                        else
                            tag_name;

                        // Parse attributes from remaining tag content
                        var attr_list: [32]Attribute = undefined;
                        var attr_count: usize = 0;

                        // Skip tag name to get attributes portion
                        var remaining = tag_content[tag_name.len..];
                        while (remaining.len > 0 and attr_count < 32) {
                            // Skip whitespace
                            remaining = std.mem.trimLeft(u8, remaining, " \t\n\r");
                            if (remaining.len == 0 or remaining[0] == '/') break;

                            // Find attribute name
                            var name_end: usize = 0;
                            while (name_end < remaining.len and
                                remaining[name_end] != '=' and
                                remaining[name_end] != ' ' and
                                remaining[name_end] != '/') : (name_end += 1)
                            {}

                            if (name_end == 0) break;

                            const attr_name = remaining[0..name_end];
                            remaining = remaining[name_end..];

                            // Check for value
                            var attr_value: ?[]const u8 = null;
                            remaining = std.mem.trimLeft(u8, remaining, " \t");
                            if (remaining.len > 0 and remaining[0] == '=') {
                                remaining = remaining[1..];
                                remaining = std.mem.trimLeft(u8, remaining, " \t");

                                if (remaining.len > 0) {
                                    const quote = remaining[0];
                                    if (quote == '"' or quote == '\'') {
                                        remaining = remaining[1..];
                                        if (std.mem.indexOfScalar(u8, remaining, quote)) |end| {
                                            attr_value = remaining[0..end];
                                            remaining = remaining[end + 1 ..];
                                        }
                                    } else {
                                        // Unquoted value - ends at whitespace
                                        var val_end: usize = 0;
                                        while (val_end < remaining.len and remaining[val_end] != ' ' and remaining[val_end] != '/') : (val_end += 1) {}
                                        attr_value = remaining[0..val_end];
                                        remaining = remaining[val_end..];
                                    }
                                }
                            }

                            attr_list[attr_count] = Attribute{
                                .name = attr_name,
                                .value = attr_value,
                            };
                            attr_count += 1;
                        }

                        const attrs = attr_list[0..attr_count];

                        if (self.handle_starttag) |handler| {
                            handler(clean_tag, attrs);
                        }

                        if (is_self_closing) {
                            if (self.handle_endtag) |handler| {
                                handler(clean_tag);
                            }
                        }

                        i = tag_end + 1;
                        continue;
                    }
                }
            }

            // Regular text content
            const next_tag = std.mem.indexOfScalarPos(u8, data, i, '<') orelse data.len;
            if (next_tag > i) {
                const text = data[i..next_tag];
                if (self.convert_charrefs) {
                    // Unescape HTML entities in text content
                    if (std.mem.indexOf(u8, text, "&") != null) {
                        const unescaped = utils.unescape(self.allocator, text) catch text;
                        if (self.handle_data) |handler| {
                            handler(unescaped);
                        }
                        if (unescaped.ptr != text.ptr) {
                            self.allocator.free(unescaped);
                        }
                    } else {
                        if (self.handle_data) |handler| {
                            handler(text);
                        }
                    }
                } else {
                    if (self.handle_data) |handler| {
                        handler(text);
                    }
                }
            }
            i = next_tag;
        }
    }

    /// Reset the parser
    pub fn reset(self: *Self) void {
        _ = self;
        // Reset internal state
    }

    /// Close the parser and process any remaining data
    pub fn close(self: *Self) void {
        _ = self;
        // Process any remaining buffered data
    }

    /// Get current line number
    pub fn getPos(self: *Self) struct { lineno: usize, offset: usize } {
        _ = self;
        return .{ .lineno = 1, .offset = 0 };
    }
};
