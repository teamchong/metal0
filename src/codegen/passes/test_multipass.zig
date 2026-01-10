//! Integration test for multi-pass build system
//!
//! This test manually constructs IR and runs it through the passes to verify
//! the mutation analysis and emit passes work correctly.

const std = @import("std");
const ir = @import("../ir.zig");
const analysis = @import("analysis.zig");
const emit = @import("emit.zig");

const ZigIR = ir.ZigIR;
const ZigIRExpr = ir.ZigIRExpr;
const ZigIRType = ir.ZigIRType;

/// Test: Variable assigned once should be const
fn testConstVariable(allocator: std.mem.Allocator) !void {
    // Simulate: x = 1
    const int_expr = try allocator.create(ZigIRExpr);
    int_expr.* = .{ .int = 1 };

    const statements = try allocator.alloc(ZigIR, 1);
    statements[0] = .{ .var_decl = .{
        .name = "x",
        .init = int_expr,
    } };

    // Run mutation analysis
    var analysis = try analysis.analyze(statements, allocator);
    defer analysis.deinit();

    // x should be const (assigned once)
    std.debug.assert(analysis.shouldBeConst("x"));
    std.debug.print("testConstVariable: PASSED\n", .{});

    allocator.free(statements);
    allocator.destroy(int_expr);
}

/// Test: Variable assigned twice should be var
fn testMutatedVariable(allocator: std.mem.Allocator) !void {
    // Simulate: x = 1; x = 2
    const int_expr1 = try allocator.create(ZigIRExpr);
    int_expr1.* = .{ .int = 1 };

    const int_expr2 = try allocator.create(ZigIRExpr);
    int_expr2.* = .{ .int = 2 };

    const name_expr = try allocator.create(ZigIRExpr);
    name_expr.* = .{ .name = "x" };

    const statements = try allocator.alloc(ZigIR, 2);
    statements[0] = .{ .var_decl = .{
        .name = "x",
        .init = int_expr1,
    } };
    statements[1] = .{ .assign = .{
        .target = name_expr,
        .value = int_expr2,
    } };

    // Run mutation analysis
    var analysis = try analysis.analyze(statements, allocator);
    defer analysis.deinit();

    // x should be var (assigned twice)
    std.debug.assert(!analysis.shouldBeConst("x"));
    std.debug.print("testMutatedVariable: PASSED\n", .{});

    allocator.free(statements);
    allocator.destroy(int_expr1);
    allocator.destroy(int_expr2);
    allocator.destroy(name_expr);
}

/// Test: Emit pass generates correct code
fn testEmit(allocator: std.mem.Allocator) !void {
    // Create IR for: x = 1; y = 2; y = 3
    const int_expr1 = try allocator.create(ZigIRExpr);
    int_expr1.* = .{ .int = 1 };

    const int_expr2 = try allocator.create(ZigIRExpr);
    int_expr2.* = .{ .int = 2 };

    const int_expr3 = try allocator.create(ZigIRExpr);
    int_expr3.* = .{ .int = 3 };

    const name_y = try allocator.create(ZigIRExpr);
    name_y.* = .{ .name = "y" };

    const statements = try allocator.alloc(ZigIR, 3);
    statements[0] = .{ .var_decl = .{
        .name = "x",
        .init = int_expr1,
    } };
    statements[1] = .{ .var_decl = .{
        .name = "y",
        .init = int_expr2,
    } };
    statements[2] = .{ .assign = .{
        .target = name_y,
        .value = int_expr3,
    } };

    // Run mutation analysis
    var analysis = try analysis.analyze(statements, allocator);
    defer analysis.deinit();

    // Emit to buffer
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try emit.emit(statements, &analysis, &output, allocator);

    // Check output
    const code = output.items;
    std.debug.print("Generated code:\n{s}\n", .{code});

    // x should be const, y should be var
    std.debug.assert(std.mem.indexOf(u8, code, "const x") != null);
    std.debug.assert(std.mem.indexOf(u8, code, "var y") != null);
    std.debug.print("testEmit: PASSED\n", .{});

    allocator.free(statements);
    allocator.destroy(int_expr1);
    allocator.destroy(int_expr2);
    allocator.destroy(int_expr3);
    allocator.destroy(name_y);
}

/// Run all tests
pub fn runTests() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Multi-Pass Build System Tests ===\n\n", .{});

    try testConstVariable(allocator);
    try testMutatedVariable(allocator);
    try testEmit(allocator);

    std.debug.print("\n=== All tests PASSED ===\n", .{});
}

pub fn main() !void {
    try runTests();
}

test "multi-pass integration" {
    try runTests();
}
