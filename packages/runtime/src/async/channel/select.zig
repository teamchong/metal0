const std = @import("std");
const Task = @import("../task.zig").Task;
const TaskState = @import("../task.zig").TaskState;

/// Select operation on multiple channels (Go-style)
pub const Select = struct {
    cases: []Case,
    allocator: std.mem.Allocator,

    pub const Case = union(enum) {
        send: SendCase,
        recv: RecvCase,
        default: void,

        pub const SendCase = struct {
            chan: *anyopaque,
            value: *anyopaque,
            value_size: usize,
        };

        pub const RecvCase = struct {
            chan: *anyopaque,
            result_ptr: *anyopaque,
            result_size: usize,
        };
    };

    pub fn init(allocator: std.mem.Allocator, cases: []Case) Select {
        return Select{
            .cases = cases,
            .allocator = allocator,
        };
    }

    /// Execute select (returns index of ready case)
    pub fn execute(self: *Select, current_task: *Task) !usize {
        // First pass: try non-blocking operations
        for (self.cases, 0..) |*case, i| {
            switch (case.*) {
                .send => |*s| {
                    if (self.trySendCase(s)) {
                        return i;
                    }
                },
                .recv => |*r| {
                    if (self.tryRecvCase(r)) {
                        return i;
                    }
                },
                .default => {
                    return i;
                },
            }
        }

        // No default case and nothing ready - block
        if (!self.hasDefault()) {
            return self.blockOnCases(current_task);
        }

        // Has default - should have returned already
        unreachable;
    }

    /// Execute with timeout
    pub fn executeTimeout(self: *Select, current_task: *Task, timeout_ns: u64) !usize {
        _ = current_task;
        const start_time = std.time.nanoTimestamp();

        while (true) {
            // Check timeout
            const now = std.time.nanoTimestamp();
            const elapsed = @as(u64, @intCast(now - start_time));
            if (elapsed >= timeout_ns) {
                return error.Timeout;
            }

            // Try each case
            for (self.cases, 0..) |*case, i| {
                switch (case.*) {
                    .send => |*s| {
                        if (self.trySendCase(s)) {
                            return i;
                        }
                    },
                    .recv => |*r| {
                        if (self.tryRecvCase(r)) {
                            return i;
                        }
                    },
                    .default => {
                        return i;
                    },
                }
            }

            // Nothing ready, yield briefly
            std.atomic.spinLoopHint();
            std.Thread.sleep(1000); // 1 microsecond
        }
    }

    fn hasDefault(self: *Select) bool {
        for (self.cases) |*case| {
            if (case.* == .default) {
                return true;
            }
        }
        return false;
    }

    fn trySendCase(self: *Select, send_case: *const Case.SendCase) bool {
        _ = self;
        _ = send_case;
        // TODO: Implement actual try-send on channel
        // For now, always return false
        return false;
    }

    fn tryRecvCase(self: *Select, recv_case: *const Case.RecvCase) bool {
        _ = self;
        _ = recv_case;
        // TODO: Implement actual try-recv on channel
        // For now, always return false
        return false;
    }

    fn blockOnCases(self: *Select, current_task: *Task) !usize {
        const max_spins: usize = 1000;
        var spin_count: usize = 0;

        while (true) {
            // Try each case again
            for (self.cases, 0..) |*case, i| {
                switch (case.*) {
                    .send => |*s| {
                        if (self.trySendCase(s)) {
                            return i;
                        }
                    },
                    .recv => |*r| {
                        if (self.tryRecvCase(r)) {
                            return i;
                        }
                    },
                    .default => unreachable, // Should have returned earlier
                }
            }

            // Nothing ready - decide whether to spin or yield
            if (spin_count < max_spins) {
                spin_count += 1;
                std.atomic.spinLoopHint();
                continue;
            }

            // Yield to scheduler
            current_task.state = .waiting;
            current_task.recordYield();
            std.Thread.sleep(1000);

            if (current_task.state == .runnable) {
                current_task.state = .running;
            }

            spin_count = 0;
        }
    }
};

/// Helper to create send case
pub fn sendCase(comptime T: type, chan: anytype, value: *T) Select.Case {
    return Select.Case{
        .send = .{
            .chan = @ptrCast(chan),
            .value = @ptrCast(value),
            .value_size = @sizeOf(T),
        },
    };
}

