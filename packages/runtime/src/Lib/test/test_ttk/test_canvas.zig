//! test.test_ttk.test_canvas - Tk canvas widget tests
const std = @import("std");

/// Canvas item types
pub const ItemType = enum {
    arc,
    bitmap,
    image,
    line,
    oval,
    polygon,
    rectangle,
    text,
    window,
};

/// Canvas coordinates
pub const Coords = struct {
    points: std.ArrayList(f64),

    pub fn init(allocator: std.mem.Allocator) Coords {
        return .{ .points = std.ArrayList(f64).init(allocator) };
    }

    pub fn deinit(self: *Coords) void {
        self.points.deinit();
    }

    pub fn add(self: *Coords, x: f64, y: f64) !void {
        try self.points.append(x);
        try self.points.append(y);
    }

    pub fn count(self: *const Coords) usize {
        return self.points.items.len / 2;
    }

    pub fn getX(self: *const Coords, index: usize) ?f64 {
        const i = index * 2;
        if (i < self.points.items.len) return self.points.items[i];
        return null;
    }

    pub fn getY(self: *const Coords, index: usize) ?f64 {
        const i = index * 2 + 1;
        if (i < self.points.items.len) return self.points.items[i];
        return null;
    }
};

/// Canvas item options
pub const ItemOptions = struct {
    fill: ?[]const u8 = null,
    outline: ?[]const u8 = null,
    width: f64 = 1.0,
    stipple: ?[]const u8 = null,
    state: ItemState = .normal,
    tags: ?[]const u8 = null,

    pub const ItemState = enum { normal, disabled, hidden };
};

/// Canvas item
pub const CanvasItem = struct {
    id: u32,
    type_: ItemType,
    coords: []f64,
    options: ItemOptions = .{},

    pub fn init(id: u32, item_type: ItemType, coords: []f64) CanvasItem {
        return .{
            .id = id,
            .type_ = item_type,
            .coords = coords,
        };
    }

    pub fn move(self: *CanvasItem, dx: f64, dy: f64) void {
        var i: usize = 0;
        while (i < self.coords.len) : (i += 2) {
            self.coords[i] += dx;
            if (i + 1 < self.coords.len) {
                self.coords[i + 1] += dy;
            }
        }
    }

    pub fn isVisible(self: *const CanvasItem) bool {
        return self.options.state != .hidden;
    }
};

/// Bounding box
pub const BBox = struct {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,

    pub fn init(x1: f64, y1: f64, x2: f64, y2: f64) BBox {
        return .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 };
    }

    pub fn width(self: *const BBox) f64 {
        return self.x2 - self.x1;
    }

    pub fn height(self: *const BBox) f64 {
        return self.y2 - self.y1;
    }

    pub fn contains(self: *const BBox, x: f64, y: f64) bool {
        return x >= self.x1 and x <= self.x2 and y >= self.y1 and y <= self.y2;
    }

    pub fn intersects(self: *const BBox, other: *const BBox) bool {
        return !(self.x2 < other.x1 or other.x2 < self.x1 or
                 self.y2 < other.y1 or other.y2 < self.y1);
    }
};

/// Canvas widget
pub const Canvas = struct {
    next_id: u32 = 1,
    width: u32,
    height: u32,
    bg_color: []const u8 = "white",
    scroll_region: ?BBox = null,
    allocator: std.mem.Allocator,
    items: std.ArrayList(CanvasItem),

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) Canvas {
        return .{
            .width = width,
            .height = height,
            .allocator = allocator,
            .items = std.ArrayList(CanvasItem).init(allocator),
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.items.deinit();
    }

    pub fn createRectangle(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64) !u32 {
        const coords = try self.allocator.alloc(f64, 4);
        coords[0] = x1;
        coords[1] = y1;
        coords[2] = x2;
        coords[3] = y2;

        const id = self.next_id;
        self.next_id += 1;
        try self.items.append(CanvasItem.init(id, .rectangle, coords));
        return id;
    }

    pub fn createLine(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64) !u32 {
        const coords = try self.allocator.alloc(f64, 4);
        coords[0] = x1;
        coords[1] = y1;
        coords[2] = x2;
        coords[3] = y2;

        const id = self.next_id;
        self.next_id += 1;
        try self.items.append(CanvasItem.init(id, .line, coords));
        return id;
    }

    pub fn createOval(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64) !u32 {
        const coords = try self.allocator.alloc(f64, 4);
        coords[0] = x1;
        coords[1] = y1;
        coords[2] = x2;
        coords[3] = y2;

        const id = self.next_id;
        self.next_id += 1;
        try self.items.append(CanvasItem.init(id, .oval, coords));
        return id;
    }

    pub fn delete(self: *Canvas, id: u32) void {
        for (self.items.items, 0..) |item, i| {
            if (item.id == id) {
                _ = self.items.orderedRemove(i);
                return;
            }
        }
    }

    pub fn find(self: *Canvas, id: u32) ?*CanvasItem {
        for (self.items.items) |*item| {
            if (item.id == id) return item;
        }
        return null;
    }

    pub fn itemCount(self: *const Canvas) usize {
        return self.items.items.len;
    }

    pub fn bbox(self: *const Canvas, id: u32) ?BBox {
        for (self.items.items) |item| {
            if (item.id == id and item.coords.len >= 4) {
                return BBox.init(
                    item.coords[0],
                    item.coords[1],
                    item.coords[2],
                    item.coords[3],
                );
            }
        }
        return null;
    }
};

