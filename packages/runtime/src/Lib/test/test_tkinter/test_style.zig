//! test.test_tkinter.test_style - Tk TTK style tests
//!
//! Tests for TTK themed widget styling including themes, style elements,
//! layout specifications, and dynamic appearance changes.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Available TTK themes
pub const Theme = enum {
    default,
    clam,
    alt,
    classic,
    vista,
    xpnative,
    winnative,
    aqua,

    pub fn toTclString(self: Theme) []const u8 {
        return switch (self) {
            .default => "default",
            .clam => "clam",
            .alt => "alt",
            .classic => "classic",
            .vista => "vista",
            .xpnative => "xpnative",
            .winnative => "winnative",
            .aqua => "aqua",
        };
    }

    pub fn fromString(s: []const u8) ?Theme {
        const themes = .{
            .{ "default", Theme.default },
            .{ "clam", Theme.clam },
            .{ "alt", Theme.alt },
            .{ "classic", Theme.classic },
            .{ "vista", Theme.vista },
            .{ "xpnative", Theme.xpnative },
            .{ "winnative", Theme.winnative },
            .{ "aqua", Theme.aqua },
        };
        inline for (themes) |pair| {
            if (std.mem.eql(u8, s, pair[0])) return pair[1];
        }
        return null;
    }
};

/// Widget states for styling
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

    pub fn toTclList(self: WidgetState, buf: []u8) []const u8 {
        var len: usize = 0;
        if (self.active) len += appendState(buf[len..], "active");
        if (self.disabled) len += appendState(buf[len..], "disabled");
        if (self.focus) len += appendState(buf[len..], "focus");
        if (self.pressed) len += appendState(buf[len..], "pressed");
        if (self.selected) len += appendState(buf[len..], "selected");
        if (self.background) len += appendState(buf[len..], "background");
        if (self.readonly) len += appendState(buf[len..], "readonly");
        if (self.alternate) len += appendState(buf[len..], "alternate");
        if (self.invalid) len += appendState(buf[len..], "invalid");
        if (self.hover) len += appendState(buf[len..], "hover");
        return buf[0..len];
    }

    fn appendState(buf: []u8, state: []const u8) usize {
        if (buf.len < state.len + 1) return 0;
        if (buf.len > 0 and buf[0] != 0) {
            buf[0] = ' ';
            @memcpy(buf[1 .. state.len + 1], state);
            return state.len + 1;
        }
        @memcpy(buf[0..state.len], state);
        return state.len;
    }

    pub fn none() WidgetState {
        return .{};
    }

    pub fn normal() WidgetState {
        return .{};
    }

    pub fn activeState() WidgetState {
        return .{ .active = true };
    }

    pub fn disabledState() WidgetState {
        return .{ .disabled = true };
    }
};

/// Style element types
pub const ElementType = enum {
    border,
    field,
    focus,
    label,
    padding,
    arrow,
    slider,
    pbar,
    thumb,
    trough,
    separator,
    sizegrip,
    indicator,
    text,
    image,
    vsapi,

    pub fn toTclString(self: ElementType) []const u8 {
        return switch (self) {
            .border => "border",
            .field => "field",
            .focus => "focus",
            .label => "label",
            .padding => "padding",
            .arrow => "arrow",
            .slider => "slider",
            .pbar => "pbar",
            .thumb => "thumb",
            .trough => "trough",
            .separator => "separator",
            .sizegrip => "sizegrip",
            .indicator => "indicator",
            .text => "text",
            .image => "image",
            .vsapi => "vsapi",
        };
    }
};

/// Layout sticky options
pub const Sticky = packed struct {
    north: bool = false,
    south: bool = false,
    east: bool = false,
    west: bool = false,

    pub fn all() Sticky {
        return .{ .north = true, .south = true, .east = true, .west = true };
    }

    pub fn horizontal() Sticky {
        return .{ .east = true, .west = true };
    }

    pub fn vertical() Sticky {
        return .{ .north = true, .south = true };
    }

    pub fn toTclString(self: Sticky) []const u8 {
        if (self.north and self.south and self.east and self.west) return "nsew";
        if (self.north and self.south) return "ns";
        if (self.east and self.west) return "ew";
        if (self.north) return "n";
        if (self.south) return "s";
        if (self.east) return "e";
        if (self.west) return "w";
        return "";
    }
};

