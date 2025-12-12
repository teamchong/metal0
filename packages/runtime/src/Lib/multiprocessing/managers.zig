//! Manager - Process manager for shared objects
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const queues = @import("queues.zig");
const sharedctypes = @import("sharedctypes.zig");

const Queue = queues.Queue;
const Value = sharedctypes.Value;

/// Manager for creating shared objects
pub const Manager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    started: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .started = false,
        };
    }

    pub fn start(self: *Self) void {
        self.started = true;
    }

    pub fn shutdown(self: *Self) void {
        self.started = false;
    }

    /// Create a managed list
    pub fn list(self: *Self, comptime T: type) !std.ArrayList(T) {
        _ = self;
        if (!self.started) return error.ManagerNotStarted;
        return std.ArrayList(T){};
    }

    /// Create a managed dict
    pub fn dict(self: *Self, comptime K: type, comptime V: type) !std.AutoHashMap(K, V) {
        if (!self.started) return error.ManagerNotStarted;
        return std.AutoHashMap(K, V).init(self.allocator);
    }

    /// Create a managed namespace
    pub fn Namespace(self: *Self) !ManagedNamespace {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedNamespace.init(self.allocator);
    }

    /// Create a managed queue
    pub fn queue(self: *Self, comptime T: type, maxsize: usize) !Queue(T) {
        if (!self.started) return error.ManagerNotStarted;
        return Queue(T).init(self.allocator, maxsize);
    }

    /// Create a managed value
    pub fn value(self: *Self, comptime T: type, initial: T) !Value(T) {
        if (!self.started) return error.ManagerNotStarted;
        return Value(T).init(initial);
    }
};

/// Managed namespace for shared attributes
pub const ManagedNamespace = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    attrs: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .attrs = hashmap_helper.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.attrs.deinit();
    }

    pub fn setAttr(self: *Self, name: []const u8, val: []const u8) !void {
        try self.attrs.put(name, val);
    }

    pub fn getAttr(self: *Self, name: []const u8) ?[]const u8 {
        return self.attrs.get(name);
    }

    pub fn delAttr(self: *Self, name: []const u8) void {
        _ = self.attrs.remove(name);
    }
};
