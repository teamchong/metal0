//! Basic Tkinter widgets
//!
//! Provides simple user interface widgets:
//! - Label: Text display
//! - Button: Clickable button with command callback
//! - Entry: Single-line text input

const std = @import("std");
const widget_mod = @import("widget.zig");
const Widget = widget_mod.Widget;

/// Label widget
pub const Label = struct {
    widget: Widget,
    text: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Label {
        var l = Label{
            .widget = Widget.init(allocator, "label"),
        };
        l.widget.parent = parent;
        return l;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.text = text;
    }
};

/// Button widget
pub const Button = struct {
    widget: Widget,
    text: []const u8 = "",
    command: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Button {
        var b = Button{
            .widget = Widget.init(allocator, "button"),
        };
        b.widget.parent = parent;
        return b;
    }

    pub fn setText(self: *Button, text: []const u8) void {
        self.text = text;
    }

    pub fn setCommand(self: *Button, cmd: *const fn () void) void {
        self.command = cmd;
    }

    pub fn invoke(self: *Button) void {
        if (self.command) |cmd| {
            cmd();
        }
    }
};

/// Entry widget (single-line text input)
pub const Entry = struct {
    widget: Widget,
    text: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Entry {
        var e = Entry{
            .widget = Widget.init(allocator, "entry"),
            .text = std.ArrayList(u8).init(allocator),
        };
        e.widget.parent = parent;
        return e;
    }

    pub fn deinit(self: *Entry) void {
        self.text.deinit();
        self.widget.deinit();
    }

    pub fn get(self: *const Entry) []const u8 {
        return self.text.items;
    }

    pub fn insert(self: *Entry, index: usize, text: []const u8) !void {
        const pos = @min(index, self.text.items.len);
        try self.text.insertSlice(pos, text);
    }

    pub fn delete(self: *Entry, first: usize, last: usize) void {
        const start = @min(first, self.text.items.len);
        const end = @min(last, self.text.items.len);
        if (start < end) {
            self.text.replaceRange(start, end - start, &.{}) catch {};
        }
    }
};
