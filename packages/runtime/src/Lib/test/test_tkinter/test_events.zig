//! test.test_tkinter.test_events - Tk events tests
//! Tests for tkinter event handling, bindings, and virtual events

const std = @import("std");
const testing = std.testing;

/// Event types supported by Tk
pub const EventType = enum(u32) {
    key_press = 2,
    key_release = 3,
    button_press = 4,
    button_release = 5,
    motion = 6,
    enter = 7,
    leave = 8,
    focus_in = 9,
    focus_out = 10,
    keymap = 11,
    expose = 12,
    graphics_expose = 13,
    no_expose = 14,
    visibility = 15,
    create = 16,
    destroy = 17,
    unmap = 18,
    map = 19,
    map_request = 20,
    reparent = 21,
    configure = 22,
    configure_request = 23,
    gravity = 24,
    resize_request = 25,
    circulate = 26,
    circulate_request = 27,
    property = 28,
    selection_clear = 29,
    selection_request = 30,
    selection = 31,
    colormap = 32,
    client_message = 33,
    mapping = 34,
    activate = 36,
    deactivate = 37,
    mouse_wheel = 38,

    pub fn toEventString(self: EventType) []const u8 {
        return switch (self) {
            .key_press => "<KeyPress>",
            .key_release => "<KeyRelease>",
            .button_press => "<ButtonPress>",
            .button_release => "<ButtonRelease>",
            .motion => "<Motion>",
            .enter => "<Enter>",
            .leave => "<Leave>",
            .focus_in => "<FocusIn>",
            .focus_out => "<FocusOut>",
            .configure => "<Configure>",
            .destroy => "<Destroy>",
            .map => "<Map>",
            .unmap => "<Unmap>",
            .mouse_wheel => "<MouseWheel>",
            else => "<Unknown>",
        };
    }
};

/// Mouse button identifiers
pub const MouseButton = enum(u8) {
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,

    pub fn toButtonString(self: MouseButton) []const u8 {
        return switch (self) {
            .left => "Button-1",
            .middle => "Button-2",
            .right => "Button-3",
            .wheel_up => "Button-4",
            .wheel_down => "Button-5",
        };
    }
};

/// Modifier keys for event bindings
pub const Modifiers = packed struct {
    shift: bool = false,
    lock: bool = false,
    control: bool = false,
    mod1: bool = false, // Alt
    mod2: bool = false, // Num Lock
    mod3: bool = false,
    mod4: bool = false, // Super/Windows
    mod5: bool = false,
    button1: bool = false,
    button2: bool = false,
    button3: bool = false,
    button4: bool = false,
    button5: bool = false,
    _padding: u3 = 0,

    pub fn none() Modifiers {
        return .{};
    }

    pub fn ctrl() Modifiers {
        return .{ .control = true };
    }

    pub fn shift() Modifiers {
        return .{ .shift = true };
    }

    pub fn alt() Modifiers {
        return .{ .mod1 = true };
    }

    pub fn ctrlShift() Modifiers {
        return .{ .control = true, .shift = true };
    }

    pub fn toModifierString(self: Modifiers, buf: []u8) []const u8 {
        var pos: usize = 0;
        if (self.control) {
            const s = "Control-";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }
        if (self.shift) {
            const s = "Shift-";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }
        if (self.mod1) {
            const s = "Alt-";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }
        if (self.mod4) {
            const s = "Super-";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }
        return buf[0..pos];
    }

    pub fn hasAnyModifier(self: Modifiers) bool {
        return self.shift or self.control or self.mod1 or self.mod4;
    }
};

