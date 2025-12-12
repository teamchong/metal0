//! Container and drawing widgets
//!
//! Provides widgets for layout and graphics:
//! - Frame: Container widget for organizing other widgets
//! - Text: Multi-line text editor widget
//! - Canvas: Drawing surface for shapes and graphics

const std = @import("std");
const widget_mod = @import("widget.zig");
const Widget = widget_mod.Widget;

/// Frame widget (container)
pub const Frame = struct {
    widget: Widget,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Frame {
        var f = Frame{
            .widget = Widget.init(allocator, "frame"),
        };
        f.widget.parent = parent;
        return f;
    }
};

/// Text widget (multi-line text)
pub const Text = struct {
    widget: Widget,
    content: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Text {
        var t = Text{
            .widget = Widget.init(allocator, "text"),
            .content = .{},
        };
        t.widget.parent = parent;
        return t;
    }

    pub fn deinit(self: *Text, allocator: std.mem.Allocator) void {
        self.content.deinit(allocator);
        self.widget.deinit();
    }

    pub fn get(self: *const Text, start: []const u8, end_: []const u8) []const u8 {
        _ = start;
        _ = end_;
        return self.content.items;
    }

    pub fn insert(self: *Text, allocator: std.mem.Allocator, index: []const u8, text: []const u8) !void {
        _ = index;
        try self.content.appendSlice(allocator, text);
    }
};

/// Canvas widget
pub const Canvas = struct {
    widget: Widget,
    width: u32 = 300,
    height: u32 = 200,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Canvas {
        var c = Canvas{
            .widget = Widget.init(allocator, "canvas"),
        };
        c.widget.parent = parent;
        return c;
    }

    pub fn create_line(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32) u32 {
        _ = self;
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        return 1;
    }

    pub fn create_rectangle(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32) u32 {
        _ = self;
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        return 1;
    }

    pub fn create_oval(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32) u32 {
        _ = self;
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        return 1;
    }

    pub fn create_text(self: *Canvas, x: i32, y: i32, text: []const u8) u32 {
        _ = self;
        _ = x;
        _ = y;
        _ = text;
        return 1;
    }

    pub fn delete(self: *Canvas, item: u32) void {
        _ = self;
        _ = item;
    }
};
