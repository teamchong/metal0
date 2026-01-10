//! test.test_ttk.test_style - Ttk Style configuration tests
//!
//! Tests for ttk.Style which provides theming and styling for ttk widgets.
//! Styles define the appearance of widgets including colors, fonts, padding, etc.

const std = @import("std");
const testing = std.testing;

/// Style element options - defines individual element appearance
pub const ElementOptions = struct {
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    font: ?[]const u8 = null,
    borderwidth: ?i32 = null,
    relief: ?Relief = null,
    padding: ?Padding = null,
    anchor: ?Anchor = null,
    width: ?i32 = null,
    sticky: ?[]const u8 = null,

    pub const Relief = enum {
        flat,
        raised,
        sunken,
        groove,
        ridge,
        solid,

        pub fn toString(self: Relief) []const u8 {
            return switch (self) {
                .flat => "flat",
                .raised => "raised",
                .sunken => "sunken",
                .groove => "groove",
                .ridge => "ridge",
                .solid => "solid",
            };
        }
    };

    pub const Anchor = enum {
        n,
        ne,
        e,
        se,
        s,
        sw,
        w,
        nw,
        center,

        pub fn toString(self: Anchor) []const u8 {
            return switch (self) {
                .n => "n",
                .ne => "ne",
                .e => "e",
                .se => "se",
                .s => "s",
                .sw => "sw",
                .w => "w",
                .nw => "nw",
                .center => "center",
            };
        }
    };

    pub const Padding = struct {
        left: i32 = 0,
        top: i32 = 0,
        right: i32 = 0,
        bottom: i32 = 0,

        pub fn uniform(value: i32) Padding {
            return .{ .left = value, .top = value, .right = value, .bottom = value };
        }

        pub fn symmetric(horizontal: i32, vertical: i32) Padding {
            return .{ .left = horizontal, .top = vertical, .right = horizontal, .bottom = vertical };
        }
    };
};

/// Widget state flags for state-based styling
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

    pub fn toStateSpec(self: WidgetState, allocator: std.mem.Allocator) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        if (self.active) try parts.append("active");
        if (self.disabled) try parts.append("disabled");
        if (self.focus) try parts.append("focus");
        if (self.pressed) try parts.append("pressed");
        if (self.selected) try parts.append("selected");
        if (self.background) try parts.append("background");
        if (self.readonly) try parts.append("readonly");
        if (self.alternate) try parts.append("alternate");
        if (self.invalid) try parts.append("invalid");
        if (self.hover) try parts.append("hover");

        return std.mem.join(allocator, " ", parts.items);
    }
};

/// Style map entry - maps states to option values
pub const StyleMapEntry = struct {
    states: WidgetState,
    value: []const u8,
};

/// Style configuration for a widget class
pub const StyleConfig = struct {
    name: []const u8,
    parent: ?[]const u8 = null,
    options: ElementOptions = .{},
    state_maps: std.StringHashMap([]StyleMapEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) StyleConfig {
        return .{
            .name = name,
            .allocator = allocator,
            .options = .{},
            .state_maps = std.StringHashMap([]StyleMapEntry).init(allocator),
        };
    }

    pub fn deinit(self: *StyleConfig) void {
        self.state_maps.deinit();
    }

    pub fn configure(self: *StyleConfig, options: ElementOptions) void {
        if (options.foreground) |fg| self.options.foreground = fg;
        if (options.background) |bg| self.options.background = bg;
        if (options.font) |font| self.options.font = font;
        if (options.borderwidth) |bw| self.options.borderwidth = bw;
        if (options.relief) |rel| self.options.relief = rel;
        if (options.padding) |pad| self.options.padding = pad;
        if (options.anchor) |anc| self.options.anchor = anc;
        if (options.width) |w| self.options.width = w;
    }

    pub fn setMap(self: *StyleConfig, option: []const u8, entries: []StyleMapEntry) !void {
        try self.state_maps.put(option, entries);
    }
};

/// Ttk Style manager
pub const Style = struct {
    allocator: std.mem.Allocator,
    theme_name: []const u8,
    styles: std.StringHashMap(StyleConfig),
    elements: std.StringHashMap(ElementOptions),

    pub fn init(allocator: std.mem.Allocator) Style {
        return .{
            .allocator = allocator,
            .theme_name = "default",
            .styles = std.StringHashMap(StyleConfig).init(allocator),
            .elements = std.StringHashMap(ElementOptions).init(allocator),
        };
    }

    pub fn deinit(self: *Style) void {
        var iter = self.styles.valueIterator();
        while (iter.next()) |config| {
            config.deinit();
        }
        self.styles.deinit();
        self.elements.deinit();
    }

    /// Configure a style
    pub fn configure(self: *Style, style_name: []const u8, options: ElementOptions) !void {
        const result = try self.styles.getOrPut(style_name);
        if (!result.found_existing) {
            result.value_ptr.* = StyleConfig.init(self.allocator, style_name);
        }
        result.value_ptr.configure(options);
    }

    /// Get style configuration
    pub fn lookup(self: *Style, style_name: []const u8, option: []const u8) ?[]const u8 {
        const config = self.styles.get(style_name) orelse return null;
        if (std.mem.eql(u8, option, "foreground")) return config.options.foreground;
        if (std.mem.eql(u8, option, "background")) return config.options.background;
        if (std.mem.eql(u8, option, "font")) return config.options.font;
        return null;
    }

    /// Create a derived style
    pub fn derive(self: *Style, new_name: []const u8, parent_name: []const u8) !void {
        var new_config = StyleConfig.init(self.allocator, new_name);
        new_config.parent = parent_name;

        if (self.styles.get(parent_name)) |parent| {
            new_config.options = parent.options;
        }

        try self.styles.put(new_name, new_config);
    }

    /// Register a custom element
    pub fn elementCreate(self: *Style, name: []const u8, options: ElementOptions) !void {
        try self.elements.put(name, options);
    }

    /// Get list of available themes
    pub fn themeNames(_: *Style) []const []const u8 {
        return &[_][]const u8{ "clam", "alt", "default", "classic" };
    }

    /// Set current theme
    pub fn themeUse(self: *Style, theme: []const u8) void {
        self.theme_name = theme;
    }

    /// Get current theme
    pub fn themeCurrent(self: *Style) []const u8 {
        return self.theme_name;
    }
};