/// Key symbol representation
pub const KeySym = struct {
    keysym: u32,
    keysym_string: []const u8,
    char: ?u8 = null,

    pub const Return = KeySym{ .keysym = 0xff0d, .keysym_string = "Return", .char = '\r' };
    pub const Escape = KeySym{ .keysym = 0xff1b, .keysym_string = "Escape", .char = 0x1b };
    pub const Tab = KeySym{ .keysym = 0xff09, .keysym_string = "Tab", .char = '\t' };
    pub const BackSpace = KeySym{ .keysym = 0xff08, .keysym_string = "BackSpace", .char = 0x08 };
    pub const Delete = KeySym{ .keysym = 0xffff, .keysym_string = "Delete" };
    pub const Insert = KeySym{ .keysym = 0xff63, .keysym_string = "Insert" };
    pub const Home = KeySym{ .keysym = 0xff50, .keysym_string = "Home" };
    pub const End = KeySym{ .keysym = 0xff57, .keysym_string = "End" };
    pub const Prior = KeySym{ .keysym = 0xff55, .keysym_string = "Prior" }; // Page Up
    pub const Next = KeySym{ .keysym = 0xff56, .keysym_string = "Next" }; // Page Down
    pub const Left = KeySym{ .keysym = 0xff51, .keysym_string = "Left" };
    pub const Up = KeySym{ .keysym = 0xff52, .keysym_string = "Up" };
    pub const Right = KeySym{ .keysym = 0xff53, .keysym_string = "Right" };
    pub const Down = KeySym{ .keysym = 0xff54, .keysym_string = "Down" };
    pub const Space = KeySym{ .keysym = 0x20, .keysym_string = "space", .char = ' ' };

    pub fn fromChar(c: u8) KeySym {
        return .{ .keysym = c, .keysym_string = &[_]u8{c}, .char = c };
    }

    pub fn isModifier(self: KeySym) bool {
        return self.keysym >= 0xffe1 and self.keysym <= 0xffee;
    }

    pub fn isPrintable(self: KeySym) bool {
        if (self.char) |c| {
            return c >= 0x20 and c <= 0x7e;
        }
        return false;
    }
};

/// Event object containing all event information
pub const Event = struct {
    event_type: EventType,
    widget: []const u8 = "",
    x: i32 = 0,
    y: i32 = 0,
    x_root: i32 = 0,
    y_root: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    keysym: ?KeySym = null,
    keycode: u32 = 0,
    state: Modifiers = .{},
    button: ?MouseButton = null,
    delta: i32 = 0, // Mouse wheel delta
    time: u64 = 0,
    serial: u64 = 0,
    send_event: bool = false,
    focus: bool = false,

    pub fn init(event_type: EventType) Event {
        return .{ .event_type = event_type };
    }

    pub fn withPosition(self: Event, x: i32, y: i32) Event {
        var e = self;
        e.x = x;
        e.y = y;
        return e;
    }

    pub fn withRootPosition(self: Event, x_root: i32, y_root: i32) Event {
        var e = self;
        e.x_root = x_root;
        e.y_root = y_root;
        return e;
    }

    pub fn withButton(self: Event, button: MouseButton) Event {
        var e = self;
        e.button = button;
        return e;
    }

    pub fn withKey(self: Event, keysym: KeySym) Event {
        var e = self;
        e.keysym = keysym;
        return e;
    }

    pub fn withModifiers(self: Event, modifiers: Modifiers) Event {
        var e = self;
        e.state = modifiers;
        return e;
    }

    pub fn getChar(self: *const Event) ?u8 {
        if (self.keysym) |ks| {
            return ks.char;
        }
        return null;
    }
};

