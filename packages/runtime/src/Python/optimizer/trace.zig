/// Execution Trace Management
/// Handles recording and managing execution traces for optimization

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

const MicroOp = types.MicroOp;
const TypeInfo = types.TypeInfo;
const Guard = types.Guard;

/// Execution trace - a sequence of bytecode instructions observed at runtime
pub const ExecutionTrace = struct {
    const Self = @This();

    /// Trace ID
    id: u64,
    /// Start instruction pointer
    start_ip: u32,
    /// Trace instructions (micro-ops)
    uops: std.ArrayList(MicroOp),
    /// Execution count
    exec_count: u64 = 0,
    /// Is trace complete
    complete: bool = false,
    /// Is trace optimized
    optimized: bool = false,
    /// Compiled code (if JIT enabled)
    compiled_code: ?*anyopaque = null,
    /// Type information collected
    type_info: std.ArrayList(TypeInfo),
    /// Guard conditions
    guards: std.ArrayList(Guard),
    /// Memory allocator
    allocator: Allocator,

    /// Create new trace
    pub fn init(allocator: Allocator, id: u64, start_ip: u32) Self {
        return Self{
            .id = id,
            .start_ip = start_ip,
            .uops = std.ArrayList(MicroOp).init(allocator),
            .type_info = std.ArrayList(TypeInfo).init(allocator),
            .guards = std.ArrayList(Guard).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free trace resources
    pub fn deinit(self: *Self) void {
        self.uops.deinit();
        self.type_info.deinit();
        self.guards.deinit();
    }

    /// Add micro-op to trace
    pub fn addUop(self: *Self, uop: MicroOp) !void {
        try self.uops.append(uop);
    }

    /// Add type information
    pub fn addTypeInfo(self: *Self, info: TypeInfo) !void {
        try self.type_info.append(info);
    }

    /// Add guard condition
    pub fn addGuard(self: *Self, guard: Guard) !void {
        try self.guards.append(guard);
    }

    /// Mark trace as complete
    pub fn finalize(self: *Self) void {
        self.complete = true;
    }

    /// Get trace length
    pub fn length(self: *const Self) usize {
        return self.uops.items.len;
    }
};
