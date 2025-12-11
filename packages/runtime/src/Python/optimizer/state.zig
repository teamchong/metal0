/// Optimizer State Management
/// Maintains optimizer state and coordinates trace recording/optimization

const std = @import("std");
const Allocator = std.mem.Allocator;
const config_mod = @import("config.zig");
const types = @import("types.zig");
const trace_mod = @import("trace.zig");

const OptimizerConfig = config_mod.OptimizerConfig;
const OptimizerStats = types.OptimizerStats;
const MicroOp = types.MicroOp;
const ExecutionTrace = trace_mod.ExecutionTrace;

/// Bytecode optimizer
pub const Optimizer = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Active traces
    traces: std.AutoHashMap(u64, *ExecutionTrace),
    /// Trace recording state
    recording_trace: ?*ExecutionTrace = null,
    /// Next trace ID
    next_trace_id: u64 = 0,
    /// Statistics
    stats: OptimizerStats = .{},
    /// Configuration
    config: OptimizerConfig = .{},

    /// Create new optimizer
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .traces = std.AutoHashMap(u64, *ExecutionTrace).init(allocator),
        };
    }

    /// Free optimizer resources
    pub fn deinit(self: *Self) void {
        var iter = self.traces.valueIterator();
        while (iter.next()) |trace| {
            trace.*.deinit();
            self.allocator.destroy(trace.*);
        }
        self.traces.deinit();
    }

    /// Start recording a new trace
    pub fn startTrace(self: *Self, start_ip: u32) !void {
        if (!self.config.enabled) return;

        const trace = try self.allocator.create(ExecutionTrace);
        trace.* = ExecutionTrace.init(self.allocator, self.next_trace_id, start_ip);
        self.next_trace_id += 1;
        self.recording_trace = trace;
        self.stats.traces_started += 1;
    }

    /// Record instruction in current trace
    pub fn recordInstruction(self: *Self, uop: MicroOp) !void {
        if (self.recording_trace) |trace| {
            if (trace.length() >= self.config.max_trace_length) {
                try self.abortTrace();
                return;
            }
            try trace.addUop(uop);
        }
    }

    /// Finish recording current trace
    pub fn finishTrace(self: *Self) !void {
        if (self.recording_trace) |trace| {
            trace.finalize();
            try self.traces.put(trace.id, trace);
            self.recording_trace = null;
            self.stats.traces_completed += 1;
        }
    }

    /// Abort current trace recording
    pub fn abortTrace(self: *Self) !void {
        if (self.recording_trace) |trace| {
            trace.deinit();
            self.allocator.destroy(trace);
            self.recording_trace = null;
            self.stats.traces_aborted += 1;
        }
    }

    /// Optimize a completed trace
    pub fn optimizeTrace(self: *Self, trace_id: u64) !void {
        if (self.traces.get(trace_id)) |trace| {
            if (trace.optimized) return;

            // Run optimization passes
            try self.constantFold(trace);
            try self.deadCodeEliminate(trace);
            try self.strengthReduce(trace);

            trace.optimized = true;
            self.stats.traces_optimized += 1;
        }
    }

    /// Constant folding pass
    fn constantFold(self: *Self, trace: *ExecutionTrace) !void {
        if (!self.config.const_fold_enabled) return;
        // Fold constant expressions
        _ = trace;
    }

    /// Dead code elimination pass
    fn deadCodeEliminate(self: *Self, trace: *ExecutionTrace) !void {
        if (!self.config.dce_enabled) return;
        // Remove dead code
        _ = trace;
    }

    /// Strength reduction pass
    fn strengthReduce(self: *Self, trace: *ExecutionTrace) !void {
        // Replace expensive operations with cheaper ones
        _ = trace;
    }

    /// Get trace by ID
    pub fn getTrace(self: *Self, trace_id: u64) ?*ExecutionTrace {
        return self.traces.get(trace_id);
    }

    /// Remove trace
    pub fn removeTrace(self: *Self, trace_id: u64) void {
        if (self.traces.fetchSwapRemove(trace_id)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
        }
    }

    /// Get statistics
    pub fn getStats(self: *const Self) OptimizerStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        self.stats = .{};
    }
};
