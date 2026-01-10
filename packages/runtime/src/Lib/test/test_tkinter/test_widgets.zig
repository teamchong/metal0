//! test.test_tkinter.test_widgets - Tk widgets tests
//! Tests for tkinter widget creation, configuration, and properties

const std = @import("std");
const testing = std.testing;

/// Widget state flags
pub const WidgetState = packed struct {
    active: bool = false,
    disabled: bool = false,
    focus: bool = false,
    pressed: bool = false,
    selected: bool = false,
    background: bool = false,
    readonly: bool = false,
    alternate: bool = false,
    invalid: bool = false,
    hover: bool = false,
    _padding: u6 = 0,

    pub fn isNormal(self: WidgetState) bool {
        return !self.disabled and !self.readonly;
    }

    pub fn toTclString(self: WidgetState) []const u8 {
        if (self.disabled) return "disabled";
        if (self.active) return "active";
        if (self.pressed) return "pressed";
        return "normal";
    }
};

/// Widget configuration options
pub const WidgetConfig = struct {
    text: ?[]const u8 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    state: WidgetState = .{},
    background: ?[]const u8 = null,
    foreground: ?[]const u8 = null,
    font: ?[]const u8 = null,
    relief: Relief = .flat,
    borderwidth: u32 = 0,
    padding: Padding = .{},
    cursor: ?[]const u8 = null,
    takefocus: bool = true,

    pub fn merge(self: WidgetConfig, other: WidgetConfig) WidgetConfig {
        var result = self;
        if (other.text) |t| result.text = t;
        if (other.width) |w| result.width = w;
        if (other.height) |h| result.height = h;
        if (other.background) |bg| result.background = bg;
        if (other.foreground) |fg| result.foreground = fg;
        if (other.font) |f| result.font = f;
        return result;
    }
};

/// Relief styles for widgets
pub const Relief = enum {
    flat,
    raised,
    sunken,
    ridge,
    solid,
    groove,

    pub fn toTclString(self: Relief) []const u8 {
        return switch (self) {
            .flat => "flat",
            .raised => "raised",
            .sunken => "sunken",
            .ridge => "ridge",
            .solid => "solid",
            .groove => "groove",
        };
    }
};

/// Padding specification
pub const Padding = struct {
    left: u32 = 0,
    top: u32 = 0,
    right: u32 = 0,
    bottom: u32 = 0,

    pub fn uniform(value: u32) Padding {
        return .{ .left = value, .top = value, .right = value, .bottom = value };
    }

    pub fn symmetric(horizontal: u32, vertical: u32) Padding {
        return .{ .left = horizontal, .right = horizontal, .top = vertical, .bottom = vertical };
    }

    pub fn horizontal(self: Padding) u32 {
        return self.left + self.right;
    }

    pub fn vertical(self: Padding) u32 {
        return self.top + self.bottom;
    }
};

/// Base widget structure
pub const Widget = struct {
    id: []const u8,
    parent: ?*Widget = null,
    children: std.ArrayList(*Widget),
    config: WidgetConfig = .{},
    allocator: std.mem.Allocator,
    widget_class: WidgetClass = .frame,
    destroyed: bool = false,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Widget {
        return .{
            .id = id,
            .children = std.ArrayList(*Widget).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Widget) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn configure(self: *Widget, config: WidgetConfig) void {
        self.config = self.config.merge(config);
    }

    pub fn cget(self: *const Widget, option: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, option, "-text")) return self.config.text;
        if (std.mem.eql(u8, option, "-background")) return self.config.background;
        if (std.mem.eql(u8, option, "-foreground")) return self.config.foreground;
        if (std.mem.eql(u8, option, "-font")) return self.config.font;
        return null;
    }

    pub fn winfo_class(self: *const Widget) []const u8 {
        return self.widget_class.toClassName();
    }

    pub fn winfo_children(self: *const Widget) []*Widget {
        return self.children.items;
    }

    pub fn winfo_parent(self: *const Widget) ?*Widget {
        return self.parent;
    }

    pub fn destroy(self: *Widget) void {
        self.destroyed = true;
        for (self.children.items) |child| {
            child.destroy();
        }
    }

    pub fn addChild(self: *Widget, child: *Widget) !void {
        child.parent = self;
        try self.children.append(child);
    }
};

