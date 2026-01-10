//! test.test_ttk.test_events - Tk event handling tests
const std = @import("std");

/// Event types
pub const EventType = enum {
    key_press,
    key_release,
    button_press,
    button_release,
    motion,
    enter,
    leave,
    focus_in,
    focus_out,
    configure,
    destroy,
    map,
    unmap,
    visibility,
    expose,
};

/// Mouse button identifiers
pub const MouseButton = enum(u8) {
    left = 1,
    middle = 2,
    right = 3,
    scroll_up = 4,
    scroll_down = 5,
};

/// Keyboard modifiers
pub const Modifiers = packed struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _padding: u2 = 0,

    pub fn none() Modifiers {
        return .{};
    }

    pub fn hasAny(self: Modifiers) bool {
        return self.shift or self.control or self.alt or self.meta;
    }
};

/// Key event data
pub const KeyEvent = struct {
    keysym: u32,
    keycode: u8,
    char: ?u8 = null,
    modifiers: Modifiers = .{},
    time: u64 = 0,

    pub fn init(keysym: u32, keycode: u8) KeyEvent {
        return .{ .keysym = keysym, .keycode = keycode };
    }

    pub fn withModifiers(self: KeyEvent, mods: Modifiers) KeyEvent {
        var copy = self;
        copy.modifiers = mods;
        return copy;
    }
};

/// Mouse event data
pub const MouseEvent = struct {
    x: i32,
    y: i32,
    x_root: i32 = 0,
    y_root: i32 = 0,
    button: ?MouseButton = null,
    modifiers: Modifiers = .{},
    time: u64 = 0,

    pub fn init(x: i32, y: i32) MouseEvent {
        return .{ .x = x, .y = y };
    }

    pub fn withButton(self: MouseEvent, button: MouseButton) MouseEvent {
        var copy = self;
        copy.button = button;
        return copy;
    }
};

/// Event binding
pub const EventBinding = struct {
    sequence: []const u8,
    callback: *const fn (*anyopaque) void,
    data: ?*anyopaque = null,

    pub fn init(sequence: []const u8, callback: *const fn (*anyopaque) void) EventBinding {
        return .{ .sequence = sequence, .callback = callback };
    }
};

/// Event queue for deferred processing
pub const EventQueue = struct {
    events: std.ArrayList(Event),
    allocator: std.mem.Allocator,

    pub const Event = struct {
        type_: EventType,
        widget_id: u32,
        time: u64,
    };

    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return .{
            .events = std.ArrayList(Event).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.events.deinit();
    }

    pub fn push(self: *EventQueue, event: Event) !void {
        try self.events.append(event);
    }

    pub fn pop(self: *EventQueue) ?Event {
        if (self.events.items.len > 0) {
            return self.events.orderedRemove(0);
        }
        return null;
    }

    pub fn isEmpty(self: *const EventQueue) bool {
        return self.events.items.len == 0;
    }

    pub fn len(self: *const EventQueue) usize {
        return self.events.items.len;
    }
};

/// Virtual event definition
pub const VirtualEvent = struct {
    name: []const u8,
    physical_events: []const []const u8,

    pub fn init(name: []const u8) VirtualEvent {
        return .{ .name = name, .physical_events = &[_][]const u8{} };
    }
};

/// Parse event sequence string
pub fn parseEventSequence(sequence: []const u8) ?EventType {
    if (std.mem.eql(u8, sequence, "<Button-1>")) return .button_press;
    if (std.mem.eql(u8, sequence, "<KeyPress>")) return .key_press;
    if (std.mem.eql(u8, sequence, "<Motion>")) return .motion;
    if (std.mem.eql(u8, sequence, "<Enter>")) return .enter;
    if (std.mem.eql(u8, sequence, "<Leave>")) return .leave;
    if (std.mem.eql(u8, sequence, "<FocusIn>")) return .focus_in;
    if (std.mem.eql(u8, sequence, "<FocusOut>")) return .focus_out;
    return null;
}

test "KeyEvent creation" {
    const event = KeyEvent.init(65, 38);
    try std.testing.expectEqual(@as(u32, 65), event.keysym);
    try std.testing.expectEqual(@as(u8, 38), event.keycode);
}

test "KeyEvent with modifiers" {
    const event = KeyEvent.init(65, 38)
        .withModifiers(.{ .control = true, .shift = true });

    try std.testing.expect(event.modifiers.control);
    try std.testing.expect(event.modifiers.shift);
    try std.testing.expect(!event.modifiers.alt);
}

test "MouseEvent creation" {
    const event = MouseEvent.init(100, 200)
        .withButton(.left);

    try std.testing.expectEqual(@as(i32, 100), event.x);
    try std.testing.expectEqual(@as(i32, 200), event.y);
    try std.testing.expectEqual(MouseButton.left, event.button.?);
}

test "EventQueue" {
    const allocator = std.testing.allocator;
    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    try std.testing.expect(queue.isEmpty());

    try queue.push(.{ .type_ = .button_press, .widget_id = 1, .time = 0 });
    try std.testing.expectEqual(@as(usize, 1), queue.len());

    const event = queue.pop();
    try std.testing.expect(event != null);
    try std.testing.expectEqual(EventType.button_press, event.?.type_);
    try std.testing.expect(queue.isEmpty());
}

test "Modifiers" {
    const none = Modifiers.none();
    try std.testing.expect(!none.hasAny());

    const ctrl_shift = Modifiers{ .control = true, .shift = true };
    try std.testing.expect(ctrl_shift.hasAny());
}

test "parseEventSequence" {
    try std.testing.expectEqual(EventType.button_press, parseEventSequence("<Button-1>").?);
    try std.testing.expectEqual(EventType.key_press, parseEventSequence("<KeyPress>").?);
    try std.testing.expect(parseEventSequence("<Invalid>") == null);
}
