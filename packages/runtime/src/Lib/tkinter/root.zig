//! Tk root window implementation
//!
//! Provides the main application window (Tk) with:
//! - Event loop management (mainloop)
//! - Scheduled callbacks (after/after_cancel)
//! - Window configuration (title, geometry)

const std = @import("std");
const widget_mod = @import("widget.zig");
const Widget = widget_mod.Widget;

/// Root window (main application window)
pub const Tk = struct {
    const Self = @This();

    widget: Widget,
    title_text: []const u8 = "tk",
    running: bool = false,
    /// Scheduled callbacks (timer-based)
    scheduled: std.ArrayList(ScheduledCallback),

    const ScheduledCallback = struct {
        due_time: i64, // nanoseconds since epoch
        callback: *const fn () void,
    };

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

    /// Start main event loop
    /// Processes scheduled callbacks and user events
    pub fn mainloop(self: *Self) void {
        self.running = true;
        self.scheduled = .{};
        defer self.scheduled.deinit(self.widget.allocator);

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
            std.Thread.sleep(16 * std.time.ns_per_ms);

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
        self.scheduled.append(self.widget.allocator, .{ .due_time = due, .callback = callback }) catch unreachable;
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
