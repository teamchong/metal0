//! test.test_tkinter.test_menu - Tk menu tests
//! Tests for tkinter Menu widget and related functionality

const std = @import("std");
const testing = std.testing;

/// Menu item types
pub const MenuItemType = enum {
    command,
    checkbutton,
    radiobutton,
    separator,
    cascade,
    tearoff,

    pub fn toTclString(self: MenuItemType) []const u8 {
        return switch (self) {
            .command => "command",
            .checkbutton => "checkbutton",
            .radiobutton => "radiobutton",
            .separator => "separator",
            .cascade => "cascade",
            .tearoff => "tearoff",
        };
    }
};

/// Menu item state
pub const MenuState = enum {
    normal,
    active,
    disabled,

    pub fn toTclString(self: MenuState) []const u8 {
        return switch (self) {
            .normal => "normal",
            .active => "active",
            .disabled => "disabled",
        };
    }
};

/// Menu item configuration
pub const MenuItemConfig = struct {
    label: ?[]const u8 = null,
    command: ?*const fn () void = null,
    accelerator: ?[]const u8 = null,
    underline: ?i32 = null,
    image: ?[]const u8 = null,
    compound: Compound = .none,
    state: MenuState = .normal,
    font: ?[]const u8 = null,
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    activeforeground: ?[]const u8 = null,
    activebackground: ?[]const u8 = null,
    columnbreak: bool = false,
    hidemargin: bool = false,

    pub const Compound = enum { none, bottom, top, left, right, center };
};

/// Checkbutton specific config
pub const CheckbuttonConfig = struct {
    base: MenuItemConfig = .{},
    variable: ?*bool = null,
    onvalue: bool = true,
    offvalue: bool = false,
    indicatoron: bool = true,
    selectcolor: ?[]const u8 = null,
};

/// Radiobutton specific config
pub const RadiobuttonConfig = struct {
    base: MenuItemConfig = .{},
    variable: ?*[]const u8 = null,
    value: []const u8 = "",
    indicatoron: bool = true,
    selectcolor: ?[]const u8 = null,
};

/// Cascade menu config
pub const CascadeConfig = struct {
    base: MenuItemConfig = .{},
    menu: ?*Menu = null,
};

/// Menu item representation
pub const MenuItem = struct {
    item_type: MenuItemType,
    index: u32,
    config: MenuItemConfig = .{},
    submenu: ?*Menu = null,
    check_var: ?*bool = null,
    radio_value: ?[]const u8 = null,

    pub fn invoke(self: *MenuItem) void {
        if (self.config.state == .disabled) return;

        switch (self.item_type) {
            .command => {
                if (self.config.command) |cmd| {
                    cmd();
                }
            },
            .checkbutton => {
                if (self.check_var) |v| {
                    v.* = !v.*;
                }
                if (self.config.command) |cmd| {
                    cmd();
                }
            },
            .radiobutton => {
                if (self.config.command) |cmd| {
                    cmd();
                }
            },
            else => {},
        }
    }

    pub fn isChecked(self: *const MenuItem) bool {
        if (self.item_type != .checkbutton) return false;
        if (self.check_var) |v| {
            return v.*;
        }
        return false;
    }
};

