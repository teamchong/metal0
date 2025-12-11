/// context - Analysis Context
/// Main analysis driver and warning system

const std = @import("std");
const Allocator = std.mem.Allocator;
const DataFlowState = @import("dataflow.zig").DataFlowState;
const EscapeAnalyzer = @import("escape.zig").EscapeAnalyzer;

// ============================================================================
// Analysis Driver
// ============================================================================

/// Analysis context
pub const AnalysisContext = struct {
    const Self = @This();

    allocator: Allocator,
    dataflow: DataFlowState,
    escape: EscapeAnalyzer,
    warnings: std.ArrayList(AnalysisWarning),

    /// Create new context
    pub fn init(allocator: Allocator, num_locals: usize) !Self {
        return Self{
            .allocator = allocator,
            .dataflow = try DataFlowState.init(allocator, num_locals, 0),
            .escape = EscapeAnalyzer.init(allocator),
            .warnings = .{},
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.dataflow.deinit();
        self.escape.deinit();
        self.warnings.deinit(self.allocator);
    }

    /// Add warning
    pub fn warn(self: *Self, kind: WarningKind, location: u32, message: []const u8) !void {
        try self.warnings.append(self.allocator, .{
            .kind = kind,
            .location = location,
            .message = message,
        });
    }
};

/// Analysis warning
pub const AnalysisWarning = struct {
    kind: WarningKind,
    location: u32,
    message: []const u8,
};

/// Warning types
pub const WarningKind = enum {
    type_mismatch,
    possible_null,
    dead_code,
    unused_variable,
    possible_overflow,
    escape_detected,
};