/// Widget class types
pub const WidgetClass = enum {
    frame,
    label,
    button,
    entry,
    text,
    canvas,
    listbox,
    scrollbar,
    scale,
    spinbox,
    checkbutton,
    radiobutton,
    menubutton,
    menu,
    toplevel,
    labelframe,
    panedwindow,
    notebook,
    treeview,
    progressbar,
    combobox,
    separator,
    sizegrip,

    pub fn toClassName(self: WidgetClass) []const u8 {
        return switch (self) {
            .frame => "Frame",
            .label => "Label",
            .button => "Button",
            .entry => "Entry",
            .text => "Text",
            .canvas => "Canvas",
            .listbox => "Listbox",
            .scrollbar => "Scrollbar",
            .scale => "Scale",
            .spinbox => "Spinbox",
            .checkbutton => "Checkbutton",
            .radiobutton => "Radiobutton",
            .menubutton => "Menubutton",
            .menu => "Menu",
            .toplevel => "Toplevel",
            .labelframe => "Labelframe",
            .panedwindow => "Panedwindow",
            .notebook => "TNotebook",
            .treeview => "Treeview",
            .progressbar => "TProgressbar",
            .combobox => "TCombobox",
            .separator => "TSeparator",
            .sizegrip => "TSizegrip",
        };
    }
};

/// Button widget with command support
pub const Button = struct {
    widget: Widget,
    command: ?*const fn () void = null,
    default_state: DefaultState = .normal,

    pub const DefaultState = enum { normal, active, disabled };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Button {
        var w = Widget.init(allocator, id);
        w.widget_class = .button;
        return .{ .widget = w };
    }

    pub fn setText(self: *Button, text: []const u8) void {
        self.widget.config.text = text;
    }

    pub fn setCommand(self: *Button, cmd: *const fn () void) void {
        self.command = cmd;
    }

    pub fn invoke(self: *Button) void {
        if (self.command) |cmd| {
            cmd();
        }
    }

    pub fn flash(self: *Button) void {
        _ = self;
        // Visual flash effect
    }
};

/// Label widget for text display
pub const Label = struct {
    widget: Widget,
    image: ?[]const u8 = null,
    compound: Compound = .none,
    anchor: Anchor = .center,
    justify: Justify = .left,
    wraplength: u32 = 0,

    pub const Compound = enum { none, bottom, top, left, right, center, image, text };
    pub const Anchor = enum { n, ne, e, se, s, sw, w, nw, center };
    pub const Justify = enum { left, right, center };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Label {
        var w = Widget.init(allocator, id);
        w.widget_class = .label;
        return .{ .widget = w };
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.widget.config.text = text;
    }

    pub fn setImage(self: *Label, image: []const u8) void {
        self.image = image;
    }
};

