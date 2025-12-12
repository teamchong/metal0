//! Python 'turtledemo' module - Turtle graphics demonstration programs
//!
//! Collection of demonstration scripts showing turtle graphics capabilities.
//!
//! Mirrors: CPython Lib/turtledemo/

const std = @import("std");
const turtle = @import("turtle.zig");

// ============================================================================
// Demo Information
// ============================================================================

/// Demo script metadata
pub const DemoInfo = struct {
    name: []const u8,
    description: []const u8,
    category: Category,
};

/// Demo categories
pub const Category = enum {
    basic,
    fractals,
    design,
    games,
    educational,
};

/// List of available demos
pub const demos = &[_]DemoInfo{
    .{
        .name = "bytedesign",
        .description = "Complex turtle graphics design",
        .category = .design,
    },
    .{
        .name = "chaos",
        .description = "Chaos game fractal",
        .category = .fractals,
    },
    .{
        .name = "clock",
        .description = "Analog clock display",
        .category = .educational,
    },
    .{
        .name = "colormixer",
        .description = "RGB color mixing demo",
        .category = .educational,
    },
    .{
        .name = "forest",
        .description = "Random tree forest",
        .category = .design,
    },
    .{
        .name = "fractalcurves",
        .description = "Various fractal curves",
        .category = .fractals,
    },
    .{
        .name = "lindenmayer",
        .description = "L-system fractal generator",
        .category = .fractals,
    },
    .{
        .name = "minimal_hanoi",
        .description = "Tower of Hanoi puzzle",
        .category = .games,
    },
    .{
        .name = "nim",
        .description = "Nim game",
        .category = .games,
    },
    .{
        .name = "paint",
        .description = "Simple paint program",
        .category = .educational,
    },
    .{
        .name = "peace",
        .description = "Peace symbol drawing",
        .category = .basic,
    },
    .{
        .name = "penrose",
        .description = "Penrose tiling",
        .category = .design,
    },
    .{
        .name = "planet_and_moon",
        .description = "Orbital simulation",
        .category = .educational,
    },
    .{
        .name = "rosette",
        .description = "Rosette pattern",
        .category = .design,
    },
    .{
        .name = "round_dance",
        .description = "Dancing turtles",
        .category = .basic,
    },
    .{
        .name = "sorting_animate",
        .description = "Sorting algorithm visualization",
        .category = .educational,
    },
    .{
        .name = "tree",
        .description = "Recursive tree drawing",
        .category = .fractals,
    },
    .{
        .name = "two_canvases",
        .description = "Two canvas demo",
        .category = .basic,
    },
    .{
        .name = "yinyang",
        .description = "Yin-Yang symbol",
        .category = .basic,
    },
};

// ============================================================================
// Demo Implementations (Basic Patterns)
// ============================================================================

/// Draw a square
pub fn square(t: *turtle.Turtle, size: f64) !void {
    for (0..4) |_| {
        try t.forward(size);
        t.right(90);
    }
}

/// Draw a triangle
pub fn triangle(t: *turtle.Turtle, size: f64) !void {
    for (0..3) |_| {
        try t.forward(size);
        t.right(120);
    }
}

/// Draw a star
pub fn star(t: *turtle.Turtle, size: f64, points: u32) !void {
    const angle = 180.0 - (180.0 / @as(f64, @floatFromInt(points)));
    for (0..points) |_| {
        try t.forward(size);
        t.right(angle);
    }
}

/// Draw a spiral
pub fn spiral(t: *turtle.Turtle, initial_size: f64, angle: f64, increment: f64, iterations: u32) !void {
    var size = initial_size;
    for (0..iterations) |_| {
        try t.forward(size);
        t.right(angle);
        size += increment;
    }
}

/// Draw a polygon
pub fn polygon(t: *turtle.Turtle, size: f64, sides: u32) !void {
    const angle = 360.0 / @as(f64, @floatFromInt(sides));
    for (0..sides) |_| {
        try t.forward(size);
        t.right(angle);
    }
}

// ============================================================================
// Fractal Implementations
// ============================================================================

