const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;

pub fn main() !void {
    std.debug.print("Testing SIMD work-stealing scheduler...\n", .{});

    // Test that SIMD functions compile
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var sched = try Scheduler.init(gpa.allocator(), 8);
    defer sched.shutdown();

    std.debug.print("✅ Scheduler created with 8 workers\n", .{});
    std.debug.print("✅ SIMD work-stealing code compiles\n", .{});
}