/// Menu widget
pub const Menu = struct {
    items: std.ArrayList(MenuItem),
    allocator: std.mem.Allocator,
    tearoff: bool = false,
    title: ?[]const u8 = null,
    postcommand: ?*const fn () void = null,
    tearoffcommand: ?*const fn () void = null,
    font: ?[]const u8 = null,
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    activeforeground: ?[]const u8 = null,
    activebackground: ?[]const u8 = null,
    disabledforeground: ?[]const u8 = null,
    selectcolor: ?[]const u8 = null,
    relief: []const u8 = "raised",
    borderwidth: u32 = 1,
    activeborderwidth: u32 = 1,
    type_mode: MenuType = .normal,

    pub const MenuType = enum { normal, menubar, tearoff };

    pub fn init(allocator: std.mem.Allocator) Menu {
        return .{
            .items = std.ArrayList(MenuItem).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Menu) void {
        self.items.deinit();
    }

    pub fn addCommand(self: *Menu, config: MenuItemConfig) !u32 {
        const idx = @as(u32, @intCast(self.items.items.len));
        try self.items.append(.{
            .item_type = .command,
            .index = idx,
            .config = config,
        });
        return idx;
    }

    pub fn addCheckbutton(self: *Menu, config: CheckbuttonConfig) !u32 {
        const idx = @as(u32, @intCast(self.items.items.len));
        try self.items.append(.{
            .item_type = .checkbutton,
            .index = idx,
            .config = config.base,
            .check_var = config.variable,
        });
        return idx;
    }

    pub fn addRadiobutton(self: *Menu, config: RadiobuttonConfig) !u32 {
        const idx = @as(u32, @intCast(self.items.items.len));
        try self.items.append(.{
            .item_type = .radiobutton,
            .index = idx,
            .config = config.base,
            .radio_value = config.value,
        });
        return idx;
    }

    pub fn addSeparator(self: *Menu) !u32 {
        const idx = @as(u32, @intCast(self.items.items.len));
        try self.items.append(.{
            .item_type = .separator,
            .index = idx,
        });
        return idx;
    }

    pub fn addCascade(self: *Menu, config: CascadeConfig) !u32 {
        const idx = @as(u32, @intCast(self.items.items.len));
        try self.items.append(.{
            .item_type = .cascade,
            .index = idx,
            .config = config.base,
            .submenu = config.menu,
        });
        return idx;
    }

    pub fn insert(self: *Menu, index: u32, item_type: MenuItemType, config: MenuItemConfig) !void {
        const idx = @min(index, @as(u32, @intCast(self.items.items.len)));
        try self.items.insert(idx, .{
            .item_type = item_type,
            .index = idx,
            .config = config,
        });
        // Update indices of subsequent items
        var i = idx + 1;
        while (i < self.items.items.len) : (i += 1) {
            self.items.items[i].index = @as(u32, @intCast(i));
        }
    }

    pub fn delete(self: *Menu, first: u32, last: ?u32) void {
        const f = @min(first, @as(u32, @intCast(self.items.items.len)));
        const l = @min(last orelse first, @as(u32, @intCast(self.items.items.len)));

        var count: u32 = 0;
        while (count <= l - f and f < self.items.items.len) : (count += 1) {
            _ = self.items.orderedRemove(f);
        }

        // Update indices
        var i: usize = f;
        while (i < self.items.items.len) : (i += 1) {
            self.items.items[i].index = @as(u32, @intCast(i));
        }
    }

    pub fn entrycget(self: *const Menu, index: u32, option: []const u8) ?[]const u8 {
        if (index >= self.items.items.len) return null;

        const item = self.items.items[index];
        if (std.mem.eql(u8, option, "-label")) return item.config.label;
        if (std.mem.eql(u8, option, "-accelerator")) return item.config.accelerator;
        if (std.mem.eql(u8, option, "-state")) return item.config.state.toTclString();

        return null;
    }

    pub fn entryconfigure(self: *Menu, index: u32, config: MenuItemConfig) void {
        if (index < self.items.items.len) {
            self.items.items[index].config = config;
        }
    }

    pub fn index(self: *const Menu, pattern: []const u8) ?u32 {
        if (std.mem.eql(u8, pattern, "end") or std.mem.eql(u8, pattern, "last")) {
            if (self.items.items.len == 0) return null;
            return @as(u32, @intCast(self.items.items.len - 1));
        }
        if (std.mem.eql(u8, pattern, "none")) {
            return null;
        }
        if (std.mem.eql(u8, pattern, "active")) {
            for (self.items.items, 0..) |item, i| {
                if (item.config.state == .active) {
                    return @as(u32, @intCast(i));
                }
            }
            return null;
        }

        // Try numeric index
        if (std.fmt.parseInt(u32, pattern, 10)) |idx| {
            if (idx < self.items.items.len) return idx;
        } else |_| {}

        // Search by label
        for (self.items.items, 0..) |item, i| {
            if (item.config.label) |label| {
                if (std.mem.eql(u8, label, pattern)) {
                    return @as(u32, @intCast(i));
                }
            }
        }

        return null;
    }

    pub fn invoke(self: *Menu, idx: u32) void {
        if (idx < self.items.items.len) {
            self.items.items[idx].invoke();
        }
    }

    pub fn itemType(self: *const Menu, idx: u32) ?MenuItemType {
        if (idx < self.items.items.len) {
            return self.items.items[idx].item_type;
        }
        return null;
    }

    pub fn size(self: *const Menu) usize {
        return self.items.items.len;
    }

    pub fn post(self: *Menu, x: i32, y: i32) void {
        _ = self;
        _ = x;
        _ = y;
        // Display popup menu at coordinates
    }

    pub fn unpost(self: *Menu) void {
        _ = self;
        // Hide popup menu
    }

    pub fn activate(self: *Menu, idx: u32) void {
        // Deactivate all
        for (self.items.items) |*item| {
            if (item.config.state == .active) {
                item.config.state = .normal;
            }
        }
        // Activate specified item
        if (idx < self.items.items.len) {
            if (self.items.items[idx].config.state != .disabled) {
                self.items.items[idx].config.state = .active;
            }
        }
    }

    pub fn yposition(self: *const Menu, idx: u32) i32 {
        // Return y pixel position of entry
        _ = self;
        return @as(i32, @intCast(idx)) * 20; // Approximate
    }
};

/// Menubar (horizontal menu container)
pub const Menubar = struct {
    menus: std.ArrayList(MenuEntry),
    allocator: std.mem.Allocator,

    pub const MenuEntry = struct {
        label: []const u8,
        menu: *Menu,
        underline: ?i32 = null,
    };

    pub fn init(allocator: std.mem.Allocator) Menubar {
        return .{
            .menus = std.ArrayList(MenuEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Menubar) void {
        self.menus.deinit();
    }

    pub fn addMenu(self: *Menubar, label: []const u8, menu: *Menu) !void {
        try self.menus.append(.{ .label = label, .menu = menu });
    }

    pub fn getMenu(self: *const Menubar, label: []const u8) ?*Menu {
        for (self.menus.items) |entry| {
            if (std.mem.eql(u8, entry.label, label)) {
                return entry.menu;
            }
        }
        return null;
    }

    pub fn getMenuByIndex(self: *const Menubar, idx: usize) ?*Menu {
        if (idx < self.menus.items.len) {
            return self.menus.items[idx].menu;
        }
        return null;
    }

    pub fn count(self: *const Menubar) usize {
        return self.menus.items.len;
    }
};

/// Option menu (dropdown selection)
pub const OptionMenu = struct {
    variable: []const u8,
    values: std.ArrayList([]const u8),
    menu: Menu,
    allocator: std.mem.Allocator,
    current_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator, variable: []const u8) OptionMenu {
        return .{
            .variable = variable,
            .values = std.ArrayList([]const u8).init(allocator),
            .menu = Menu.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OptionMenu) void {
        self.values.deinit();
        self.menu.deinit();
    }

    pub fn setValues(self: *OptionMenu, values: []const []const u8) !void {
        self.values.clearRetainingCapacity();
        self.menu.items.clearRetainingCapacity();

        for (values) |value| {
            try self.values.append(value);
            _ = try self.menu.addCommand(.{ .label = value });
        }
    }

    pub fn getValue(self: *const OptionMenu) ?[]const u8 {
        if (self.current_idx < self.values.items.len) {
            return self.values.items[self.current_idx];
        }
        return null;
    }

    pub fn setValue(self: *OptionMenu, value: []const u8) bool {
        for (self.values.items, 0..) |v, i| {
            if (std.mem.eql(u8, v, value)) {
                self.current_idx = i;
                return true;
            }
        }
        return false;
    }

    pub fn setIndex(self: *OptionMenu, idx: usize) bool {
        if (idx < self.values.items.len) {
            self.current_idx = idx;
            return true;
        }
        return false;
    }
};

/// Popup menu helper
pub const PopupMenu = struct {
    menu: Menu,
    x: i32 = 0,
    y: i32 = 0,
    visible: bool = false,

    pub fn init(allocator: std.mem.Allocator) PopupMenu {
        return .{
            .menu = Menu.init(allocator),
        };
    }

    pub fn deinit(self: *PopupMenu) void {
        self.menu.deinit();
    }

    pub fn show(self: *PopupMenu, x: i32, y: i32) void {
        self.x = x;
        self.y = y;
        self.visible = true;
        self.menu.post(x, y);
    }

    pub fn hide(self: *PopupMenu) void {
        self.visible = false;
        self.menu.unpost();
    }

    pub fn isVisible(self: *const PopupMenu) bool {
        return self.visible;
    }
};

// Tests

test "menu_item_type" {
    try testing.expectEqualStrings("command", MenuItemType.command.toTclString());
    try testing.expectEqualStrings("separator", MenuItemType.separator.toTclString());
    try testing.expectEqualStrings("cascade", MenuItemType.cascade.toTclString());
}

test "menu_state" {
    try testing.expectEqualStrings("normal", MenuState.normal.toTclString());
    try testing.expectEqualStrings("disabled", MenuState.disabled.toTclString());
}

test "menu_add_command" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    const idx = try menu.addCommand(.{ .label = "Open", .accelerator = "Ctrl+O" });
    try testing.expectEqual(@as(u32, 0), idx);
    try testing.expectEqual(@as(usize, 1), menu.size());

    const item_type = menu.itemType(0);
    try testing.expectEqual(MenuItemType.command, item_type.?);
}

test "menu_add_separator" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "Cut" });
    _ = try menu.addSeparator();
    _ = try menu.addCommand(.{ .label = "Paste" });

    try testing.expectEqual(@as(usize, 3), menu.size());
    try testing.expectEqual(MenuItemType.separator, menu.itemType(1).?);
}