/// Event binding pattern
pub const BindingPattern = struct {
    event_type: EventType,
    modifiers: Modifiers = .{},
    detail: ?union(enum) {
        button: MouseButton,
        keysym: KeySym,
    } = null,

    pub fn parse(pattern: []const u8) !BindingPattern {
        var result = BindingPattern{ .event_type = .key_press };

        // Simple parser for common patterns
        if (std.mem.eql(u8, pattern, "<Button-1>")) {
            return .{ .event_type = .button_press, .detail = .{ .button = .left } };
        }
        if (std.mem.eql(u8, pattern, "<Button-2>")) {
            return .{ .event_type = .button_press, .detail = .{ .button = .middle } };
        }
        if (std.mem.eql(u8, pattern, "<Button-3>")) {
            return .{ .event_type = .button_press, .detail = .{ .button = .right } };
        }
        if (std.mem.eql(u8, pattern, "<Return>")) {
            return .{ .event_type = .key_press, .detail = .{ .keysym = KeySym.Return } };
        }
        if (std.mem.eql(u8, pattern, "<Escape>")) {
            return .{ .event_type = .key_press, .detail = .{ .keysym = KeySym.Escape } };
        }
        if (std.mem.eql(u8, pattern, "<Control-c>")) {
            return .{ .event_type = .key_press, .modifiers = Modifiers.ctrl(), .detail = .{ .keysym = KeySym.fromChar('c') } };
        }
        if (std.mem.eql(u8, pattern, "<Control-v>")) {
            return .{ .event_type = .key_press, .modifiers = Modifiers.ctrl(), .detail = .{ .keysym = KeySym.fromChar('v') } };
        }
        if (std.mem.eql(u8, pattern, "<Enter>")) {
            return .{ .event_type = .enter };
        }
        if (std.mem.eql(u8, pattern, "<Leave>")) {
            return .{ .event_type = .leave };
        }
        if (std.mem.eql(u8, pattern, "<FocusIn>")) {
            return .{ .event_type = .focus_in };
        }
        if (std.mem.eql(u8, pattern, "<FocusOut>")) {
            return .{ .event_type = .focus_out };
        }
        if (std.mem.eql(u8, pattern, "<Motion>")) {
            return .{ .event_type = .motion };
        }

        return result;
    }

    pub fn matches(self: BindingPattern, event: Event) bool {
        if (self.event_type != event.event_type) return false;

        // Check modifiers
        if (self.modifiers.hasAnyModifier()) {
            if (self.modifiers.control != event.state.control) return false;
            if (self.modifiers.shift != event.state.shift) return false;
            if (self.modifiers.mod1 != event.state.mod1) return false;
        }

        // Check detail
        if (self.detail) |detail| {
            switch (detail) {
                .button => |b| {
                    if (event.button) |eb| {
                        if (b != eb) return false;
                    } else return false;
                },
                .keysym => |k| {
                    if (event.keysym) |ek| {
                        if (k.keysym != ek.keysym) return false;
                    } else return false;
                },
            }
        }

        return true;
    }
};

/// Event handler callback type
pub const EventCallback = *const fn (*Event) void;

/// Binding entry for event dispatch
pub const Binding = struct {
    pattern: BindingPattern,
    callback: EventCallback,
    add: bool = false, // If true, add to existing bindings instead of replacing
    widget_id: ?[]const u8 = null,
    tag: ?[]const u8 = null,
};