/// Draw a Koch curve segment
pub fn koch(t: *turtle.Turtle, size: f64, depth: u32) !void {
    if (depth == 0) {
        try t.forward(size);
    } else {
        const new_size = size / 3.0;
        try koch(t, new_size, depth - 1);
        t.left(60);
        try koch(t, new_size, depth - 1);
        t.right(120);
        try koch(t, new_size, depth - 1);
        t.left(60);
        try koch(t, new_size, depth - 1);
    }
}

/// Draw a Koch snowflake
pub fn snowflake(t: *turtle.Turtle, size: f64, depth: u32) !void {
    for (0..3) |_| {
        try koch(t, size, depth);
        t.right(120);
    }
}

/// Draw a Sierpinski triangle
pub fn sierpinski(t: *turtle.Turtle, size: f64, depth: u32) !void {
    if (depth == 0) {
        try triangle(t, size);
    } else {
        const half = size / 2.0;
        try sierpinski(t, half, depth - 1);
        try t.forward(half);
        try sierpinski(t, half, depth - 1);
        try t.backward(half);
        t.left(60);
        try t.forward(half);
        t.right(60);
        try sierpinski(t, half, depth - 1);
        t.left(60);
        try t.backward(half);
        t.right(60);
    }
}

/// Draw a simple tree
pub fn tree(t: *turtle.Turtle, size: f64, depth: u32) !void {
    if (depth == 0) return;

    try t.forward(size);
    t.left(30);
    try tree(t, size * 0.7, depth - 1);
    t.right(60);
    try tree(t, size * 0.7, depth - 1);
    t.left(30);
    try t.backward(size);
}

// ============================================================================
// Demo Runner
// ============================================================================

/// Get demo info by name
pub fn getDemoInfo(name: []const u8) ?DemoInfo {
    for (demos) |demo| {
        if (std.mem.eql(u8, demo.name, name)) {
            return demo;
        }
    }
    return null;
}

/// Get demos by category
pub fn getDemosByCategory(allocator: std.mem.Allocator, category: Category) !std.ArrayList(DemoInfo) {
    var result: std.ArrayList(DemoInfo) = .{};
    for (demos) |demo| {
        if (demo.category == category) {
            try result.append(allocator, demo);
        }
    }
    return result;
}

/// Get all demo names
pub fn getDemoNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result: std.ArrayList([]const u8) = .{};
    for (demos) |demo| {
        try result.append(allocator, demo.name);
    }
    return result;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "DemoInfo" {
    const demo = demos[0];
    try std.testing.expectEqualStrings("bytedesign", demo.name);
}

test "getDemoInfo" {
    const info = getDemoInfo("tree");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("tree", info.?.name);
    try std.testing.expectEqual(Category.fractals, info.?.category);
}

test "getDemoInfo unknown" {
    const info = getDemoInfo("nonexistent");
    try std.testing.expect(info == null);
}

test "square" {
    const allocator = std.testing.allocator;
    var t = turtle.Turtle.init(allocator);
    defer t.deinit();

    try square(&t, 100);
    // Should return to starting position
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.y, 0.001);
}

test "triangle" {
    const allocator = std.testing.allocator;
    var t = turtle.Turtle.init(allocator);
    defer t.deinit();

    try triangle(&t, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.y, 0.001);
}

test "polygon" {
    const allocator = std.testing.allocator;
    var t = turtle.Turtle.init(allocator);
    defer t.deinit();

    try polygon(&t, 50, 6); // hexagon
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), t.position.y, 0.001);
}

test "getDemosByCategory" {
    const allocator = std.testing.allocator;
    var fractals = try getDemosByCategory(allocator, .fractals);
    defer fractals.deinit(allocator);

    try std.testing.expect(fractals.items.len > 0);
    for (fractals.items) |demo| {
        try std.testing.expectEqual(Category.fractals, demo.category);
    }
}

test "getDemoNames" {
    const allocator = std.testing.allocator;
    var names = try getDemoNames(allocator);
    defer names.deinit(allocator);

    try std.testing.expectEqual(demos.len, names.items.len);
}
