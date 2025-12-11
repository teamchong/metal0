/// Optimizer Tests
/// Test suite for bytecode optimizer functionality

const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");
const passes = @import("passes.zig");

const MicroOp = types.MicroOp;
const UopOpcode = types.UopOpcode;
const TypeInfo = types.TypeInfo;
const TypeId = types.TypeId;
const Optimizer = state.Optimizer;

test "trace creation" {
    const allocator = std.testing.allocator;

    var opt = Optimizer.init(allocator);
    defer opt.deinit();

    try opt.startTrace(0);
    try opt.recordInstruction(.{ .opcode = .UOP_LOAD_FAST, .oparg_a = 0 });
    try opt.recordInstruction(.{ .opcode = .UOP_LOAD_FAST, .oparg_a = 1 });
    try opt.recordInstruction(.{ .opcode = .UOP_BINARY_ADD });
    try opt.finishTrace();

    try std.testing.expectEqual(@as(u64, 1), opt.stats.traces_completed);
}

test "trace abort on overflow" {
    const allocator = std.testing.allocator;

    var opt = Optimizer.init(allocator);
    defer opt.deinit();

    opt.config.max_trace_length = 2;

    try opt.startTrace(0);
    try opt.recordInstruction(.{ .opcode = .UOP_LOAD_FAST });
    try opt.recordInstruction(.{ .opcode = .UOP_LOAD_FAST });
    try opt.recordInstruction(.{ .opcode = .UOP_BINARY_ADD }); // Should abort

    try std.testing.expectEqual(@as(u64, 1), opt.stats.traces_aborted);
}

test "trace optimization" {
    const allocator = std.testing.allocator;

    var opt = Optimizer.init(allocator);
    defer opt.deinit();

    try opt.startTrace(100);
    try opt.recordInstruction(.{ .opcode = .UOP_LOAD_CONST, .oparg_a = 42 });
    try opt.recordInstruction(.{ .opcode = .UOP_RETURN });
    try opt.finishTrace();

    try opt.optimizeTrace(0);

    const trace = opt.getTrace(0);
    try std.testing.expect(trace != null);
    try std.testing.expect(trace.?.optimized);
}

test "peephole optimization" {
    const allocator = std.testing.allocator;

    var uops = std.ArrayList(MicroOp).init(allocator);
    defer uops.deinit();

    try uops.append(.{ .opcode = .UOP_LOAD_FAST, .oparg_a = 0 });
    try uops.append(.{ .opcode = .UOP_POP_TOP });
    try uops.append(.{ .opcode = .UOP_LOAD_CONST, .oparg_a = 1 });

    passes.peepholeOptimize(&uops);

    try std.testing.expectEqual(@as(usize, 1), uops.items.len);
    try std.testing.expectEqual(UopOpcode.UOP_LOAD_CONST, uops.items[0].opcode);
}

test "type information" {
    const info = TypeInfo{
        .slot = 0,
        .type_id = .int_type,
        .confidence = 95,
        .observed_count = 100,
    };

    try std.testing.expectEqual(TypeId.int_type, info.type_id);
    try std.testing.expectEqual(@as(u8, 95), info.confidence);
}