/// Layout specification for compound widgets
pub const Layout = struct {
    element: []const u8,
    children: ?[]const Layout = null,
    options: LayoutOptions = .{},

    pub const LayoutOptions = struct {
        side: ?Side = null,
        sticky: ?[]const u8 = null,
        expand: bool = false,

        pub const Side = enum { left, right, top, bottom };
    };

    pub fn create(element: []const u8) Layout {
        return .{ .element = element };
    }

    pub fn withChildren(element: []const u8, children: []const Layout) Layout {
        return .{ .element = element, .children = children };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "style_init" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    try testing.expectEqualStrings("default", style.themeCurrent());
}

test "style_configure" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    try style.configure("TButton", .{
        .foreground = "black",
        .background = "white",
        .font = "TkDefaultFont",
    });

    try testing.expectEqualStrings("black", style.lookup("TButton", "foreground").?);
    try testing.expectEqualStrings("white", style.lookup("TButton", "background").?);
}

test "style_derive" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    try style.configure("TButton", .{
        .foreground = "black",
        .background = "lightgray",
    });

    try style.derive("Custom.TButton", "TButton");

    const derived = style.styles.get("Custom.TButton");
    try testing.expect(derived != null);
    try testing.expectEqualStrings("TButton", derived.?.parent.?);
}

test "style_theme_names" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    const themes = style.themeNames();
    try testing.expect(themes.len >= 4);
    try testing.expectEqualStrings("clam", themes[0]);
}

test "style_theme_use" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    style.themeUse("clam");
    try testing.expectEqualStrings("clam", style.themeCurrent());
}

test "element_options_relief" {
    try testing.expectEqualStrings("raised", ElementOptions.Relief.raised.toString());
    try testing.expectEqualStrings("sunken", ElementOptions.Relief.sunken.toString());
    try testing.expectEqualStrings("flat", ElementOptions.Relief.flat.toString());
}

test "element_options_anchor" {
    try testing.expectEqualStrings("center", ElementOptions.Anchor.center.toString());
    try testing.expectEqualStrings("nw", ElementOptions.Anchor.nw.toString());
    try testing.expectEqualStrings("se", ElementOptions.Anchor.se.toString());
}

test "padding_uniform" {
    const pad = ElementOptions.Padding.uniform(10);
    try testing.expectEqual(@as(i32, 10), pad.left);
    try testing.expectEqual(@as(i32, 10), pad.top);
    try testing.expectEqual(@as(i32, 10), pad.right);
    try testing.expectEqual(@as(i32, 10), pad.bottom);
}

test "padding_symmetric" {
    const pad = ElementOptions.Padding.symmetric(5, 10);
    try testing.expectEqual(@as(i32, 5), pad.left);
    try testing.expectEqual(@as(i32, 10), pad.top);
    try testing.expectEqual(@as(i32, 5), pad.right);
    try testing.expectEqual(@as(i32, 10), pad.bottom);
}

test "widget_state" {
    const state = WidgetState{ .active = true, .focus = true };
    try testing.expect(state.active);
    try testing.expect(state.focus);
    try testing.expect(!state.disabled);
}

test "widget_state_to_spec" {
    const state = WidgetState{ .active = true, .pressed = true };
    const spec = try state.toStateSpec(testing.allocator);
    defer testing.allocator.free(spec);

    try testing.expect(std.mem.indexOf(u8, spec, "active") != null);
    try testing.expect(std.mem.indexOf(u8, spec, "pressed") != null);
}

test "layout_create" {
    const layout = Layout.create("Button.button");
    try testing.expectEqualStrings("Button.button", layout.element);
    try testing.expect(layout.children == null);
}

test "layout_with_children" {
    const children = [_]Layout{
        Layout.create("Button.padding"),
        Layout.create("Button.label"),
    };
    const layout = Layout.withChildren("Button.button", &children);

    try testing.expectEqualStrings("Button.button", layout.element);
    try testing.expect(layout.children != null);
    try testing.expectEqual(@as(usize, 2), layout.children.?.len);
}

test "element_create" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    try style.elementCreate("custom.element", .{
        .background = "blue",
        .borderwidth = 2,
    });

    const elem = style.elements.get("custom.element");
    try testing.expect(elem != null);
    try testing.expectEqualStrings("blue", elem.?.background.?);
}

test "style_lookup_nonexistent" {
    var style = Style.init(testing.allocator);
    defer style.deinit();

    const result = style.lookup("NonExistent", "foreground");
    try testing.expect(result == null);
}
