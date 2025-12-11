//! Base widget class for all Tkinter widgets
//!
//! Provides the foundational Widget struct with methods for:
//! - Configuration and option management
//! - Geometry management (pack, grid, place)
//! - Event binding
//! - Widget hierarchy (parent/children)

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

/// Base widget class
pub const Widget = struct {
    const Self = @This();

    name: []const u8,
    parent: ?*Widget = null,
    children: std.ArrayList(*Widget),
    allocator: std.mem.Allocator,
    /// Widget options storage
    options: hashmap_helper.StringHashMap(types.OptionValue),
    /// Event bindings
    bindings: hashmap_helper.StringHashMap(*const fn () void),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return Self{
            .name = name,
            .allocator = allocator,
            .children = std.ArrayList(*Widget).init(allocator),
            .options = hashmap_helper.StringHashMap(types.OptionValue).init(allocator),
            .bindings = hashmap_helper.StringHashMap(*const fn () void).init(allocator),
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
                const opt_value: types.OptionValue = switch (@TypeOf(value)) {
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