/// Event manager for handling bindings and dispatch
pub const EventManager = struct {
    bindings: std.ArrayList(Binding),
    virtual_events: std.StringHashMap(std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
    event_queue: std.ArrayList(Event),
    processing: bool = false,

    pub fn init(allocator: std.mem.Allocator) EventManager {
        return .{
            .bindings = std.ArrayList(Binding).init(allocator),
            .virtual_events = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .allocator = allocator,
            .event_queue = std.ArrayList(Event).init(allocator),
        };
    }

    pub fn deinit(self: *EventManager) void {
        self.bindings.deinit();
        var it = self.virtual_events.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.virtual_events.deinit();
        self.event_queue.deinit();
    }

    pub fn bind(self: *EventManager, pattern_str: []const u8, callback: EventCallback) !void {
        const pattern = try BindingPattern.parse(pattern_str);
        try self.bindings.append(.{ .pattern = pattern, .callback = callback });
    }

    pub fn bindWidget(self: *EventManager, widget_id: []const u8, pattern_str: []const u8, callback: EventCallback) !void {
        const pattern = try BindingPattern.parse(pattern_str);
        try self.bindings.append(.{ .pattern = pattern, .callback = callback, .widget_id = widget_id });
    }

    pub fn unbind(self: *EventManager, pattern_str: []const u8) !void {
        const pattern = try BindingPattern.parse(pattern_str);
        var i: usize = 0;
        while (i < self.bindings.items.len) {
            if (self.bindings.items[i].pattern.event_type == pattern.event_type) {
                _ = self.bindings.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn dispatch(self: *EventManager, event: *Event) void {
        for (self.bindings.items) |binding| {
            if (binding.widget_id) |wid| {
                if (!std.mem.eql(u8, wid, event.widget)) continue;
            }
            if (binding.pattern.matches(event.*)) {
                binding.callback(event);
            }
        }
    }

    pub fn queueEvent(self: *EventManager, event: Event) !void {
        try self.event_queue.append(event);
    }

    pub fn processQueue(self: *EventManager) void {
        if (self.processing) return;
        self.processing = true;
        defer self.processing = false;

        while (self.event_queue.items.len > 0) {
            var event = self.event_queue.orderedRemove(0);
            self.dispatch(&event);
        }
    }

    pub fn addVirtualEvent(self: *EventManager, name: []const u8, sequences: []const []const u8) !void {
        var list = std.ArrayList([]const u8).init(self.allocator);
        for (sequences) |seq| {
            try list.append(seq);
        }
        try self.virtual_events.put(name, list);
    }

    pub fn getVirtualEvent(self: *EventManager, name: []const u8) ?[]const []const u8 {
        if (self.virtual_events.get(name)) |list| {
            return list.items;
        }
        return null;
    }
};

/// Virtual event definitions (common ones)
pub const VirtualEvents = struct {
    pub const Cut = "<<Cut>>";
    pub const Copy = "<<Copy>>";
    pub const Paste = "<<Paste>>";
    pub const Undo = "<<Undo>>";
    pub const Redo = "<<Redo>>";
    pub const SelectAll = "<<SelectAll>>";
    pub const Clear = "<<Clear>>";
    pub const PrevWindow = "<<PrevWindow>>";
    pub const NextWindow = "<<NextWindow>>";

    pub fn getSequences(name: []const u8) ?[]const []const u8 {
        if (std.mem.eql(u8, name, Cut)) {
            return &[_][]const u8{ "<Control-x>", "<Shift-Delete>" };
        }
        if (std.mem.eql(u8, name, Copy)) {
            return &[_][]const u8{ "<Control-c>", "<Control-Insert>" };
        }
        if (std.mem.eql(u8, name, Paste)) {
            return &[_][]const u8{ "<Control-v>", "<Shift-Insert>" };
        }
        if (std.mem.eql(u8, name, Undo)) {
            return &[_][]const u8{"<Control-z>"};
        }
        if (std.mem.eql(u8, name, Redo)) {
            return &[_][]const u8{ "<Control-y>", "<Control-Shift-z>" };
        }
        if (std.mem.eql(u8, name, SelectAll)) {
            return &[_][]const u8{"<Control-a>"};
        }
        return null;
    }
};

/// Event generation for testing
pub const EventGenerator = struct {
    target_widget: []const u8,
    serial: u64 = 0,

    pub fn init(widget: []const u8) EventGenerator {
        return .{ .target_widget = widget };
    }

    pub fn generateKeyPress(self: *EventGenerator, keysym: KeySym, modifiers: Modifiers) Event {
        self.serial += 1;
        return Event{
            .event_type = .key_press,
            .widget = self.target_widget,
            .keysym = keysym,
            .state = modifiers,
            .serial = self.serial,
            .time = @intCast(std.time.milliTimestamp() catch 0),
        };
    }

    pub fn generateKeyRelease(self: *EventGenerator, keysym: KeySym, modifiers: Modifiers) Event {
        self.serial += 1;
        return Event{
            .event_type = .key_release,
            .widget = self.target_widget,
            .keysym = keysym,
            .state = modifiers,
            .serial = self.serial,
            .time = @intCast(std.time.milliTimestamp() catch 0),
        };
    }

    pub fn generateButtonPress(self: *EventGenerator, button: MouseButton, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .button_press,
            .widget = self.target_widget,
            .button = button,
            .x = x,
            .y = y,
            .serial = self.serial,
            .time = @intCast(std.time.milliTimestamp() catch 0),
        };
    }

    pub fn generateButtonRelease(self: *EventGenerator, button: MouseButton, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .button_release,
            .widget = self.target_widget,
            .button = button,
            .x = x,
            .y = y,
            .serial = self.serial,
            .time = @intCast(std.time.milliTimestamp() catch 0),
        };
    }

    pub fn generateMotion(self: *EventGenerator, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .motion,
            .widget = self.target_widget,
            .x = x,
            .y = y,
            .serial = self.serial,
            .time = @intCast(std.time.milliTimestamp() catch 0),
        };
    }

    pub fn generateEnter(self: *EventGenerator, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .enter,
            .widget = self.target_widget,
            .x = x,
            .y = y,
            .serial = self.serial,
        };
    }

    pub fn generateLeave(self: *EventGenerator, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .leave,
            .widget = self.target_widget,
            .x = x,
            .y = y,
            .serial = self.serial,
        };
    }

    pub fn generateConfigure(self: *EventGenerator, width: u32, height: u32) Event {
        self.serial += 1;
        return Event{
            .event_type = .configure,
            .widget = self.target_widget,
            .width = width,
            .height = height,
            .serial = self.serial,
        };
    }

    pub fn generateMouseWheel(self: *EventGenerator, delta: i32, x: i32, y: i32) Event {
        self.serial += 1;
        return Event{
            .event_type = .mouse_wheel,
            .widget = self.target_widget,
            .delta = delta,
            .x = x,
            .y = y,
            .serial = self.serial,
        };
    }
};

