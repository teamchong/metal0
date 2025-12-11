//! Python 'tkinter' module - Tk GUI toolkit interface
//!
//! Python interface to Tcl/Tk for building graphical user interfaces.
//!
//! Mirrors: CPython Lib/tkinter/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TkError = error{
    TclError,
    TkNotAvailable,
    WidgetDestroyed,
    InvalidOption,
    OutOfMemory,
};

// ============================================================================
// Constants
// ============================================================================

// Boolean constants
pub const YES = true;
pub const NO = false;
pub const TRUE = true;
pub const FALSE = false;
pub const ON = true;
pub const OFF = false;

// Anchor positions
pub const N = "n";
pub const NE = "ne";
pub const E = "e";
pub const SE = "se";
pub const S = "s";
pub const SW = "sw";
pub const W = "w";
pub const NW = "nw";
pub const CENTER = "center";

// Fill options
pub const NONE = "none";
pub const X = "x";
pub const Y = "y";
pub const BOTH = "both";

// Side options
pub const LEFT = "left";
pub const TOP = "top";
pub const RIGHT = "right";
pub const BOTTOM = "bottom";

// Relief styles
pub const RAISED = "raised";
pub const SUNKEN = "sunken";
pub const FLAT = "flat";
pub const RIDGE = "ridge";
pub const GROOVE = "groove";
pub const SOLID = "solid";

// State values
pub const NORMAL = "normal";
pub const DISABLED = "disabled";
pub const ACTIVE = "active";
pub const HIDDEN = "hidden";

// Selection modes
pub const SINGLE = "single";
pub const BROWSE = "browse";
pub const MULTIPLE = "multiple";
pub const EXTENDED = "extended";

// Wrap modes
pub const CHAR = "char";
pub const WORD = "word";

// Cursor types
pub const INSERT = "insert";
pub const CURRENT = "current";
pub const END = "end";
pub const SEL = "sel";
pub const SEL_FIRST = "sel.first";
pub const SEL_LAST = "sel.last";

// ============================================================================
// Widget Types
// ============================================================================

/// Widget option value (can be string, int, bool, or callback)
pub const OptionValue = union(enum) {
    string: []const u8,
    int: i32,
    boolean: bool,
    callback: ?*const fn () void,
};