/// Entry widget for single-line text input
pub const Entry = struct {
    widget: Widget,
    content: std.ArrayList(u8),
    cursor_position: usize = 0,
    selection_start: ?usize = null,
    selection_end: ?usize = null,
    show_char: ?u8 = null,
    validate: ValidateMode = .none,
    validate_command: ?*const fn ([]const u8) bool = null,

    pub const ValidateMode = enum { none, focus, focusin, focusout, key, all };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Entry {
        var w = Widget.init(allocator, id);
        w.widget_class = .entry;
        return .{
            .widget = w,
            .content = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Entry) void {
        self.content.deinit();
        self.widget.deinit();
    }

    pub fn get(self: *const Entry) []const u8 {
        return self.content.items;
    }

    pub fn insert(self: *Entry, index: usize, text: []const u8) !void {
        const pos = @min(index, self.content.items.len);
        try self.content.insertSlice(pos, text);
        self.cursor_position = pos + text.len;
    }

    pub fn delete(self: *Entry, start: usize, end: usize) void {
        const s = @min(start, self.content.items.len);
        const e = @min(end, self.content.items.len);
        if (s < e) {
            const count = e - s;
            var i: usize = 0;
            while (i < count and s < self.content.items.len) : (i += 1) {
                _ = self.content.orderedRemove(s);
            }
        }
    }

    pub fn selectRange(self: *Entry, start: usize, end: usize) void {
        self.selection_start = start;
        self.selection_end = end;
    }

    pub fn selectAll(self: *Entry) void {
        self.selection_start = 0;
        self.selection_end = self.content.items.len;
    }

    pub fn getSelection(self: *const Entry) ?[]const u8 {
        if (self.selection_start) |start| {
            if (self.selection_end) |end| {
                if (start < end and end <= self.content.items.len) {
                    return self.content.items[start..end];
                }
            }
        }
        return null;
    }

    pub fn icursor(self: *Entry, index: usize) void {
        self.cursor_position = @min(index, self.content.items.len);
    }
};

/// Checkbutton widget
pub const Checkbutton = struct {
    widget: Widget,
    variable: bool = false,
    onvalue: []const u8 = "1",
    offvalue: []const u8 = "0",
    command: ?*const fn () void = null,
    indicatoron: bool = true,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Checkbutton {
        var w = Widget.init(allocator, id);
        w.widget_class = .checkbutton;
        return .{ .widget = w };
    }

    pub fn toggle(self: *Checkbutton) void {
        self.variable = !self.variable;
        if (self.command) |cmd| cmd();
    }

    pub fn select(self: *Checkbutton) void {
        self.variable = true;
    }

    pub fn deselect(self: *Checkbutton) void {
        self.variable = false;
    }

    pub fn isSelected(self: *const Checkbutton) bool {
        return self.variable;
    }
};

/// Radiobutton widget
pub const Radiobutton = struct {
    widget: Widget,
    value: []const u8 = "",
    variable_group: ?*[]const u8 = null,
    command: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Radiobutton {
        var w = Widget.init(allocator, id);
        w.widget_class = .radiobutton;
        return .{ .widget = w };
    }

    pub fn select(self: *Radiobutton) void {
        if (self.variable_group) |vg| {
            vg.* = self.value;
        }
        if (self.command) |cmd| cmd();
    }

    pub fn isSelected(self: *const Radiobutton) bool {
        if (self.variable_group) |vg| {
            return std.mem.eql(u8, vg.*, self.value);
        }
        return false;
    }
};

/// Scale (slider) widget
pub const Scale = struct {
    widget: Widget,
    from: f64 = 0.0,
    to: f64 = 100.0,
    value: f64 = 0.0,
    resolution: f64 = 1.0,
    orient: Orientation = .horizontal,
    length: u32 = 100,
    showvalue: bool = true,
    command: ?*const fn (f64) void = null,

    pub const Orientation = enum { horizontal, vertical };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Scale {
        var w = Widget.init(allocator, id);
        w.widget_class = .scale;
        return .{ .widget = w };
    }

    pub fn set(self: *Scale, val: f64) void {
        self.value = std.math.clamp(val, self.from, self.to);
        if (self.resolution > 0) {
            self.value = @round(self.value / self.resolution) * self.resolution;
        }
        if (self.command) |cmd| cmd(self.value);
    }

    pub fn get(self: *const Scale) f64 {
        return self.value;
    }
};

/// Spinbox widget
pub const Spinbox = struct {
    widget: Widget,
    from: f64 = 0.0,
    to: f64 = 100.0,
    increment: f64 = 1.0,
    value: f64 = 0.0,
    values: ?[]const []const u8 = null,
    wrap: bool = false,
    command: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Spinbox {
        var w = Widget.init(allocator, id);
        w.widget_class = .spinbox;
        return .{ .widget = w };
    }

    pub fn invoke(self: *Spinbox, element: SpinElement) void {
        switch (element) {
            .buttonup => self.value = @min(self.value + self.increment, self.to),
            .buttondown => self.value = @max(self.value - self.increment, self.from),
        }
        if (self.wrap) {
            if (self.value > self.to) self.value = self.from;
            if (self.value < self.from) self.value = self.to;
        }
        if (self.command) |cmd| cmd();
    }

    pub const SpinElement = enum { buttonup, buttondown };

    pub fn get(self: *const Spinbox) f64 {
        return self.value;
    }

    pub fn set(self: *Spinbox, val: f64) void {
        self.value = std.math.clamp(val, self.from, self.to);
    }
};

/// Listbox widget
pub const Listbox = struct {
    widget: Widget,
    items: std.ArrayList([]const u8),
    selection: std.ArrayList(usize),
    selectmode: SelectMode = .browse,
    activestyle: ActiveStyle = .dotbox,

    pub const SelectMode = enum { single, browse, multiple, extended };
    pub const ActiveStyle = enum { dotbox, underline, none };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Listbox {
        var w = Widget.init(allocator, id);
        w.widget_class = .listbox;
        return .{
            .widget = w,
            .items = std.ArrayList([]const u8).init(allocator),
            .selection = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Listbox) void {
        self.items.deinit();
        self.selection.deinit();
        self.widget.deinit();
    }

    pub fn insert(self: *Listbox, index: usize, item: []const u8) !void {
        const pos = @min(index, self.items.items.len);
        try self.items.insert(pos, item);
    }

    pub fn delete(self: *Listbox, first: usize, last: usize) void {
        const f = @min(first, self.items.items.len);
        const l = @min(last + 1, self.items.items.len);
        if (f < l) {
            var i: usize = 0;
            while (i < l - f and f < self.items.items.len) : (i += 1) {
                _ = self.items.orderedRemove(f);
            }
        }
    }

    pub fn get(self: *const Listbox, index: usize) ?[]const u8 {
        if (index < self.items.items.len) {
            return self.items.items[index];
        }
        return null;
    }

    pub fn size(self: *const Listbox) usize {
        return self.items.items.len;
    }

    pub fn selectionSet(self: *Listbox, first: usize, last: usize) !void {
        var i = first;
        while (i <= last and i < self.items.items.len) : (i += 1) {
            var found = false;
            for (self.selection.items) |s| {
                if (s == i) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try self.selection.append(i);
            }
        }
    }

    pub fn selectionClear(self: *Listbox, first: usize, last: usize) void {
        var new_selection = std.ArrayList(usize).init(self.widget.allocator);
        for (self.selection.items) |s| {
            if (s < first or s > last) {
                new_selection.append(s) catch {};
            }
        }
        self.selection.deinit();
        self.selection = new_selection;
    }

    pub fn curselection(self: *const Listbox) []const usize {
        return self.selection.items;
    }
};

/// Scrollbar widget
pub const Scrollbar = struct {
    widget: Widget,
    orient: Orientation = .vertical,
    command: ?*const fn (ScrollAction) void = null,
    first: f64 = 0.0,
    last: f64 = 1.0,

    pub const Orientation = enum { horizontal, vertical };
    pub const ScrollAction = struct {
        action: enum { moveto, scroll },
        value: f64,
        unit: enum { units, pages } = .units,
    };

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Scrollbar {
        var w = Widget.init(allocator, id);
        w.widget_class = .scrollbar;
        return .{ .widget = w };
    }

    pub fn set(self: *Scrollbar, first: f64, last: f64) void {
        self.first = std.math.clamp(first, 0.0, 1.0);
        self.last = std.math.clamp(last, 0.0, 1.0);
    }

    pub fn get(self: *const Scrollbar) struct { first: f64, last: f64 } {
        return .{ .first = self.first, .last = self.last };
    }
};

// Tests

test "widget_state" {
    const state = WidgetState{ .active = true, .focus = true };
    try testing.expect(state.isNormal());
    try testing.expectEqualStrings("active", state.toTclString());

    const disabled = WidgetState{ .disabled = true };
    try testing.expect(!disabled.isNormal());
    try testing.expectEqualStrings("disabled", disabled.toTclString());
}

test "widget_config" {
    const config1 = WidgetConfig{ .text = "Hello", .width = 100 };
    const config2 = WidgetConfig{ .text = "World", .height = 50 };
    const merged = config1.merge(config2);

    try testing.expectEqualStrings("World", merged.text.?);
    try testing.expectEqual(@as(i32, 100), merged.width.?);
    try testing.expectEqual(@as(i32, 50), merged.height.?);
}

test "padding" {
    const uniform = Padding.uniform(10);
    try testing.expectEqual(@as(u32, 20), uniform.horizontal());
    try testing.expectEqual(@as(u32, 20), uniform.vertical());

    const symmetric = Padding.symmetric(5, 10);
    try testing.expectEqual(@as(u32, 10), symmetric.horizontal());
    try testing.expectEqual(@as(u32, 20), symmetric.vertical());
}

test "widget_basic" {
    var widget = Widget.init(testing.allocator, ".frame1");
    defer widget.deinit();

    try testing.expectEqualStrings(".frame1", widget.id);
    try testing.expectEqualStrings("Frame", widget.winfo_class());
    try testing.expect(widget.parent == null);
    try testing.expect(!widget.destroyed);
}

test "widget_configure" {
    var widget = Widget.init(testing.allocator, ".label1");
    defer widget.deinit();

    widget.configure(.{ .text = "Hello", .background = "#ffffff" });
    try testing.expectEqualStrings("Hello", widget.cget("-text").?);
    try testing.expectEqualStrings("#ffffff", widget.cget("-background").?);
}

test "button_widget" {
    var invoked = false;
    const callback = struct {
        fn call() void {
            @as(*bool, @ptrFromInt(@intFromPtr(&invoked))).* = true;
        }
    }.call;
    _ = callback;

    var button = Button.init(testing.allocator, ".button1");
    defer button.widget.deinit();

    button.setText("Click Me");
    try testing.expectEqualStrings("Click Me", button.widget.config.text.?);
    try testing.expectEqualStrings("Button", button.widget.winfo_class());
}

test "label_widget" {
    var label = Label.init(testing.allocator, ".label1");
    defer label.widget.deinit();

    label.setText("Hello World");
    label.setImage("icon.png");
    label.anchor = .nw;

    try testing.expectEqualStrings("Hello World", label.widget.config.text.?);
    try testing.expectEqualStrings("icon.png", label.image.?);
    try testing.expectEqual(Label.Anchor.nw, label.anchor);
}

test "entry_widget" {
    var entry = Entry.init(testing.allocator, ".entry1");
    defer entry.deinit();

    try entry.insert(0, "Hello");
    try testing.expectEqualStrings("Hello", entry.get());

    try entry.insert(5, " World");
    try testing.expectEqualStrings("Hello World", entry.get());

    entry.selectRange(0, 5);
    try testing.expectEqualStrings("Hello", entry.getSelection().?);

    entry.delete(0, 6);
    try testing.expectEqualStrings("World", entry.get());
}

test "checkbutton_widget" {
    var cb = Checkbutton.init(testing.allocator, ".check1");
    defer cb.widget.deinit();

    try testing.expect(!cb.isSelected());

    cb.select();
    try testing.expect(cb.isSelected());

    cb.toggle();
    try testing.expect(!cb.isSelected());

    cb.deselect();
    try testing.expect(!cb.isSelected());
}

test "scale_widget" {
    var scale = Scale.init(testing.allocator, ".scale1");
    defer scale.widget.deinit();

    scale.from = 0;
    scale.to = 100;
    scale.resolution = 5;

    scale.set(47);
    try testing.expectEqual(@as(f64, 45), scale.get());

    scale.set(150);
    try testing.expectEqual(@as(f64, 100), scale.get());

    scale.set(-10);
    try testing.expectEqual(@as(f64, 0), scale.get());
}

test "spinbox_widget" {
    var spinbox = Spinbox.init(testing.allocator, ".spin1");
    defer spinbox.widget.deinit();

    spinbox.from = 0;
    spinbox.to = 10;
    spinbox.increment = 2;
    spinbox.value = 5;

    spinbox.invoke(.buttonup);
    try testing.expectEqual(@as(f64, 7), spinbox.get());

    spinbox.invoke(.buttondown);
    try testing.expectEqual(@as(f64, 5), spinbox.get());
}

test "listbox_widget" {
    var listbox = Listbox.init(testing.allocator, ".list1");
    defer listbox.deinit();

    try listbox.insert(0, "Item 1");
    try listbox.insert(1, "Item 2");
    try listbox.insert(2, "Item 3");

    try testing.expectEqual(@as(usize, 3), listbox.size());
    try testing.expectEqualStrings("Item 2", listbox.get(1).?);

    try listbox.selectionSet(0, 1);
    try testing.expectEqual(@as(usize, 2), listbox.curselection().len);

    listbox.delete(1, 1);
    try testing.expectEqual(@as(usize, 2), listbox.size());
}

test "scrollbar_widget" {
    var scrollbar = Scrollbar.init(testing.allocator, ".scroll1");
    defer scrollbar.widget.deinit();

    scrollbar.set(0.2, 0.5);
    const pos = scrollbar.get();

    try testing.expectEqual(@as(f64, 0.2), pos.first);
    try testing.expectEqual(@as(f64, 0.5), pos.last);

    scrollbar.set(-0.1, 1.5);
    const clamped = scrollbar.get();
    try testing.expectEqual(@as(f64, 0.0), clamped.first);
    try testing.expectEqual(@as(f64, 1.0), clamped.last);
}

test "relief_styles" {
    try testing.expectEqualStrings("flat", Relief.flat.toTclString());
    try testing.expectEqualStrings("raised", Relief.raised.toTclString());
    try testing.expectEqualStrings("sunken", Relief.sunken.toTclString());
    try testing.expectEqualStrings("groove", Relief.groove.toTclString());
}

test "widget_class_names" {
    try testing.expectEqualStrings("Button", WidgetClass.button.toClassName());
    try testing.expectEqualStrings("TNotebook", WidgetClass.notebook.toClassName());
    try testing.expectEqualStrings("Treeview", WidgetClass.treeview.toClassName());
}