/// Focus manager for widget focus handling
pub const FocusManager = struct {
    current_focus: ?[]const u8 = null,
    focus_order: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FocusManager {
        return .{
            .focus_order = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FocusManager) void {
        self.focus_order.deinit();
    }

    pub fn addWidget(self: *FocusManager, widget_id: []const u8) !void {
        try self.focus_order.append(widget_id);
    }

    pub fn removeWidget(self: *FocusManager, widget_id: []const u8) void {
        var i: usize = 0;
        while (i < self.focus_order.items.len) {
            if (std.mem.eql(u8, self.focus_order.items[i], widget_id)) {
                _ = self.focus_order.orderedRemove(i);
                if (self.current_focus) |cf| {
                    if (std.mem.eql(u8, cf, widget_id)) {
                        self.current_focus = null;
                    }
                }
            } else {
                i += 1;
            }
        }
    }

    pub fn focusSet(self: *FocusManager, widget_id: []const u8) void {
        for (self.focus_order.items) |wid| {
            if (std.mem.eql(u8, wid, widget_id)) {
                self.current_focus = wid;
                return;
            }
        }
    }

    pub fn focusNext(self: *FocusManager) ?[]const u8 {
        if (self.focus_order.items.len == 0) return null;

        if (self.current_focus) |cf| {
            for (self.focus_order.items, 0..) |wid, i| {
                if (std.mem.eql(u8, wid, cf)) {
                    const next_idx = (i + 1) % self.focus_order.items.len;
                    self.current_focus = self.focus_order.items[next_idx];
                    return self.current_focus;
                }
            }
        }

        self.current_focus = self.focus_order.items[0];
        return self.current_focus;
    }

    pub fn focusPrev(self: *FocusManager) ?[]const u8 {
        if (self.focus_order.items.len == 0) return null;

        if (self.current_focus) |cf| {
            for (self.focus_order.items, 0..) |wid, i| {
                if (std.mem.eql(u8, wid, cf)) {
                    const prev_idx = if (i == 0) self.focus_order.items.len - 1 else i - 1;
                    self.current_focus = self.focus_order.items[prev_idx];
                    return self.current_focus;
                }
            }
        }

        self.current_focus = self.focus_order.items[self.focus_order.items.len - 1];
        return self.current_focus;
    }

    pub fn getFocus(self: *const FocusManager) ?[]const u8 {
        return self.current_focus;
    }
};

// Tests

test "event_type_strings" {
    try testing.expectEqualStrings("<KeyPress>", EventType.key_press.toEventString());
    try testing.expectEqualStrings("<ButtonPress>", EventType.button_press.toEventString());
    try testing.expectEqualStrings("<Enter>", EventType.enter.toEventString());
    try testing.expectEqualStrings("<Configure>", EventType.configure.toEventString());
}

test "mouse_button" {
    try testing.expectEqualStrings("Button-1", MouseButton.left.toButtonString());
    try testing.expectEqualStrings("Button-3", MouseButton.right.toButtonString());
}

test "modifiers" {
    const ctrl = Modifiers.ctrl();
    try testing.expect(ctrl.control);
    try testing.expect(!ctrl.shift);

    const ctrlShift = Modifiers.ctrlShift();
    try testing.expect(ctrlShift.control);
    try testing.expect(ctrlShift.shift);
    try testing.expect(ctrlShift.hasAnyModifier());

    const none = Modifiers.none();
    try testing.expect(!none.hasAnyModifier());
}

test "keysym_special_keys" {
    try testing.expectEqualStrings("Return", KeySym.Return.keysym_string);
    try testing.expectEqual(@as(?u8, '\r'), KeySym.Return.char);
    try testing.expect(!KeySym.Return.isModifier());
    try testing.expect(KeySym.Space.isPrintable());
    try testing.expect(!KeySym.Delete.isPrintable());
}

test "keysym_from_char" {
    const a = KeySym.fromChar('a');
    try testing.expectEqual(@as(u32, 'a'), a.keysym);
    try testing.expectEqual(@as(?u8, 'a'), a.char);
    try testing.expect(a.isPrintable());
}

test "event_creation" {
    var event = Event.init(.button_press);
    event = event.withPosition(100, 200);
    event = event.withButton(.left);

    try testing.expectEqual(EventType.button_press, event.event_type);
    try testing.expectEqual(@as(i32, 100), event.x);
    try testing.expectEqual(@as(i32, 200), event.y);
    try testing.expectEqual(MouseButton.left, event.button.?);
}

test "event_with_key" {
    var event = Event.init(.key_press);
    event = event.withKey(KeySym.Return);
    event = event.withModifiers(Modifiers.ctrl());

    try testing.expectEqual(EventType.key_press, event.event_type);
    try testing.expectEqual(@as(?u8, '\r'), event.getChar());
    try testing.expect(event.state.control);
}

test "binding_pattern_parse" {
    const button1 = try BindingPattern.parse("<Button-1>");
    try testing.expectEqual(EventType.button_press, button1.event_type);

    const ret = try BindingPattern.parse("<Return>");
    try testing.expectEqual(EventType.key_press, ret.event_type);

    const ctrlC = try BindingPattern.parse("<Control-c>");
    try testing.expect(ctrlC.modifiers.control);
}

test "binding_pattern_matches" {
    const pattern = try BindingPattern.parse("<Button-1>");
    const event = Event.init(.button_press).withButton(.left);
    try testing.expect(pattern.matches(event));

    const wrong_button = Event.init(.button_press).withButton(.right);
    try testing.expect(!pattern.matches(wrong_button));
}

test "event_manager_bind_dispatch" {
    var handler_called = false;
    const handler = struct {
        fn call(e: *Event) void {
            _ = e;
            @as(*bool, @ptrFromInt(@intFromPtr(&handler_called))).* = true;
        }
    }.call;
    _ = handler;

    var manager = EventManager.init(testing.allocator);
    defer manager.deinit();

    try manager.bind("<Button-1>", @ptrCast(&struct {
        fn dummy(_: *Event) void {}
    }.dummy));

    try testing.expectEqual(@as(usize, 1), manager.bindings.items.len);
}

test "event_generator" {
    var gen = EventGenerator.init(".button1");

    const key_event = gen.generateKeyPress(KeySym.Return, Modifiers.none());
    try testing.expectEqual(EventType.key_press, key_event.event_type);
    try testing.expectEqualStrings(".button1", key_event.widget);
    try testing.expectEqual(@as(u64, 1), key_event.serial);

    const click_event = gen.generateButtonPress(.left, 50, 75);
    try testing.expectEqual(EventType.button_press, click_event.event_type);
    try testing.expectEqual(@as(i32, 50), click_event.x);
    try testing.expectEqual(@as(u64, 2), click_event.serial);
}

test "focus_manager" {
    var focus = FocusManager.init(testing.allocator);
    defer focus.deinit();

    try focus.addWidget(".entry1");
    try focus.addWidget(".entry2");
    try focus.addWidget(".button1");

    try testing.expect(focus.getFocus() == null);

    focus.focusSet(".entry1");
    try testing.expectEqualStrings(".entry1", focus.getFocus().?);

    const next = focus.focusNext();
    try testing.expectEqualStrings(".entry2", next.?);

    const prev = focus.focusPrev();
    try testing.expectEqualStrings(".entry1", prev.?);
}

test "focus_manager_wrap" {
    var focus = FocusManager.init(testing.allocator);
    defer focus.deinit();

    try focus.addWidget(".w1");
    try focus.addWidget(".w2");

    focus.focusSet(".w2");
    const next = focus.focusNext();
    try testing.expectEqualStrings(".w1", next.?); // Wraps around
}

test "virtual_events" {
    const copy_seqs = VirtualEvents.getSequences(VirtualEvents.Copy);
    try testing.expect(copy_seqs != null);
    try testing.expectEqual(@as(usize, 2), copy_seqs.?.len);
    try testing.expectEqualStrings("<Control-c>", copy_seqs.?[0]);

    const unknown = VirtualEvents.getSequences("<<Unknown>>");
    try testing.expect(unknown == null);
}

test "event_manager_virtual_events" {
    var manager = EventManager.init(testing.allocator);
    defer manager.deinit();

    try manager.addVirtualEvent("<<MyEvent>>", &[_][]const u8{ "<Control-m>", "<Alt-m>" });

    const seqs = manager.getVirtualEvent("<<MyEvent>>");
    try testing.expect(seqs != null);
    try testing.expectEqual(@as(usize, 2), seqs.?.len);
}

test "event_queue" {
    var manager = EventManager.init(testing.allocator);
    defer manager.deinit();

    try manager.queueEvent(Event.init(.button_press));
    try manager.queueEvent(Event.init(.button_release));

    try testing.expectEqual(@as(usize, 2), manager.event_queue.items.len);

    manager.processQueue();
    try testing.expectEqual(@as(usize, 0), manager.event_queue.items.len);
}

test "modifier_string" {
    var buf: [64]u8 = undefined;

    const ctrl = Modifiers.ctrl();
    const ctrl_str = ctrl.toModifierString(&buf);
    try testing.expectEqualStrings("Control-", ctrl_str);

    const ctrlShift = Modifiers.ctrlShift();
    const cs_str = ctrlShift.toModifierString(&buf);
    try testing.expectEqualStrings("Control-Shift-", cs_str);
}
