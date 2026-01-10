//! test.test_ttk.test_widgets - Tk widgets tests
const std = @import("std");

/// Widget state flags
pub const WidgetState = packed struct {
    active: bool = false,
    disabled: bool = false,
    focus: bool = false,
    pressed: bool = false,
    selected: bool = false,
    background: bool = false,
    readonly: bool = false,
    invalid: bool = false,

    pub fn none() WidgetState {
        return .{};
    }

    pub fn isEnabled(self: WidgetState) bool {
        return !self.disabled;
    }
};

/// Widget options common to all widgets
pub const WidgetOptions = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    padding: ?[4]u32 = null,
    cursor: ?[]const u8 = null,
    style: ?[]const u8 = null,
    takefocus: bool = true,

    pub fn init() WidgetOptions {
        return .{};
    }

    pub fn withSize(self: WidgetOptions, width: u32, height: u32) WidgetOptions {
        var copy = self;
        copy.width = width;
        copy.height = height;
        return copy;
    }
};

/// Base widget class
pub const Widget = struct {
    id: u32,
    parent_id: ?u32,
    widget_class: []const u8,
    state: WidgetState = .{},
    options: WidgetOptions = .{},

    pub fn init(id: u32, parent_id: ?u32, class: []const u8) Widget {
        return .{
            .id = id,
            .parent_id = parent_id,
            .widget_class = class,
        };
    }

    pub fn configure(self: *Widget, options: WidgetOptions) void {
        self.options = options;
    }

    pub fn setState(self: *Widget, state: WidgetState) void {
        self.state = state;
    }

    pub fn isVisible(self: *const Widget) bool {
        _ = self;
        return true;
    }
};

/// Button widget
pub const Button = struct {
    base: Widget,
    text: []const u8 = "",
    command: ?*const fn () void = null,
    image: ?[]const u8 = null,

    pub fn init(id: u32, parent_id: ?u32) Button {
        return .{
            .base = Widget.init(id, parent_id, "TButton"),
        };
    }

    pub fn setText(self: *Button, text: []const u8) void {
        self.text = text;
    }

    pub fn invoke(self: *Button) void {
        if (self.command) |cmd| {
            cmd();
        }
    }
};

/// Label widget
pub const Label = struct {
    base: Widget,
    text: []const u8 = "",
    image: ?[]const u8 = null,
    compound: Compound = .none,

    pub const Compound = enum { none, text, image, center, top, bottom, left, right };

    pub fn init(id: u32, parent_id: ?u32) Label {
        return .{
            .base = Widget.init(id, parent_id, "TLabel"),
        };
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.text = text;
    }
};

/// Entry widget
pub const Entry = struct {
    base: Widget,
    text: std.ArrayList(u8),
    cursor_pos: usize = 0,
    selection_start: ?usize = null,
    selection_end: ?usize = null,
    show: ?u8 = null,

    pub fn init(allocator: std.mem.Allocator, id: u32, parent_id: ?u32) Entry {
        return .{
            .base = Widget.init(id, parent_id, "TEntry"),
            .text = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Entry) void {
        self.text.deinit();
    }

    pub fn get(self: *const Entry) []const u8 {
        return self.text.items;
    }

    pub fn insert(self: *Entry, index: usize, text: []const u8) !void {
        const pos = @min(index, self.text.items.len);
        try self.text.insertSlice(pos, text);
        self.cursor_pos = pos + text.len;
    }

    pub fn delete(self: *Entry, start: usize, end: usize) void {
        const s = @min(start, self.text.items.len);
        const e = @min(end, self.text.items.len);
        if (s < e) {
            self.text.replaceRange(s, e - s, &[_]u8{}) catch {};
        }
    }
};

/// Checkbutton widget
pub const Checkbutton = struct {
    base: Widget,
    text: []const u8 = "",
    checked: bool = false,
    command: ?*const fn () void = null,

    pub fn init(id: u32, parent_id: ?u32) Checkbutton {
        return .{
            .base = Widget.init(id, parent_id, "TCheckbutton"),
        };
    }

    pub fn toggle(self: *Checkbutton) void {
        self.checked = !self.checked;
        if (self.command) |cmd| cmd();
    }
};

test "WidgetState" {
    const state = WidgetState.none();
    try std.testing.expect(state.isEnabled());

    const disabled = WidgetState{ .disabled = true };
    try std.testing.expect(!disabled.isEnabled());
}

test "Widget creation" {
    var widget = Widget.init(1, null, "TFrame");
    try std.testing.expectEqual(@as(u32, 1), widget.id);
    try std.testing.expectEqualStrings("TFrame", widget.widget_class);

    widget.setState(.{ .focus = true });
    try std.testing.expect(widget.state.focus);
}

test "Button widget" {
    var button = Button.init(1, null);
    button.setText("Click Me");
    try std.testing.expectEqualStrings("Click Me", button.text);
}

test "Label widget" {
    var label = Label.init(1, null);
    label.setText("Hello");
    try std.testing.expectEqualStrings("Hello", label.text);
}

test "Entry widget" {
    const allocator = std.testing.allocator;
    var entry = Entry.init(allocator, 1, null);
    defer entry.deinit();

    try entry.insert(0, "Hello");
    try std.testing.expectEqualStrings("Hello", entry.get());
    try std.testing.expectEqual(@as(usize, 5), entry.cursor_pos);
}

test "Checkbutton toggle" {
    var cb = Checkbutton.init(1, null);
    try std.testing.expect(!cb.checked);

    cb.toggle();
    try std.testing.expect(cb.checked);

    cb.toggle();
    try std.testing.expect(!cb.checked);
}
