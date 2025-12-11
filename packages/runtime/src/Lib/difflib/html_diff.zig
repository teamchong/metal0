//! HtmlDiff - generate side-by-side HTML diffs
//!
//! Creates HTML tables showing differences between sequences

const std = @import("std");
const sequence_matcher = @import("sequence_matcher.zig");
const SequenceMatcher = sequence_matcher.SequenceMatcher;

// ============================================================================
// HtmlDiff
// ============================================================================

/// Generate side-by-side HTML diff
pub const HtmlDiff = struct {
    const Self = @This();

    tabsize: usize,
    wrapcolumn: ?usize,
    linejunk: ?*const fn ([]const u8) bool,
    charjunk: ?*const fn (u8) bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .tabsize = 8,
            .wrapcolumn = null,
            .linejunk = null,
            .charjunk = null,
            .allocator = allocator,
        };
    }

    pub fn makeFile(self: *Self, fromlines: []const []const u8, tolines: []const []const u8, fromdesc: []const u8, todesc: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice(
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\<style>
            \\.diff_header { background-color: #e0e0e0; }
            \\.diff_next { background-color: #c0c0c0; }
            \\.diff_add { background-color: #aaffaa; }
            \\.diff_chg { background-color: #ffff77; }
            \\.diff_sub { background-color: #ffaaaa; }
            \\</style>
            \\</head>
            \\<body>
            \\
        );

        const table = try self.makeTable(fromlines, tolines, fromdesc, todesc);
        defer self.allocator.free(table);
        try result.appendSlice(table);

        try result.appendSlice(
            \\</body>
            \\</html>
        );

        return result.toOwnedSlice();
    }

    pub fn makeTable(self: *Self, fromlines: []const []const u8, tolines: []const []const u8, fromdesc: []const u8, todesc: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("<table>\n<tr><th>");
        try result.appendSlice(fromdesc);
        try result.appendSlice("</th><th>");
        try result.appendSlice(todesc);
        try result.appendSlice("</th></tr>\n");

        var sm = SequenceMatcher([]const u8).init(self.allocator, fromlines, tolines);
        defer sm.deinit();

        const opcodes = try sm.getOpcodes();
        for (opcodes) |op| {
            const maxlines = @max(op.i2 - op.i1, op.j2 - op.j1);
            var i: usize = 0;
            while (i < maxlines) : (i += 1) {
                try result.appendSlice("<tr>");

                // From column
                if (op.i1 + i < op.i2) {
                    const class = switch (op.tag) {
                        .replace => "diff_chg",
                        .delete => "diff_sub",
                        else => "",
                    };
                    try result.appendSlice("<td class=\"");
                    try result.appendSlice(class);
                    try result.appendSlice("\">");
                    try result.appendSlice(fromlines[op.i1 + i]);
                    try result.appendSlice("</td>");
                } else {
                    try result.appendSlice("<td></td>");
                }

                // To column
                if (op.j1 + i < op.j2) {
                    const class = switch (op.tag) {
                        .replace => "diff_chg",
                        .insert => "diff_add",
                        else => "",
                    };
                    try result.appendSlice("<td class=\"");
                    try result.appendSlice(class);
                    try result.appendSlice("\">");
                    try result.appendSlice(tolines[op.j1 + i]);
                    try result.appendSlice("</td>");
                } else {
                    try result.appendSlice("<td></td>");
                }

                try result.appendSlice("</tr>\n");
            }
        }

        try result.appendSlice("</table>\n");

        return result.toOwnedSlice();
    }
};