test "menu_add_checkbutton" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    var checked = false;
    _ = try menu.addCheckbutton(.{
        .base = .{ .label = "Show Toolbar" },
        .variable = &checked,
    });

    try testing.expectEqual(MenuItemType.checkbutton, menu.itemType(0).?);
    try testing.expect(!menu.items.items[0].isChecked());
}

test "menu_add_cascade" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    var submenu = Menu.init(testing.allocator);
    defer submenu.deinit();
    _ = try submenu.addCommand(.{ .label = "Zoom In" });
    _ = try submenu.addCommand(.{ .label = "Zoom Out" });

    _ = try menu.addCascade(.{
        .base = .{ .label = "View" },
        .menu = &submenu,
    });

    try testing.expectEqual(MenuItemType.cascade, menu.itemType(0).?);
    try testing.expect(menu.items.items[0].submenu != null);
}

test "menu_delete" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "Item 1" });
    _ = try menu.addCommand(.{ .label = "Item 2" });
    _ = try menu.addCommand(.{ .label = "Item 3" });

    try testing.expectEqual(@as(usize, 3), menu.size());

    menu.delete(1, null);
    try testing.expectEqual(@as(usize, 2), menu.size());

    // Verify indices are updated
    try testing.expectEqual(@as(u32, 0), menu.items.items[0].index);
    try testing.expectEqual(@as(u32, 1), menu.items.items[1].index);
}