/// Style option value
pub const StyleValue = union(enum) {
    string: []const u8,
    integer: i32,
    float: f64,
    color: []const u8,
    font: []const u8,
    padding: [4]i32,
    boolean: bool,

    pub fn fromString(s: []const u8) StyleValue {
        return .{ .string = s };
    }

    pub fn fromInt(i: i32) StyleValue {
        return .{ .integer = i };
    }

    pub fn fromPadding(top: i32, right: i32, bottom: i32, left: i32) StyleValue {
        return .{ .padding = .{ top, right, bottom, left } };
    }
};

/// Style configuration for a single state
pub const StateStyle = struct {
    state: WidgetState,
    options: std.StringHashMap(StyleValue),

    pub fn init(allocator: Allocator, state: WidgetState) StateStyle {
        return .{
            .state = state,
            .options = std.StringHashMap(StyleValue).init(allocator),
        };
    }

    pub fn deinit(self: *StateStyle) void {
        self.options.deinit();
    }

    pub fn set(self: *StateStyle, key: []const u8, value: StyleValue) !void {
        try self.options.put(key, value);
    }

    pub fn get(self: *StateStyle, key: []const u8) ?StyleValue {
        return self.options.get(key);
    }
};

/// Layout element specification
pub const LayoutElement = struct {
    element: ElementType,
    sticky: Sticky = .{},
    side: Side = .top,
    children: std.ArrayList(LayoutElement),
    allocator: Allocator,

    pub const Side = enum {
        top,
        bottom,
        left,
        right,

        pub fn toTclString(self: Side) []const u8 {
            return switch (self) {
                .top => "top",
                .bottom => "bottom",
                .left => "left",
                .right => "right",
            };
        }
    };

    pub fn init(allocator: Allocator, element: ElementType) LayoutElement {
        return .{
            .element = element,
            .children = std.ArrayList(LayoutElement).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LayoutElement) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn addChild(self: *LayoutElement, element: ElementType) !*LayoutElement {
        try self.children.append(LayoutElement.init(self.allocator, element));
        return &self.children.items[self.children.items.len - 1];
    }

    pub fn setSticky(self: *LayoutElement, sticky: Sticky) void {
        self.sticky = sticky;
    }

    pub fn setSide(self: *LayoutElement, side: Side) void {
        self.side = side;
    }
};

/// TTK Style definition
pub const Style = struct {
    name: []const u8,
    parent: ?[]const u8 = null,
    layout: ?LayoutElement = null,
    configure: std.StringHashMap(StyleValue),
    map: std.ArrayList(StateStyle),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) Style {
        return .{
            .name = name,
            .configure = std.StringHashMap(StyleValue).init(allocator),
            .map = std.ArrayList(StateStyle).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Style) void {
        self.configure.deinit();
        for (self.map.items) |*state_style| {
            state_style.deinit();
        }
        self.map.deinit();
        if (self.layout) |*layout| {
            layout.deinit();
        }
    }

    pub fn setParent(self: *Style, parent: []const u8) void {
        self.parent = parent;
    }

    pub fn set(self: *Style, key: []const u8, value: StyleValue) !void {
        try self.configure.put(key, value);
    }

    pub fn get(self: *Style, key: []const u8) ?StyleValue {
        return self.configure.get(key);
    }

    pub fn setLayout(self: *Style, layout: LayoutElement) void {
        self.layout = layout;
    }

    pub fn addStateMapping(self: *Style, state: WidgetState) !*StateStyle {
        try self.map.append(StateStyle.init(self.allocator, state));
        return &self.map.items[self.map.items.len - 1];
    }

    pub fn lookup(self: *Style, key: []const u8, state: WidgetState) ?StyleValue {
        // First check state-specific mappings
        for (self.map.items) |state_style| {
            if (matchesState(state_style.state, state)) {
                if (state_style.options.get(key)) |value| {
                    return value;
                }
            }
        }
        // Fall back to configure
        return self.configure.get(key);
    }

    fn matchesState(pattern: WidgetState, state: WidgetState) bool {
        // Pattern matches if all set flags in pattern are also set in state
        const pattern_bits: u16 = @bitCast(pattern);
        const state_bits: u16 = @bitCast(state);
        return (pattern_bits & state_bits) == pattern_bits;
    }
};

/// Style manager for TTK theming
pub const StyleManager = struct {
    current_theme: Theme = .default,
    available_themes: std.ArrayList(Theme),
    styles: std.StringHashMap(Style),
    element_specs: std.StringHashMap(ElementSpec),
    allocator: Allocator,

    pub const ElementSpec = struct {
        element_type: ElementType,
        options: std.StringHashMap(StyleValue),

        pub fn init(allocator: Allocator, element_type: ElementType) ElementSpec {
            return .{
                .element_type = element_type,
                .options = std.StringHashMap(StyleValue).init(allocator),
            };
        }

        pub fn deinit(self: *ElementSpec) void {
            self.options.deinit();
        }
    };

    pub fn init(allocator: Allocator) StyleManager {
        var manager = StyleManager{
            .available_themes = std.ArrayList(Theme).init(allocator),
            .styles = std.StringHashMap(Style).init(allocator),
            .element_specs = std.StringHashMap(ElementSpec).init(allocator),
            .allocator = allocator,
        };
        // Add default themes
        manager.available_themes.append(.default) catch {};
        manager.available_themes.append(.clam) catch {};
        manager.available_themes.append(.alt) catch {};
        manager.available_themes.append(.classic) catch {};
        return manager;
    }

    pub fn deinit(self: *StyleManager) void {
        self.available_themes.deinit();
        var style_iter = self.styles.valueIterator();
        while (style_iter.next()) |style| {
            @constCast(style).deinit();
        }
        self.styles.deinit();
        var elem_iter = self.element_specs.valueIterator();
        while (elem_iter.next()) |spec| {
            @constCast(spec).deinit();
        }
        self.element_specs.deinit();
    }

    pub fn setTheme(self: *StyleManager, theme: Theme) !void {
        for (self.available_themes.items) |t| {
            if (t == theme) {
                self.current_theme = theme;
                return;
            }
        }
        return error.ThemeNotAvailable;
    }

    pub fn getTheme(self: *StyleManager) Theme {
        return self.current_theme;
    }

    pub fn themeNames(self: *StyleManager) []const Theme {
        return self.available_themes.items;
    }

    pub fn createStyle(self: *StyleManager, name: []const u8) !*Style {
        const style = Style.init(self.allocator, name);
        try self.styles.put(name, style);
        return self.styles.getPtr(name).?;
    }

    pub fn getStyle(self: *StyleManager, name: []const u8) ?*Style {
        return self.styles.getPtr(name);
    }

    pub fn configure(self: *StyleManager, style_name: []const u8, key: []const u8, value: StyleValue) !void {
        if (self.styles.getPtr(style_name)) |style| {
            try style.set(key, value);
        } else {
            const style = try self.createStyle(style_name);
            try style.set(key, value);
        }
    }

    pub fn lookup(self: *StyleManager, style_name: []const u8, key: []const u8) ?StyleValue {
        if (self.styles.get(style_name)) |style| {
            return style.configure.get(key);
        }
        return null;
    }

    pub fn elementCreate(self: *StyleManager, name: []const u8, element_type: ElementType) !void {
        const spec = ElementSpec.init(self.allocator, element_type);
        try self.element_specs.put(name, spec);
    }

    pub fn elementNames(self: *StyleManager) [][]const u8 {
        var names = std.ArrayList([]const u8).init(self.allocator);
        var iter = self.element_specs.keyIterator();
        while (iter.next()) |key| {
            names.append(key.*) catch {};
        }
        return names.toOwnedSlice() catch &.{};
    }
};

/// Color utilities for styling
pub const ColorUtils = struct {
    pub fn parseColor(color: []const u8) ?struct { r: u8, g: u8, b: u8 } {
        if (color.len == 0) return null;

        // Handle #RRGGBB format
        if (color[0] == '#' and color.len == 7) {
            const r = std.fmt.parseInt(u8, color[1..3], 16) catch return null;
            const g = std.fmt.parseInt(u8, color[3..5], 16) catch return null;
            const b = std.fmt.parseInt(u8, color[5..7], 16) catch return null;
            return .{ .r = r, .g = g, .b = b };
        }

        // Handle named colors
        const named_colors = .{
            .{ "red", .{ .r = 255, .g = 0, .b = 0 } },
            .{ "green", .{ .r = 0, .g = 128, .b = 0 } },
            .{ "blue", .{ .r = 0, .g = 0, .b = 255 } },
            .{ "white", .{ .r = 255, .g = 255, .b = 255 } },
            .{ "black", .{ .r = 0, .g = 0, .b = 0 } },
            .{ "gray", .{ .r = 128, .g = 128, .b = 128 } },
            .{ "yellow", .{ .r = 255, .g = 255, .b = 0 } },
            .{ "cyan", .{ .r = 0, .g = 255, .b = 255 } },
            .{ "magenta", .{ .r = 255, .g = 0, .b = 255 } },
        };
        inline for (named_colors) |entry| {
            if (std.mem.eql(u8, color, entry[0])) {
                return entry[1];
            }
        }
        return null;
    }

    pub fn toHex(r: u8, g: u8, b: u8) [7]u8 {
        var buf: [7]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b }) catch unreachable;
        return buf;
    }

    pub fn darken(r: u8, g: u8, b: u8, factor: f32) struct { r: u8, g: u8, b: u8 } {
        const scale = 1.0 - factor;
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(r)) * scale),
            .g = @intFromFloat(@as(f32, @floatFromInt(g)) * scale),
            .b = @intFromFloat(@as(f32, @floatFromInt(b)) * scale),
        };
    }

    pub fn lighten(r: u8, g: u8, b: u8, factor: f32) struct { r: u8, g: u8, b: u8 } {
        return .{
            .r = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(r)) + (255.0 - @as(f32, @floatFromInt(r))) * factor)),
            .g = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(g)) + (255.0 - @as(f32, @floatFromInt(g))) * factor)),
            .b = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(b)) + (255.0 - @as(f32, @floatFromInt(b))) * factor)),
        };
    }
};

