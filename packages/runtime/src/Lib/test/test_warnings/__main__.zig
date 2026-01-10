//! test.test_warnings - Warning system tests
const std = @import("std");

pub const Warning = struct {
    message: []const u8,
    category: Category,
    filename: []const u8 = "",
    lineno: usize = 0,
    
    pub const Category = enum {
        UserWarning,
        DeprecationWarning,
        PendingDeprecationWarning,
        SyntaxWarning,
        RuntimeWarning,
        FutureWarning,
        ImportWarning,
        UnicodeWarning,
        BytesWarning,
        ResourceWarning,
    };
};

pub const WarningFilter = struct {
    action: Action,
    message: ?[]const u8 = null,
    category: ?Warning.Category = null,
    module: ?[]const u8 = null,
    lineno: usize = 0,
    
    pub const Action = enum { default, error_, ignore, always, module_, once };
};

pub const WarningsModule = struct {
    filters: std.ArrayList(WarningFilter),
    once_registry: std.StringHashMap(bool),
    default_action: WarningFilter.Action = .default,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .filters = std.ArrayList(WarningFilter).init(allocator),
            .once_registry = std.StringHashMap(bool).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.filters.deinit();
        self.once_registry.deinit();
    }
    
    pub fn warn(self: *@This(), message: []const u8, category: Warning.Category) !void {
        const action = self.getAction(message, category);
        switch (action) {
            .error_ => return error.WarningAsError,
            .ignore => {},
            .always => std.debug.print("Warning: {s}\n", .{message}),
            .once => {
                if (!self.once_registry.contains(message)) {
                    try self.once_registry.put(message, true);
                    std.debug.print("Warning: {s}\n", .{message});
                }
            },
            else => std.debug.print("Warning: {s}\n", .{message}),
        }
    }
    
    pub fn filterwarnings(self: *@This(), action: WarningFilter.Action, message: ?[]const u8, category: ?Warning.Category) !void {
        try self.filters.append(.{ .action = action, .message = message, .category = category });
    }
    
    pub fn simplefilter(self: *@This(), action: WarningFilter.Action) !void {
        try self.filters.append(.{ .action = action });
    }
    
    pub fn resetwarnings(self: *@This()) void {
        self.filters.clearRetainingCapacity();
        self.once_registry.clearRetainingCapacity();
    }
    
    fn getAction(self: @This(), message: []const u8, category: Warning.Category) WarningFilter.Action {
        for (self.filters.items) |filter| {
            if (filter.message) |m| {
                if (!std.mem.eql(u8, m, message)) continue;
            }
            if (filter.category) |c| {
                if (c != category) continue;
            }
            return filter.action;
        }
        return self.default_action;
    }
};

pub fn warn(message: []const u8, category: Warning.Category) void {
    std.debug.print("{s}: {s}\n", .{@tagName(category), message});
}

test "warning_init" {
    const w = Warning{ .message = "test", .category = .UserWarning };
    try std.testing.expectEqualStrings("test", w.message);
}

test "warnings_module" {
    var wm = WarningsModule.init(std.testing.allocator);
    defer wm.deinit();
    try wm.simplefilter(.ignore);
    try std.testing.expectEqual(@as(usize, 1), wm.filters.items.len);
}

test "warnings_reset" {
    var wm = WarningsModule.init(std.testing.allocator);
    defer wm.deinit();
    try wm.simplefilter(.always);
    wm.resetwarnings();
    try std.testing.expectEqual(@as(usize, 0), wm.filters.items.len);
}

test "warning_categories" {
    try std.testing.expectEqual(Warning.Category.DeprecationWarning, Warning.Category.DeprecationWarning);
    try std.testing.expect(Warning.Category.UserWarning != Warning.Category.RuntimeWarning);
}
