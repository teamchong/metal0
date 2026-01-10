//! test.test_ttk.test_menu - Tk menu tests
const std = @import("std");

/// Menu item types
pub const MenuItemType = enum {
    command,
    checkbutton,
    radiobutton,
    separator,
    cascade,
};

/// Menu item
pub const MenuItem = struct {
    type_: MenuItemType,
    label: ?[]const u8 = null,
    command: ?*const fn () void = null,
    accelerator: ?[]const u8 = null,
    underline: ?usize = null,
    state: ItemState = .normal,
    variable: ?*bool = null,
    value: ?[]const u8 = null,
    menu: ?*Menu = null,

    pub const ItemState = enum { normal, active, disabled };

    pub fn command_item(label: []const u8, cmd: *const fn () void) MenuItem {
        return .{
            .type_ = .command,
            .label = label,
            .command = cmd,
        };
    }

    pub fn separator() MenuItem {
        return .{ .type_ = .separator };
    }

    pub fn checkbutton(label: []const u8, variable: *bool) MenuItem {
        return .{
            .type_ = .checkbutton,
            .label = label,
            .variable = variable,
        };
    }

    pub fn cascade(label: []const u8, menu: *Menu) MenuItem {
        return .{
            .type_ = .cascade,
            .label = label,
            .menu = menu,
        };
    }

    pub fn withAccelerator(self: MenuItem, accel: []const u8) MenuItem {
        var copy = self;
        copy.accelerator = accel;
        return copy;
    }

    pub fn isEnabled(self: *const MenuItem) bool {
        return self.state != .disabled;
    }
};

/// Menu widget
pub const Menu = struct {
    items: std.ArrayList(MenuItem),
    title: ?[]const u8 = null,
    tearoff: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Menu {
        return .{
            .items = std.ArrayList(MenuItem).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Menu) void {
        self.items.deinit();
    }

    pub fn add(self: *Menu, item: MenuItem) !void {
        try self.items.append(item);
    }

    pub fn addCommand(self: *Menu, label: []const u8, cmd: *const fn () void) !void {
        try self.add(MenuItem.command_item(label, cmd));
    }

    pub fn addSeparator(self: *Menu) !void {
        try self.add(MenuItem.separator());
    }

    pub fn insert(self: *Menu, index: usize, item: MenuItem) !void {
        try self.items.insert(index, item);
    }

    pub fn delete(self: *Menu, index: usize) void {
        if (index < self.items.items.len) {
            _ = self.items.orderedRemove(index);
        }
    }

    pub fn entryCount(self: *const Menu) usize {
        return self.items.items.len;
    }

    pub fn getItem(self: *const Menu, index: usize) ?MenuItem {
        if (index < self.items.items.len) {
            return self.items.items[index];
        }
        return null;
    }

    pub fn invoke(self: *Menu, index: usize) void {
        if (self.getItem(index)) |item| {
            if (item.command) |cmd| {
                cmd();
            }
        }
    }
};

/// Menubar widget
pub const Menubar = struct {
    menus: std.StringHashMap(*Menu),
    order: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Menubar {
        return .{
            .menus = std.StringHashMap(*Menu).init(allocator),
            .order = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Menubar) void {
        self.menus.deinit();
        self.order.deinit();
    }

    pub fn addMenu(self: *Menubar, label: []const u8, menu: *Menu) !void {
        try self.menus.put(label, menu);
        try self.order.append(label);
    }

    pub fn getMenu(self: *Menubar, label: []const u8) ?*Menu {
        return self.menus.get(label);
    }

    pub fn menuCount(self: *const Menubar) usize {
        return self.menus.count();
    }
};

/// Popup menu
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

    pub fn post(self: *PopupMenu, x: i32, y: i32) void {
        self.x = x;
        self.y = y;
        self.visible = true;
    }

    pub fn unpost(self: *PopupMenu) void {
        self.visible = false;
    }
};

fn dummy_cmd() void {}

test "MenuItem creation" {
    const item = MenuItem.command_item("Open", dummy_cmd)
        .withAccelerator("Ctrl+O");

    try std.testing.expectEqualStrings("Open", item.label.?);
    try std.testing.expectEqualStrings("Ctrl+O", item.accelerator.?);
    try std.testing.expect(item.isEnabled());
}

test "MenuItem separator" {
    const sep = MenuItem.separator();
    try std.testing.expectEqual(MenuItemType.separator, sep.type_);
    try std.testing.expect(sep.label == null);
}

test "Menu operations" {
    const allocator = std.testing.allocator;
    var menu = Menu.init(allocator);
    defer menu.deinit();

    try menu.addCommand("New", dummy_cmd);
    try menu.addCommand("Open", dummy_cmd);
    try menu.addSeparator();
    try menu.addCommand("Exit", dummy_cmd);

    try std.testing.expectEqual(@as(usize, 4), menu.entryCount());

    const item = menu.getItem(0);
    try std.testing.expectEqualStrings("New", item.?.label.?);
}

test "Menu delete" {
    const allocator = std.testing.allocator;
    var menu = Menu.init(allocator);
    defer menu.deinit();

    try menu.addCommand("Item1", dummy_cmd);
    try menu.addCommand("Item2", dummy_cmd);
    try std.testing.expectEqual(@as(usize, 2), menu.entryCount());

    menu.delete(0);
    try std.testing.expectEqual(@as(usize, 1), menu.entryCount());
}

test "Menubar" {
    const allocator = std.testing.allocator;
    var menubar = Menubar.init(allocator);
    defer menubar.deinit();

    var file_menu = Menu.init(allocator);
    defer file_menu.deinit();

    try menubar.addMenu("File", &file_menu);
    try std.testing.expectEqual(@as(usize, 1), menubar.menuCount());
    try std.testing.expect(menubar.getMenu("File") != null);
}

test "PopupMenu" {
    const allocator = std.testing.allocator;
    var popup = PopupMenu.init(allocator);
    defer popup.deinit();

    try std.testing.expect(!popup.visible);

    popup.post(100, 200);
    try std.testing.expect(popup.visible);
    try std.testing.expectEqual(@as(i32, 100), popup.x);

    popup.unpost();
    try std.testing.expect(!popup.visible);
}
