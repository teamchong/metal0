//! test.test_ttk.test_geometry - Tk geometry manager tests
const std = @import("std");

/// Point in 2D space
pub const Point = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Point {
        return .{ .x = x, .y = y };
    }

    pub fn distance(self: Point, other: Point) f64 {
        const dx: f64 = @floatFromInt(self.x - other.x);
        const dy: f64 = @floatFromInt(self.y - other.y);
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn translate(self: Point, dx: i32, dy: i32) Point {
        return .{ .x = self.x + dx, .y = self.y + dy };
    }
};

/// Rectangle geometry
pub const Rectangle = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn init(x: i32, y: i32, width: u32, height: u32) Rectangle {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn area(self: Rectangle) u64 {
        return @as(u64, self.width) * @as(u64, self.height);
    }

    pub fn contains(self: Rectangle, p: Point) bool {
        return p.x >= self.x and
            p.x < self.x + @as(i32, @intCast(self.width)) and
            p.y >= self.y and
            p.y < self.y + @as(i32, @intCast(self.height));
    }

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return !(self.x + @as(i32, @intCast(self.width)) <= other.x or
            other.x + @as(i32, @intCast(other.width)) <= self.x or
            self.y + @as(i32, @intCast(self.height)) <= other.y or
            other.y + @as(i32, @intCast(other.height)) <= self.y);
    }

    pub fn center(self: Rectangle) Point {
        return .{
            .x = self.x + @as(i32, @intCast(self.width / 2)),
            .y = self.y + @as(i32, @intCast(self.height / 2)),
        };
    }
};

/// Geometry manager types
pub const GeometryManager = enum {
    pack,
    grid,
    place,
};

/// Pack options
pub const PackOptions = struct {
    side: Side = .top,
    fill: Fill = .none,
    expand: bool = false,
    padx: u32 = 0,
    pady: u32 = 0,
    ipadx: u32 = 0,
    ipady: u32 = 0,
    anchor: Anchor = .center,

    pub const Side = enum { top, bottom, left, right };
    pub const Fill = enum { none, x, y, both };
};

/// Grid options
pub const GridOptions = struct {
    row: u32 = 0,
    column: u32 = 0,
    rowspan: u32 = 1,
    columnspan: u32 = 1,
    sticky: []const u8 = "",
    padx: u32 = 0,
    pady: u32 = 0,
    ipadx: u32 = 0,
    ipady: u32 = 0,
};

/// Place options
pub const PlaceOptions = struct {
    x: ?i32 = null,
    y: ?i32 = null,
    relx: f64 = 0.0,
    rely: f64 = 0.0,
    width: ?u32 = null,
    height: ?u32 = null,
    relwidth: ?f64 = null,
    relheight: ?f64 = null,
    anchor: Anchor = .nw,
};

/// Anchor positions
pub const Anchor = enum {
    n, ne, e, se, s, sw, w, nw, center,

    pub fn offset(self: Anchor, width: u32, height: u32) Point {
        return switch (self) {
            .nw => .{ .x = 0, .y = 0 },
            .n => .{ .x = @intCast(width / 2), .y = 0 },
            .ne => .{ .x = @intCast(width), .y = 0 },
            .w => .{ .x = 0, .y = @intCast(height / 2) },
            .center => .{ .x = @intCast(width / 2), .y = @intCast(height / 2) },
            .e => .{ .x = @intCast(width), .y = @intCast(height / 2) },
            .sw => .{ .x = 0, .y = @intCast(height) },
            .s => .{ .x = @intCast(width / 2), .y = @intCast(height) },
            .se => .{ .x = @intCast(width), .y = @intCast(height) },
        };
    }
};

/// Calculate layout for packed widgets
pub fn calculatePackLayout(container: Rectangle, widgets: []const Rectangle, options: PackOptions) []Rectangle {
    _ = container;
    _ = widgets;
    _ = options;
    return &[_]Rectangle{};
}

test "Point creation" {
    const p = Point.init(10, 20);
    try std.testing.expectEqual(@as(i32, 10), p.x);
    try std.testing.expectEqual(@as(i32, 20), p.y);
}

test "Point distance" {
    const p1 = Point.init(0, 0);
    const p2 = Point.init(3, 4);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), p1.distance(p2), 0.001);
}

test "Point translate" {
    const p = Point.init(10, 20);
    const moved = p.translate(5, -5);
    try std.testing.expectEqual(@as(i32, 15), moved.x);
    try std.testing.expectEqual(@as(i32, 15), moved.y);
}

test "Rectangle area" {
    const r = Rectangle.init(0, 0, 10, 20);
    try std.testing.expectEqual(@as(u64, 200), r.area());
}

test "Rectangle contains" {
    const r = Rectangle.init(0, 0, 100, 100);
    try std.testing.expect(r.contains(Point.init(50, 50)));
    try std.testing.expect(!r.contains(Point.init(150, 50)));
}

test "Rectangle intersects" {
    const r1 = Rectangle.init(0, 0, 100, 100);
    const r2 = Rectangle.init(50, 50, 100, 100);
    const r3 = Rectangle.init(200, 200, 50, 50);

    try std.testing.expect(r1.intersects(r2));
    try std.testing.expect(!r1.intersects(r3));
}

test "Rectangle center" {
    const r = Rectangle.init(0, 0, 100, 100);
    const c = r.center();
    try std.testing.expectEqual(@as(i32, 50), c.x);
    try std.testing.expectEqual(@as(i32, 50), c.y);
}

test "Anchor offset" {
    const offset = Anchor.center.offset(100, 100);
    try std.testing.expectEqual(@as(i32, 50), offset.x);
    try std.testing.expectEqual(@as(i32, 50), offset.y);
}