test "menu_entrycget" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "Save", .accelerator = "Ctrl+S" });

    const label = menu.entrycget(0, "-label");
    try testing.expectEqualStrings("Save", label.?);

    const accel = menu.entrycget(0, "-accelerator");
    try testing.expectEqualStrings("Ctrl+S", accel.?);
}

test "menu_index" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "New" });
    _ = try menu.addCommand(.{ .label = "Open" });
    _ = try menu.addCommand(.{ .label = "Save" });

    const end_idx = menu.index("end");
    try testing.expectEqual(@as(u32, 2), end_idx.?);

    const label_idx = menu.index("Open");
    try testing.expectEqual(@as(u32, 1), label_idx.?);

    const num_idx = menu.index("0");
    try testing.expectEqual(@as(u32, 0), num_idx.?);
}

test "menu_activate" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "Item 1" });
    _ = try menu.addCommand(.{ .label = "Item 2" });

    menu.activate(0);
    try testing.expectEqual(MenuState.active, menu.items.items[0].config.state);

    menu.activate(1);
    try testing.expectEqual(MenuState.normal, menu.items.items[0].config.state);
    try testing.expectEqual(MenuState.active, menu.items.items[1].config.state);
}

test "menubar_basic" {
    var menubar = Menubar.init(testing.allocator);
    defer menubar.deinit();

    var file_menu = Menu.init(testing.allocator);
    defer file_menu.deinit();
    var edit_menu = Menu.init(testing.allocator);
    defer edit_menu.deinit();

    try menubar.addMenu("File", &file_menu);
    try menubar.addMenu("Edit", &edit_menu);

    try testing.expectEqual(@as(usize, 2), menubar.count());

    const file = menubar.getMenu("File");
    try testing.expect(file != null);
}

