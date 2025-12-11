/// breakpoint - Breakpoint Management
/// Breakpoint storage, indexing, and condition checking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Breakpoint
// ============================================================================

/// Breakpoint entry
pub const Breakpoint = struct {
    /// Unique ID
    id: u32,
    /// Source file
    file: []const u8,
    /// Line number
    line: u32,
    /// Condition expression (optional)
    condition: ?[]const u8 = null,
    /// Hit count threshold (0 = always)
    hit_count_threshold: u32 = 0,
    /// Current hit count
    hit_count: u32 = 0,
    /// Is enabled
    enabled: bool = true,
    /// Log message instead of breaking
    log_message: ?[]const u8 = null,
};

/// Breakpoint manager
pub const BreakpointManager = struct {
    const Self = @This();

    /// Breakpoints by ID
    breakpoints: std.AutoHashMap(u32, Breakpoint),
    /// Breakpoints by file:line
    by_location: hashmap_helper.StringHashMap(std.ArrayList(u32)),
    /// Next breakpoint ID
    next_id: u32 = 1,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .breakpoints = std.AutoHashMap(u32, Breakpoint).init(allocator),
            .by_location = hashmap_helper.StringHashMap(std.ArrayList(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.by_location.values()) |*list| {
            list.deinit();
        }
        self.by_location.deinit();
        self.breakpoints.deinit();
    }

    /// Add a breakpoint
    pub fn addBreakpoint(self: *Self, file: []const u8, line: u32) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        try self.breakpoints.put(id, .{
            .id = id,
            .file = file,
            .line = line,
        });

        // Index by location
        var buf: [512]u8 = undefined;
        const key = try std.fmt.bufPrint(&buf, "{s}:{d}", .{ file, line });
        const key_copy = try self.allocator.dupe(u8, key);

        const result = try self.by_location.getOrPut(key_copy);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try result.value_ptr.append(id);

        return id;
    }

    /// Remove a breakpoint
    pub fn removeBreakpoint(self: *Self, id: u32) bool {
        return self.breakpoints.remove(id);
    }

    /// Check if location has breakpoint
    pub fn hasBreakpoint(self: *const Self, file: []const u8, line: u32) bool {
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{d}", .{ file, line }) catch return false;
        return self.by_location.contains(key);
    }

    /// Get breakpoint by ID
    pub fn getBreakpoint(self: *Self, id: u32) ?*Breakpoint {
        return self.breakpoints.getPtr(id);
    }

    /// Enable/disable breakpoint
    pub fn setEnabled(self: *Self, id: u32, enabled: bool) void {
        if (self.breakpoints.getPtr(id)) |bp| {
            bp.enabled = enabled;
        }
    }
};