/// Font specification for styles
pub const FontSpec = struct {
    family: []const u8 = "TkDefaultFont",
    size: i32 = 0,
    weight: Weight = .normal,
    slant: Slant = .roman,
    underline: bool = false,
    overstrike: bool = false,

    pub const Weight = enum {
        normal,
        bold,

        pub fn toTclString(self: Weight) []const u8 {
            return switch (self) {
                .normal => "normal",
                .bold => "bold",
            };
        }
    };

    pub const Slant = enum {
        roman,
        italic,

        pub fn toTclString(self: Slant) []const u8 {
            return switch (self) {
                .roman => "roman",
                .italic => "italic",
            };
        }
    };

    pub fn toTclList(self: FontSpec, allocator: Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.append('{');
        try result.appendSlice(self.family);
        try result.append('}');

        if (self.size != 0) {
            var buf: [16]u8 = undefined;
            const size_str = std.fmt.bufPrint(&buf, " {d}", .{self.size}) catch "";
            try result.appendSlice(size_str);
        }

        if (self.weight == .bold) {
            try result.appendSlice(" bold");
        }
        if (self.slant == .italic) {
            try result.appendSlice(" italic");
        }
        if (self.underline) {
            try result.appendSlice(" underline");
        }
        if (self.overstrike) {
            try result.appendSlice(" overstrike");
        }

        return result.toOwnedSlice();
    }
};

