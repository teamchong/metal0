//! Builder pooling for reusing ArrayList(u8) builders
//! Inspired by zell's context pooling - reduces allocation overhead in batch compilation
//!
//! Usage:
//!   var pool = BuilderPool.init(allocator);
//!   defer pool.deinit();
//!
//!   const builder = try pool.acquire();
//!   defer pool.release(builder);
//!   // Use builder...
//!   // On release, builder is reset but memory is retained

const std = @import("std");

/// Pool of reusable string builders
/// Avoids repeated ArrayList allocation/deallocation in batch operations
pub const BuilderPool = struct {
    allocator: std.mem.Allocator,
    builders: std.ArrayList(*std.ArrayList(u8)),
    max_capacity: usize,

    const DEFAULT_MAX_CAPACITY = 32; // Pool up to 32 builders

    pub fn init(allocator: std.mem.Allocator) BuilderPool {
        return .{
            .allocator = allocator,
            .builders = std.ArrayList(*std.ArrayList(u8)).init(allocator),
            .max_capacity = DEFAULT_MAX_CAPACITY,
        };
    }

    /// Acquire a builder from the pool (or create new if pool empty)
    pub fn acquire(self: *BuilderPool) !*std.ArrayList(u8) {
        // Check if we have available builder in pool
        if (self.builders.items.len > 0) {
            return self.builders.pop();
        }

        // Create new builder
        const builder = try self.allocator.create(std.ArrayList(u8));
        builder.* = std.ArrayList(u8).init(self.allocator);
        return builder;
    }

    /// Release builder back to pool (resets but retains capacity)
    pub fn release(self: *BuilderPool, builder: *std.ArrayList(u8)) void {
        // Reset but keep capacity
        builder.clearRetainingCapacity();

        // Add back to pool if under capacity
        if (self.builders.items.len < self.max_capacity) {
            self.builders.append(builder) catch {
                // Pool full, destroy builder
                builder.deinit();
                self.allocator.destroy(builder);
            };
        } else {
            // Pool full, destroy builder
            builder.deinit();
            self.allocator.destroy(builder);
        }
    }

    pub fn deinit(self: *BuilderPool) void {
        // Clean up all pooled builders
        for (self.builders.items) |builder| {
            builder.deinit();
            self.allocator.destroy(builder);
        }
        self.builders.deinit();
    }
};