/// Helper to create recv case
pub fn recvCase(comptime T: type, chan: anytype, result: *T) Select.Case {
    return Select.Case{
        .recv = .{
            .chan = @ptrCast(chan),
            .result_ptr = @ptrCast(result),
            .result_size = @sizeOf(T),
        },
    };
}

/// Helper to create default case
pub fn defaultCase() Select.Case {
    return Select.Case{ .default = {} };
}

/// Simplified select for 2 channels
pub fn select2(
    comptime T: type,
    allocator: std.mem.Allocator,
    ch1: anytype,
    ch2: anytype,
    current_task: *Task,
) !struct { usize, T } {
    var result1: T = undefined;
    var result2: T = undefined;

    var cases = [_]Select.Case{
        recvCase(T, ch1, &result1),
        recvCase(T, ch2, &result2),
    };

    var sel = Select.init(allocator, &cases);
    const index = try sel.execute(current_task);

    const value = if (index == 0) result1 else result2;
    return .{ index, value };
}

/// Simplified select for 3 channels
pub fn select3(
    comptime T: type,
    allocator: std.mem.Allocator,
    ch1: anytype,
    ch2: anytype,
    ch3: anytype,
    current_task: *Task,
) !struct { usize, T } {
    var result1: T = undefined;
    var result2: T = undefined;
    var result3: T = undefined;

    var cases = [_]Select.Case{
        recvCase(T, ch1, &result1),
        recvCase(T, ch2, &result2),
        recvCase(T, ch3, &result3),
    };

    var sel = Select.init(allocator, &cases);
    const index = try sel.execute(current_task);

    const value = switch (index) {
        0 => result1,
        1 => result2,
        2 => result3,
        else => unreachable,
    };
    return .{ index, value };
}

/// Simplified select for 4 channels
pub fn select4(
    comptime T: type,
    allocator: std.mem.Allocator,
    ch1: anytype,
    ch2: anytype,
    ch3: anytype,
    ch4: anytype,
    current_task: *Task,
) !struct { usize, T } {
    var result1: T = undefined;
    var result2: T = undefined;
    var result3: T = undefined;
    var result4: T = undefined;

    var cases = [_]Select.Case{
        recvCase(T, ch1, &result1),
        recvCase(T, ch2, &result2),
        recvCase(T, ch3, &result3),
        recvCase(T, ch4, &result4),
    };

    var sel = Select.init(allocator, &cases);
    const index = try sel.execute(current_task);

    const value = switch (index) {
        0 => result1,
        1 => result2,
        2 => result3,
        3 => result4,
        else => unreachable,
    };
    return .{ index, value };
}

/// Select with default (non-blocking)
pub fn selectDefault(
    comptime T: type,
    comptime ChanType: type,
    allocator: std.mem.Allocator,
    channels: []const *ChanType,
    current_task: *Task,
) !?struct { usize, T } {
    var results = try allocator.alloc(T, channels.len);
    defer allocator.free(results);

    var cases = try allocator.alloc(Select.Case, channels.len + 1);
    defer allocator.free(cases);

    // Add recv cases for each channel
    for (channels, 0..) |ch, i| {
        cases[i] = recvCase(T, ch, &results[i]);
    }

    // Add default case
    cases[channels.len] = defaultCase();

    var sel = Select.init(allocator, cases);
    const index = try sel.execute(current_task);

    // If default was selected, return null
    if (index == channels.len) {
        return null;
    }

    return .{ index, results[index] };
}

/// Race multiple channels (return first value)
pub fn race(
    comptime T: type,
    comptime ChanType: type,
    allocator: std.mem.Allocator,
    channels: []const *ChanType,
    current_task: *Task,
) !T {
    var results = try allocator.alloc(T, channels.len);
    defer allocator.free(results);

    var cases = try allocator.alloc(Select.Case, channels.len);
    defer allocator.free(cases);

    for (channels, 0..) |ch, i| {
        cases[i] = recvCase(T, ch, &results[i]);
    }

    var sel = Select.init(allocator, cases);
    const index = try sel.execute(current_task);

    return results[index];
}
