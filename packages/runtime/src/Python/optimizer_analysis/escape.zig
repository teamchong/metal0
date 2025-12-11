/// escape - Escape Analysis
/// Tracks object lifetimes and determines if objects can be stack allocated

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Escape Analysis
// ============================================================================

/// Escape state for an object
pub const EscapeState = enum(u8) {
    /// Object does not escape
    no_escape,
    /// Object escapes to caller via argument
    arg_escape,
    /// Object escapes to caller via return
    return_escape,
    /// Object escapes globally
    global_escape,
};

/// Escape analysis result
pub const EscapeInfo = struct {
    /// Object ID
    object_id: u32,
    /// Escape state
    state: EscapeState,
    /// Allocation site
    alloc_site: u32,
    /// Is object scalar replaceable
    scalar_replaceable: bool,

    /// Can object be stack allocated
    pub fn canStackAllocate(self: *const EscapeInfo) bool {
        return self.state == .no_escape or self.state == .arg_escape;
    }
};

/// Escape analyzer
pub const EscapeAnalyzer = struct {
    const Self = @This();

    allocator: Allocator,
    escape_info: std.AutoHashMap(u32, EscapeInfo),
    next_object_id: u32 = 0,

    /// Create new analyzer
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .escape_info = std.AutoHashMap(u32, EscapeInfo).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.escape_info.deinit();
    }

    /// Track new allocation
    pub fn trackAllocation(self: *Self, alloc_site: u32) !u32 {
        const id = self.next_object_id;
        self.next_object_id += 1;

        try self.escape_info.put(id, .{
            .object_id = id,
            .state = .no_escape,
            .alloc_site = alloc_site,
            .scalar_replaceable = true,
        });

        return id;
    }

    /// Mark object as escaping
    pub fn markEscape(self: *Self, object_id: u32, state: EscapeState) void {
        if (self.escape_info.getPtr(object_id)) |info| {
            // Escalate escape state
            if (@intFromEnum(state) > @intFromEnum(info.state)) {
                info.state = state;
            }
            if (state == .global_escape) {
                info.scalar_replaceable = false;
            }
        }
    }

    /// Get escape info for object
    pub fn getInfo(self: *const Self, object_id: u32) ?EscapeInfo {
        return self.escape_info.get(object_id);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "escape analysis" {
    const allocator = std.testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    const obj_id = try analyzer.trackAllocation(0);
    try std.testing.expectEqual(EscapeState.no_escape, analyzer.getInfo(obj_id).?.state);

    analyzer.markEscape(obj_id, .arg_escape);
    try std.testing.expectEqual(EscapeState.arg_escape, analyzer.getInfo(obj_id).?.state);
    try std.testing.expect(analyzer.getInfo(obj_id).?.canStackAllocate());

    analyzer.markEscape(obj_id, .global_escape);
    try std.testing.expectEqual(EscapeState.global_escape, analyzer.getInfo(obj_id).?.state);
    try std.testing.expect(!analyzer.getInfo(obj_id).?.canStackAllocate());
}