/// Arc style
pub const ArcStyle = enum { pieslice, chord, arc };

/// Line join style
pub const JoinStyle = enum { round, bevel, miter };

/// Line cap style
pub const CapStyle = enum { butt, projecting, round };

test "Coords" {
    const allocator = std.testing.allocator;
    var coords = Coords.init(allocator);
    defer coords.deinit();

    try coords.add(10.0, 20.0);
    try coords.add(30.0, 40.0);

    try std.testing.expectEqual(@as(usize, 2), coords.count());
    try std.testing.expectEqual(@as(f64, 10.0), coords.getX(0).?);
    try std.testing.expectEqual(@as(f64, 20.0), coords.getY(0).?);
}

test "BBox" {
    const box = BBox.init(0.0, 0.0, 100.0, 50.0);
    try std.testing.expectEqual(@as(f64, 100.0), box.width());
    try std.testing.expectEqual(@as(f64, 50.0), box.height());
    try std.testing.expect(box.contains(50.0, 25.0));
    try std.testing.expect(!box.contains(150.0, 25.0));
}

test "BBox intersection" {
    const b1 = BBox.init(0.0, 0.0, 100.0, 100.0);
    const b2 = BBox.init(50.0, 50.0, 150.0, 150.0);
    const b3 = BBox.init(200.0, 200.0, 300.0, 300.0);

    try std.testing.expect(b1.intersects(&b2));
    try std.testing.expect(!b1.intersects(&b3));
}

test "Canvas creation" {
    const allocator = std.testing.allocator;
    var canvas = Canvas.init(allocator, 800, 600);
    defer canvas.deinit();

    try std.testing.expectEqual(@as(u32, 800), canvas.width);
    try std.testing.expectEqual(@as(u32, 600), canvas.height);
}

test "Canvas createRectangle" {
    const allocator = std.testing.allocator;
    var canvas = Canvas.init(allocator, 400, 400);
    defer {
        for (canvas.items.items) |item| {
            allocator.free(item.coords);
        }
        canvas.deinit();
    }

    const id = try canvas.createRectangle(10.0, 10.0, 100.0, 100.0);
    try std.testing.expectEqual(@as(u32, 1), id);
    try std.testing.expectEqual(@as(usize, 1), canvas.itemCount());

    const box = canvas.bbox(id);
    try std.testing.expect(box != null);
    try std.testing.expectEqual(@as(f64, 90.0), box.?.width());
}

test "Canvas item operations" {
    const allocator = std.testing.allocator;
    var canvas = Canvas.init(allocator, 400, 400);
    defer {
        for (canvas.items.items) |item| {
            allocator.free(item.coords);
        }
        canvas.deinit();
    }

    _ = try canvas.createLine(0.0, 0.0, 100.0, 100.0);
    const id2 = try canvas.createOval(50.0, 50.0, 150.0, 150.0);

    try std.testing.expectEqual(@as(usize, 2), canvas.itemCount());

    canvas.delete(id2);
    try std.testing.expectEqual(@as(usize, 1), canvas.itemCount());
}

test "CanvasItem move" {
    var coords = [_]f64{ 0.0, 0.0, 100.0, 100.0 };
    var item = CanvasItem.init(1, .rectangle, &coords);

    item.move(10.0, 20.0);
    try std.testing.expectEqual(@as(f64, 10.0), coords[0]);
    try std.testing.expectEqual(@as(f64, 20.0), coords[1]);
}