/// Relief styles for widgets
pub const Relief = enum {
    flat,
    raised,
    sunken,
    groove,
    ridge,
    solid,

    pub fn toTclString(self: Relief) []const u8 {
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

/// Cursor types
pub const Cursor = enum {
    arrow,
    crosshair,
    hand2,
    xterm,
    watch,
    fleur,
    sizing,
    sb_h_double_arrow,
    sb_v_double_arrow,

    pub fn toTclString(self: Cursor) []const u8 {
        return switch (self) {
            .arrow => "arrow",
            .crosshair => "crosshair",
            .hand2 => "hand2",
            .xterm => "xterm",
            .watch => "watch",
            .fleur => "fleur",
            .sizing => "sizing",
            .sb_h_double_arrow => "sb_h_double_arrow",
            .sb_v_double_arrow => "sb_v_double_arrow",
        };
    }
};

// Tests

test "Theme conversion" {
    try testing.expectEqualStrings("default", Theme.default.toTclString());
    try testing.expectEqualStrings("clam", Theme.clam.toTclString());
    try testing.expectEqualStrings("aqua", Theme.aqua.toTclString());

    try testing.expectEqual(Theme.clam, Theme.fromString("clam").?);
    try testing.expectEqual(Theme.vista, Theme.fromString("vista").?);
    try testing.expect(Theme.fromString("unknown") == null);
}

test "WidgetState creation" {
    const normal = WidgetState.normal();
    try testing.expect(!normal.active);
    try testing.expect(!normal.disabled);

    const active = WidgetState.activeState();
    try testing.expect(active.active);
    try testing.expect(!active.disabled);

    const disabled = WidgetState.disabledState();
    try testing.expect(!disabled.active);
    try testing.expect(disabled.disabled);
}

test "ElementType conversion" {
    try testing.expectEqualStrings("border", ElementType.border.toTclString());
    try testing.expectEqualStrings("padding", ElementType.padding.toTclString());
    try testing.expectEqualStrings("trough", ElementType.trough.toTclString());
}

test "Sticky options" {
    const all = Sticky.all();
    try testing.expectEqualStrings("nsew", all.toTclString());

    const horizontal = Sticky.horizontal();
    try testing.expectEqualStrings("ew", horizontal.toTclString());

    const vertical = Sticky.vertical();
    try testing.expectEqualStrings("ns", vertical.toTclString());

    const north = Sticky{ .north = true };
    try testing.expectEqualStrings("n", north.toTclString());
}

test "StyleValue creation" {
    const str_val = StyleValue.fromString("test");
    try testing.expectEqualStrings("test", str_val.string);

    const int_val = StyleValue.fromInt(42);
    try testing.expectEqual(@as(i32, 42), int_val.integer);

    const pad_val = StyleValue.fromPadding(5, 10, 5, 10);
    try testing.expectEqual(@as(i32, 5), pad_val.padding[0]);
    try testing.expectEqual(@as(i32, 10), pad_val.padding[1]);
}

test "StateStyle operations" {
    const allocator = testing.allocator;
    var state_style = StateStyle.init(allocator, WidgetState.activeState());
    defer state_style.deinit();

    try state_style.set("foreground", StyleValue.fromString("blue"));
    try state_style.set("background", StyleValue.fromString("white"));

    const fg = state_style.get("foreground");
    try testing.expect(fg != null);
    try testing.expectEqualStrings("blue", fg.?.string);
}

test "LayoutElement hierarchy" {
    const allocator = testing.allocator;
    var border = LayoutElement.init(allocator, .border);
    defer border.deinit();

    const padding = try border.addChild(.padding);
    padding.setSticky(Sticky.all());
    padding.setSide(.left);

    _ = try padding.addChild(.label);

    try testing.expectEqual(@as(usize, 1), border.children.items.len);
    try testing.expectEqual(@as(usize, 1), border.children.items[0].children.items.len);
}

test "Style creation and configuration" {
    const allocator = testing.allocator;
    var style = Style.init(allocator, "TButton");
    defer style.deinit();

    style.setParent("TWidget");
    try style.set("padding", StyleValue.fromPadding(5, 10, 5, 10));
    try style.set("font", .{ .font = "TkDefaultFont" });

    try testing.expectEqualStrings("TWidget", style.parent.?);
    try testing.expect(style.get("padding") != null);
}

test "Style state mapping" {
    const allocator = testing.allocator;
    var style = Style.init(allocator, "TButton");
    defer style.deinit();

    const active_state = try style.addStateMapping(WidgetState.activeState());
    try active_state.set("background", StyleValue.fromString("lightblue"));

    try testing.expectEqual(@as(usize, 1), style.map.items.len);
}

test "StyleManager theme operations" {
    const allocator = testing.allocator;
    var manager = StyleManager.init(allocator);
    defer manager.deinit();

    try testing.expectEqual(Theme.default, manager.getTheme());

    try manager.setTheme(.clam);
    try testing.expectEqual(Theme.clam, manager.getTheme());

    const themes = manager.themeNames();
    try testing.expect(themes.len >= 4);
}

test "StyleManager style operations" {
    const allocator = testing.allocator;
    var manager = StyleManager.init(allocator);
    defer manager.deinit();

    const style = try manager.createStyle("Custom.TButton");
    try style.set("foreground", StyleValue.fromString("red"));

    const retrieved = manager.getStyle("Custom.TButton");
    try testing.expect(retrieved != null);

    try manager.configure("Custom.TButton", "background", StyleValue.fromString("white"));
    const bg = manager.lookup("Custom.TButton", "background");
    try testing.expect(bg != null);
}

test "StyleManager element creation" {
    const allocator = testing.allocator;
    var manager = StyleManager.init(allocator);
    defer manager.deinit();

    try manager.elementCreate("CustomBorder", .border);
    try manager.elementCreate("CustomField", .field);
}

test "ColorUtils parsing" {
    const red = ColorUtils.parseColor("#ff0000");
    try testing.expect(red != null);
    try testing.expectEqual(@as(u8, 255), red.?.r);
    try testing.expectEqual(@as(u8, 0), red.?.g);
    try testing.expectEqual(@as(u8, 0), red.?.b);

    const named_blue = ColorUtils.parseColor("blue");
    try testing.expect(named_blue != null);
    try testing.expectEqual(@as(u8, 0), named_blue.?.r);
    try testing.expectEqual(@as(u8, 0), named_blue.?.g);
    try testing.expectEqual(@as(u8, 255), named_blue.?.b);
}

test "ColorUtils to hex" {
    const hex = ColorUtils.toHex(255, 128, 64);
    try testing.expectEqualStrings("#ff8040", &hex);
}

test "ColorUtils darken and lighten" {
    const darkened = ColorUtils.darken(200, 100, 50, 0.5);
    try testing.expectEqual(@as(u8, 100), darkened.r);
    try testing.expectEqual(@as(u8, 50), darkened.g);
    try testing.expectEqual(@as(u8, 25), darkened.b);

    const lightened = ColorUtils.lighten(100, 100, 100, 0.5);
    try testing.expect(lightened.r > 100);
    try testing.expect(lightened.g > 100);
    try testing.expect(lightened.b > 100);
}

test "FontSpec creation" {
    const font = FontSpec{
        .family = "Helvetica",
        .size = 12,
        .weight = .bold,
        .slant = .italic,
    };

    try testing.expectEqualStrings("Helvetica", font.family);
    try testing.expectEqual(@as(i32, 12), font.size);
    try testing.expectEqual(FontSpec.Weight.bold, font.weight);
    try testing.expectEqual(FontSpec.Slant.italic, font.slant);
}

test "FontSpec to Tcl list" {
    const allocator = testing.allocator;
    const font = FontSpec{
        .family = "Arial",
        .size = 14,
        .weight = .bold,
    };
    const tcl = try font.toTclList(allocator);
    defer allocator.free(tcl);

    try testing.expect(std.mem.indexOf(u8, tcl, "Arial") != null);
    try testing.expect(std.mem.indexOf(u8, tcl, "14") != null);
    try testing.expect(std.mem.indexOf(u8, tcl, "bold") != null);
}

test "Relief types" {
    try testing.expectEqualStrings("flat", Relief.flat.toTclString());
    try testing.expectEqualStrings("raised", Relief.raised.toTclString());
    try testing.expectEqualStrings("sunken", Relief.sunken.toTclString());
    try testing.expectEqualStrings("groove", Relief.groove.toTclString());
}

test "Cursor types" {
    try testing.expectEqualStrings("arrow", Cursor.arrow.toTclString());
    try testing.expectEqualStrings("hand2", Cursor.hand2.toTclString());
    try testing.expectEqualStrings("xterm", Cursor.xterm.toTclString());
    try testing.expectEqualStrings("watch", Cursor.watch.toTclString());
}

test "LayoutElement side options" {
    const allocator = testing.allocator;
    var elem = LayoutElement.init(allocator, .border);
    defer elem.deinit();

    elem.setSide(.left);
    try testing.expectEqual(LayoutElement.Side.left, elem.side);
    try testing.expectEqualStrings("left", elem.side.toTclString());

    elem.setSide(.right);
    try testing.expectEqual(LayoutElement.Side.right, elem.side);
}

test "Style lookup with state" {
    const allocator = testing.allocator;
    var style = Style.init(allocator, "TEntry");
    defer style.deinit();

    // Set default background
    try style.set("background", StyleValue.fromString("white"));

    // Set disabled background
    const disabled_map = try style.addStateMapping(WidgetState.disabledState());
    try disabled_map.set("background", StyleValue.fromString("gray"));

    // Lookup normal state - should get default
    const normal_bg = style.lookup("background", WidgetState.normal());
    try testing.expect(normal_bg != null);
    try testing.expectEqualStrings("white", normal_bg.?.string);

    // Lookup disabled state - should get disabled mapping
    const disabled_bg = style.lookup("background", WidgetState.disabledState());
    try testing.expect(disabled_bg != null);
    try testing.expectEqualStrings("gray", disabled_bg.?.string);
}