/// Base widget class
pub const Widget = struct {
    const Self = @This();

    name: []const u8,
    parent: ?*Widget = null,
    children: std.ArrayList(*Widget),
    allocator: std.mem.Allocator,
    /// Widget options storage
    options: std.StringHashMap(OptionValue),
    /// Event bindings
    bindings: std.StringHashMap(*const fn () void),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return Self{
            .name = name,
            .allocator = allocator,
            .children = std.ArrayList(*Widget).init(allocator),
            .options = std.StringHashMap(OptionValue).init(allocator),
            .bindings = std.StringHashMap(*const fn () void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.children.deinit();
        self.options.deinit();
        self.bindings.deinit();
    }

    /// Configure widget options
    /// Stores options in the widget for later retrieval
    pub fn configure(self: *Self, options: anytype) void {
        const T = @TypeOf(options);
        if (@typeInfo(T) == .@"struct") {
            inline for (std.meta.fields(T)) |field| {
                const value = @field(options, field.name);
                const opt_value: OptionValue = switch (@TypeOf(value)) {
                    []const u8 => .{ .string = value },
                    i32, u32, usize => .{ .int = @intCast(value) },
                    bool => .{ .boolean = value },
                    else => continue,
                };
                self.options.put(field.name, opt_value) catch {};
            }
        }
    }

    // Static buffer for int-to-string conversion
    var int_str_buf: [32]u8 = undefined;

    /// Get widget option value
    pub fn cget(self: *const Self, option: []const u8) ?[]const u8 {
        if (self.options.get(option)) |value| {
            return switch (value) {
                .string => |s| s,
                .int => |i| std.fmt.bufPrint(&int_str_buf, "{d}", .{i}) catch null,
                .boolean => |b| if (b) "1" else "0",
                .callback => null,
            };
        }
        return null;
    }

    /// Get option as integer
    pub fn cgetInt(self: *const Self, option: []const u8) ?i32 {
        if (self.options.get(option)) |value| {
            return switch (value) {
                .int => |i| i,
                .boolean => |b| if (b) @as(i32, 1) else @as(i32, 0),
                else => null,
            };
        }
        return null;
    }

    /// Pack geometry manager
    pub fn pack(self: *Self, options: anytype) void {
        _ = self;
        _ = options;
    }

    /// Grid geometry manager
    pub fn grid(self: *Self, options: anytype) void {
        _ = self;
        _ = options;
    }

    /// Place geometry manager
    pub fn place(self: *Self, options: anytype) void {
        _ = self;
        _ = options;
    }

    /// Bind event handler
    pub fn bind(self: *Self, event: []const u8, handler: anytype) void {
        _ = self;
        _ = event;
        _ = handler;
    }

    /// Destroy widget
    pub fn destroy(self: *Self) void {
        for (self.children.items) |child| {
            child.destroy();
        }
        self.children.clearAndFree();
    }

    /// Focus on widget
    pub fn focus(self: *Self) void {
        _ = self;
    }

    /// Get widget width
    pub fn winfo_width(self: *const Self) u32 {
        _ = self;
        return 0;
    }

    /// Get widget height
    pub fn winfo_height(self: *const Self) u32 {
        _ = self;
        return 0;
    }
};

// ============================================================================
// Tk Root Window
// ============================================================================

/// Root window (main application window)
pub const Tk = struct {
    const Self = @This();

    widget: Widget,
    title_text: []const u8 = "tk",
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .widget = Widget.init(allocator, "."),
        };
    }

    pub fn deinit(self: *Self) void {
        self.widget.deinit();
    }

    /// Set window title
    pub fn title(self: *Self, t: []const u8) void {
        self.title_text = t;
    }

    /// Set window geometry
    pub fn geometry(self: *Self, geo: []const u8) void {
        _ = self;
        _ = geo;
    }

    /// Scheduled callbacks (timer-based)
    scheduled: std.ArrayList(ScheduledCallback) = undefined,

    const ScheduledCallback = struct {
        due_time: i64, // nanoseconds since epoch
        callback: *const fn () void,
    };

    /// Start main event loop
    /// Processes scheduled callbacks and user events
    pub fn mainloop(self: *Self) void {
        self.running = true;
        self.scheduled = std.ArrayList(ScheduledCallback).init(self.widget.allocator);
        defer self.scheduled.deinit();

        // Event loop - process scheduled callbacks
        while (self.running) {
            const now = std.time.nanoTimestamp();

            // Process due callbacks
            var i: usize = 0;
            while (i < self.scheduled.items.len) {
                if (self.scheduled.items[i].due_time <= now) {
                    const cb = self.scheduled.items[i].callback;
                    _ = self.scheduled.swapRemove(i);
                    cb(); // Execute callback
                } else {
                    i += 1;
                }
            }

            // Sleep briefly to avoid busy-waiting (16ms = ~60fps)
            std.time.sleep(16 * std.time.ns_per_ms);

            // Check if quit was requested
            if (!self.running) break;
        }
    }

    /// Quit application
    pub fn quit(self: *Self) void {
        self.running = false;
    }

    /// Destroy window
    pub fn destroy(self: *Self) void {
        self.widget.destroy();
        self.running = false;
    }

    /// Update display
    pub fn update(self: *Self) void {
        _ = self;
    }

    /// Update idle tasks
    pub fn update_idletasks(self: *Self) void {
        _ = self;
    }

    /// Schedule callback after delay (in milliseconds)
    pub fn after(self: *Self, ms: u32, callback: *const fn () void) void {
        const now = std.time.nanoTimestamp();
        const due = now + @as(i64, ms) * std.time.ns_per_ms;
        self.scheduled.append(.{ .due_time = due, .callback = callback }) catch {};
    }

    /// Cancel a scheduled callback (by finding and removing it)
    pub fn after_cancel(self: *Self, callback: *const fn () void) void {
        var i: usize = 0;
        while (i < self.scheduled.items.len) {
            if (self.scheduled.items[i].callback == callback) {
                _ = self.scheduled.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

// ============================================================================
// Common Widgets
// ============================================================================

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

/// Text widget (multi-line text)
pub const Text = struct {
    widget: Widget,
    content: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Widget) Text {
        var t = Text{
            .widget = Widget.init(allocator, "text"),
            .content = std.ArrayList(u8).init(allocator),
        };
        t.widget.parent = parent;
        return t;
    }

    pub fn deinit(self: *Text) void {
        self.content.deinit();
        self.widget.deinit();
    }

    pub fn get(self: *const Text, start: []const u8, end_: []const u8) []const u8 {
        _ = start;
        _ = end_;
        return self.content.items;
    }

    pub fn insert(self: *Text, index: []const u8, text: []const u8) !void {
        _ = index;
        try self.content.appendSlice(text);
    }
};

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

// ============================================================================
// Dialogs
// ============================================================================

pub const messagebox = struct {
    pub fn showinfo(title: []const u8, message: []const u8) void {
        _ = title;
        _ = message;
    }

    pub fn showwarning(title: []const u8, message: []const u8) void {
        _ = title;
        _ = message;
    }

    pub fn showerror(title: []const u8, message: []const u8) void {
        _ = title;
        _ = message;
    }

    pub fn askquestion(title: []const u8, message: []const u8) bool {
        _ = title;
        _ = message;
        return false;
    }

    pub fn askyesno(title: []const u8, message: []const u8) bool {
        _ = title;
        _ = message;
        return false;
    }

    pub fn askokcancel(title: []const u8, message: []const u8) bool {
        _ = title;
        _ = message;
        return false;
    }
};

pub const filedialog = struct {
    pub fn askopenfilename() ?[]const u8 {
        return null;
    }

    pub fn asksaveasfilename() ?[]const u8 {
        return null;
    }

    pub fn askdirectory() ?[]const u8 {
        return null;
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

/// Check if Tk is available
pub fn isTkAvailable() bool {
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqualStrings("n", N);
    try std.testing.expectEqualStrings("center", CENTER);
    try std.testing.expectEqualStrings("raised", RAISED);
    try std.testing.expectEqualStrings("normal", NORMAL);
}

test "Widget init" {
    const allocator = std.testing.allocator;
    var widget = Widget.init(allocator, "test");
    defer widget.deinit();

    try std.testing.expectEqualStrings("test", widget.name);
}

test "Tk init" {
    const allocator = std.testing.allocator;
    var root = Tk.init(allocator);
    defer root.deinit();

    root.title("Test Window");
    try std.testing.expectEqualStrings("Test Window", root.title_text);
}

test "Entry" {
    const allocator = std.testing.allocator;
    var entry = Entry.init(allocator, null);
    defer entry.deinit();

    try entry.insert(0, "hello");
    try std.testing.expectEqualStrings("hello", entry.get());
}

test "isTkAvailable" {
    try std.testing.expect(!isTkAvailable());
}