test "menubar_get_by_index" {
    var menubar = Menubar.init(testing.allocator);
    defer menubar.deinit();

    var menu1 = Menu.init(testing.allocator);
    defer menu1.deinit();
    var menu2 = Menu.init(testing.allocator);
    defer menu2.deinit();

    try menubar.addMenu("Menu1", &menu1);
    try menubar.addMenu("Menu2", &menu2);

    const m = menubar.getMenuByIndex(1);
    try testing.expect(m != null);
}

test "option_menu" {
    var opt = OptionMenu.init(testing.allocator, "myvar");
    defer opt.deinit();

    try opt.setValues(&[_][]const u8{ "Red", "Green", "Blue" });
    try testing.expectEqual(@as(usize, 3), opt.values.items.len);

    try testing.expectEqualStrings("Red", opt.getValue().?);

    const found = opt.setValue("Blue");
    try testing.expect(found);
    try testing.expectEqualStrings("Blue", opt.getValue().?);
}

test "option_menu_set_index" {
    var opt = OptionMenu.init(testing.allocator, "var");
    defer opt.deinit();

    try opt.setValues(&[_][]const u8{ "A", "B", "C" });

    const success = opt.setIndex(2);
    try testing.expect(success);
    try testing.expectEqualStrings("C", opt.getValue().?);

    const failed = opt.setIndex(10);
    try testing.expect(!failed);
}

test "popup_menu" {
    var popup = PopupMenu.init(testing.allocator);
    defer popup.deinit();

    _ = try popup.menu.addCommand(.{ .label = "Cut" });
    _ = try popup.menu.addCommand(.{ .label = "Copy" });
    _ = try popup.menu.addCommand(.{ .label = "Paste" });

    try testing.expect(!popup.isVisible());

    popup.show(100, 200);
    try testing.expect(popup.isVisible());
    try testing.expectEqual(@as(i32, 100), popup.x);
    try testing.expectEqual(@as(i32, 200), popup.y);

    popup.hide();
    try testing.expect(!popup.isVisible());
}

test "menu_insert" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{ .label = "First" });
    _ = try menu.addCommand(.{ .label = "Last" });

    try menu.insert(1, .command, .{ .label = "Middle" });

    try testing.expectEqual(@as(usize, 3), menu.size());
    try testing.expectEqualStrings("First", menu.items.items[0].config.label.?);
    try testing.expectEqualStrings("Middle", menu.items.items[1].config.label.?);
    try testing.expectEqualStrings("Last", menu.items.items[2].config.label.?);
}

test "menu_disabled_item" {
    var menu = Menu.init(testing.allocator);
    defer menu.deinit();

    _ = try menu.addCommand(.{
        .label = "Disabled Item",
        .state = .disabled,
    });

    try testing.expectEqual(MenuState.disabled, menu.items.items[0].config.state);
}
