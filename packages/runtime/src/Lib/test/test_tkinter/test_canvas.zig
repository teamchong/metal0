//! test.test_tkinter.test_canvas - Tk canvas tests
//! Tests for tkinter Canvas widget drawing and manipulation

const std = @import("std");
const testing = std.testing;

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

    pub fn toTclString(self: ItemType) []const u8 {
        return switch (self) {
            .arc => "arc",
            .bitmap => "bitmap",
            .image => "image",
            .line => "line",
            .oval => "oval",
            .polygon => "polygon",
            .rectangle => "rectangle",
            .text => "text",
            .window => "window",
        };
    }
};

/// Point coordinate
pub const Point = struct {
    x: f64,
    y: f64,

    pub fn init(x: f64, y: f64) Point {
        return .{ .x = x, .y = y };
    }

    pub fn distance(self: Point, other: Point) f64 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn midpoint(self: Point, other: Point) Point {
        return .{
            .x = (self.x + other.x) / 2.0,
            .y = (self.y + other.y) / 2.0,
        };
    }

    pub fn translate(self: Point, dx: f64, dy: f64) Point {
        return .{ .x = self.x + dx, .y = self.y + dy };
    }

    pub fn scale(self: Point, factor: f64, origin: Point) Point {
        return .{
            .x = origin.x + (self.x - origin.x) * factor,
            .y = origin.y + (self.y - origin.y) * factor,
        };
    }
};

/// Bounding box
pub const BoundingBox = struct {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,

    pub fn init(x1: f64, y1: f64, x2: f64, y2: f64) BoundingBox {
        return .{
            .x1 = @min(x1, x2),
            .y1 = @min(y1, y2),
            .x2 = @max(x1, x2),
            .y2 = @max(y1, y2),
        };
    }

    pub fn width(self: BoundingBox) f64 {
        return self.x2 - self.x1;
    }

    pub fn height(self: BoundingBox) f64 {
        return self.y2 - self.y1;
    }

    pub fn center(self: BoundingBox) Point {
        return .{
            .x = (self.x1 + self.x2) / 2.0,
            .y = (self.y1 + self.y2) / 2.0,
        };
    }

    pub fn contains(self: BoundingBox, point: Point) bool {
        return point.x >= self.x1 and point.x <= self.x2 and
            point.y >= self.y1 and point.y <= self.y2;
    }

    pub fn overlaps(self: BoundingBox, other: BoundingBox) bool {
        return !(self.x2 < other.x1 or self.x1 > other.x2 or
            self.y2 < other.y1 or self.y1 > other.y2);
    }

    pub fn expand(self: BoundingBox, amount: f64) BoundingBox {
        return .{
            .x1 = self.x1 - amount,
            .y1 = self.y1 - amount,
            .x2 = self.x2 + amount,
            .y2 = self.y2 + amount,
        };
    }
};

/// Arc style
pub const ArcStyle = enum {
    pieslice,
    chord,
    arc,

    pub fn toTclString(self: ArcStyle) []const u8 {
        return switch (self) {
            .pieslice => "pieslice",
            .chord => "chord",
            .arc => "arc",
        };
    }
};

/// Line cap style
pub const CapStyle = enum {
    butt,
    projecting,
    round,

    pub fn toTclString(self: CapStyle) []const u8 {
        return switch (self) {
            .butt => "butt",
            .projecting => "projecting",
            .round => "round",
        };
    }
};

/// Line join style
pub const JoinStyle = enum {
    miter,
    round,
    bevel,

    pub fn toTclString(self: JoinStyle) []const u8 {
        return switch (self) {
            .miter => "miter",
            .round => "round",
            .bevel => "bevel",
        };
    }
};

/// Arrow style for lines
pub const ArrowStyle = enum {
    none,
    first,
    last,
    both,

    pub fn toTclString(self: ArrowStyle) []const u8 {
        return switch (self) {
            .none => "none",
            .first => "first",
            .last => "last",
            .both => "both",
        };
    }
};

/// Canvas item options
pub const ItemOptions = struct {
    fill: ?[]const u8 = null,
    outline: ?[]const u8 = null,
    width: f64 = 1.0,
    stipple: ?[]const u8 = null,
    state: ItemState = .normal,
    tags: ?[]const []const u8 = null,
    dash: ?[]const u8 = null,
    activefill: ?[]const u8 = null,
    activeoutline: ?[]const u8 = null,
    disabledfill: ?[]const u8 = null,
    disabledoutline: ?[]const u8 = null,

    pub const ItemState = enum { normal, disabled, hidden };
};

/// Line-specific options
pub const LineOptions = struct {
    base: ItemOptions = .{},
    arrow: ArrowStyle = .none,
    arrowshape: ?struct { d1: f64, d2: f64, d3: f64 } = null,
    capstyle: CapStyle = .butt,
    joinstyle: JoinStyle = .round,
    smooth: bool = false,
    splinesteps: u32 = 12,
};

/// Arc-specific options
pub const ArcOptions = struct {
    base: ItemOptions = .{},
    start: f64 = 0.0, // Start angle in degrees
    extent: f64 = 90.0, // Arc extent in degrees
    style: ArcStyle = .pieslice,
};

/// Text-specific options
pub const TextOptions = struct {
    base: ItemOptions = .{},
    anchor: Anchor = .center,
    font: ?[]const u8 = null,
    justify: Justify = .left,
    angle: f64 = 0.0,
    text: []const u8 = "",

    pub const Anchor = enum { n, ne, e, se, s, sw, w, nw, center };
    pub const Justify = enum { left, right, center };
};

/// Canvas item representation
pub const CanvasItem = struct {
    id: u32,
    item_type: ItemType,
    coords: std.ArrayList(f64),
    options: ItemOptions = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: u32, item_type: ItemType) CanvasItem {
        return .{
            .id = id,
            .item_type = item_type,
            .coords = std.ArrayList(f64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CanvasItem) void {
        self.coords.deinit();
    }

    pub fn setCoords(self: *CanvasItem, coords: []const f64) !void {
        self.coords.clearRetainingCapacity();
        try self.coords.appendSlice(coords);
    }

    pub fn getCoords(self: *const CanvasItem) []const f64 {
        return self.coords.items;
    }

    pub fn move(self: *CanvasItem, dx: f64, dy: f64) void {
        var i: usize = 0;
        while (i < self.coords.items.len) {
            self.coords.items[i] += dx; // x
            if (i + 1 < self.coords.items.len) {
                self.coords.items[i + 1] += dy; // y
            }
            i += 2;
        }
    }

    pub fn getBbox(self: *const CanvasItem) ?BoundingBox {
        if (self.coords.items.len < 2) return null;

        var min_x = self.coords.items[0];
        var min_y = self.coords.items[1];
        var max_x = min_x;
        var max_y = min_y;

        var i: usize = 2;
        while (i + 1 < self.coords.items.len) {
            const x = self.coords.items[i];
            const y = self.coords.items[i + 1];
            min_x = @min(min_x, x);
            min_y = @min(min_y, y);
            max_x = @max(max_x, x);
            max_y = @max(max_y, y);
            i += 2;
        }

        return BoundingBox.init(min_x, min_y, max_x, max_y);
    }
};

/// Tag expression for finding canvas items
pub const TagExpr = union(enum) {
    all: void,
    id: u32,
    tag: []const u8,
    above: *TagExpr,
    below: *TagExpr,
    closest: struct { x: f64, y: f64 },
    enclosed: BoundingBox,
    overlapping: BoundingBox,
    withtag: []const u8,
};

/// Canvas widget
pub const Canvas = struct {
    items: std.ArrayList(CanvasItem),
    next_id: u32 = 1,
    allocator: std.mem.Allocator,
    scroll_region: ?BoundingBox = null,
    xview: f64 = 0.0,
    yview: f64 = 0.0,
    background: []const u8 = "white",
    width: u32 = 300,
    height: u32 = 200,
    confine: bool = true,
    tags: std.StringHashMap(std.ArrayList(u32)),

    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{
            .items = std.ArrayList(CanvasItem).init(allocator),
            .allocator = allocator,
            .tags = std.StringHashMap(std.ArrayList(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *Canvas) void {
        for (self.items.items) |*item| {
            item.deinit();
        }
        self.items.deinit();
        var it = self.tags.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.tags.deinit();
    }

    pub fn createLine(self: *Canvas, coords: []const f64, options: LineOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .line);
        try item.setCoords(coords);
        try self.items.append(item);

        return id;
    }

    pub fn createRectangle(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64, options: ItemOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .rectangle);
        try item.setCoords(&[_]f64{ x1, y1, x2, y2 });
        try self.items.append(item);

        return id;
    }

    pub fn createOval(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64, options: ItemOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .oval);
        try item.setCoords(&[_]f64{ x1, y1, x2, y2 });
        try self.items.append(item);

        return id;
    }

    pub fn createPolygon(self: *Canvas, coords: []const f64, options: ItemOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .polygon);
        try item.setCoords(coords);
        try self.items.append(item);

        return id;
    }

    pub fn createArc(self: *Canvas, x1: f64, y1: f64, x2: f64, y2: f64, options: ArcOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .arc);
        try item.setCoords(&[_]f64{ x1, y1, x2, y2 });
        try self.items.append(item);

        return id;
    }

    pub fn createText(self: *Canvas, x: f64, y: f64, options: TextOptions) !u32 {
        _ = options;
        const id = self.next_id;
        self.next_id += 1;

        var item = CanvasItem.init(self.allocator, id, .text);
        try item.setCoords(&[_]f64{ x, y });
        try self.items.append(item);

        return id;
    }

    pub fn delete(self: *Canvas, item_id: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (self.items.items[i].id == item_id) {
                self.items.items[i].deinit();
                _ = self.items.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }

    pub fn deleteAll(self: *Canvas) void {
        for (self.items.items) |*item| {
            item.deinit();
        }
        self.items.clearRetainingCapacity();
    }

    pub fn coords(self: *Canvas, item_id: u32, new_coords: ?[]const f64) !?[]const f64 {
        for (self.items.items) |*item| {
            if (item.id == item_id) {
                if (new_coords) |nc| {
                    try item.setCoords(nc);
                }
                return item.getCoords();
            }
        }
        return null;
    }

    pub fn move(self: *Canvas, item_id: u32, dx: f64, dy: f64) void {
        for (self.items.items) |*item| {
            if (item.id == item_id) {
                item.move(dx, dy);
                return;
            }
        }
    }

    pub fn moveAll(self: *Canvas, dx: f64, dy: f64) void {
        for (self.items.items) |*item| {
            item.move(dx, dy);
        }
    }

    pub fn scale(self: *Canvas, item_id: u32, x_origin: f64, y_origin: f64, x_scale: f64, y_scale: f64) void {
        for (self.items.items) |*item| {
            if (item.id == item_id) {
                var i: usize = 0;
                while (i + 1 < item.coords.items.len) {
                    item.coords.items[i] = x_origin + (item.coords.items[i] - x_origin) * x_scale;
                    item.coords.items[i + 1] = y_origin + (item.coords.items[i + 1] - y_origin) * y_scale;
                    i += 2;
                }
                return;
            }
        }
    }

    pub fn itemcget(self: *const Canvas, item_id: u32, option: []const u8) ?[]const u8 {
        _ = option;
        for (self.items.items) |item| {
            if (item.id == item_id) {
                return item.options.fill;
            }
        }
        return null;
    }

    pub fn itemconfigure(self: *Canvas, item_id: u32, options: ItemOptions) void {
        for (self.items.items) |*item| {
            if (item.id == item_id) {
                item.options = options;
                return;
            }
        }
    }

    pub fn bbox(self: *const Canvas, item_id: u32) ?BoundingBox {
        for (self.items.items) |item| {
            if (item.id == item_id) {
                return item.getBbox();
            }
        }
        return null;
    }

    pub fn findAll(self: *const Canvas) []const CanvasItem {
        return self.items.items;
    }

    pub fn findClosest(self: *const Canvas, x: f64, y: f64) ?u32 {
        const target = Point.init(x, y);
        var closest_id: ?u32 = null;
        var min_dist: f64 = std.math.inf(f64);

        for (self.items.items) |item| {
            if (item.getBbox()) |box| {
                const center = box.center();
                const dist = target.distance(center);
                if (dist < min_dist) {
                    min_dist = dist;
                    closest_id = item.id;
                }
            }
        }

        return closest_id;
    }

    pub fn findEnclosed(self: *const Canvas, box: BoundingBox) std.ArrayList(u32) {
        var result = std.ArrayList(u32).init(self.allocator);
        for (self.items.items) |item| {
            if (item.getBbox()) |item_box| {
                if (box.contains(Point.init(item_box.x1, item_box.y1)) and
                    box.contains(Point.init(item_box.x2, item_box.y2)))
                {
                    result.append(item.id) catch {};
                }
            }
        }
        return result;
    }

    pub fn findOverlapping(self: *const Canvas, box: BoundingBox) std.ArrayList(u32) {
        var result = std.ArrayList(u32).init(self.allocator);
        for (self.items.items) |item| {
            if (item.getBbox()) |item_box| {
                if (box.overlaps(item_box)) {
                    result.append(item.id) catch {};
                }
            }
        }
        return result;
    }

    pub fn raiseItem(self: *Canvas, item_id: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (self.items.items[i].id == item_id and i < self.items.items.len - 1) {
                const item = self.items.orderedRemove(i);
                self.items.append(item) catch {};
                return;
            }
            i += 1;
        }
    }

    pub fn lowerItem(self: *Canvas, item_id: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (self.items.items[i].id == item_id and i > 0) {
                const item = self.items.orderedRemove(i);
                self.items.insert(0, item) catch {};
                return;
            }
            i += 1;
        }
    }

    pub fn addtag(self: *Canvas, tag: []const u8, item_id: u32) !void {
        const result = try self.tags.getOrPut(tag);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try result.value_ptr.append(item_id);
    }

    pub fn dtag(self: *Canvas, tag: []const u8, item_id: u32) void {
        if (self.tags.getPtr(tag)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == item_id) {
                    _ = list.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    pub fn gettags(self: *const Canvas, item_id: u32) std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.tags.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |id| {
                if (id == item_id) {
                    result.append(entry.key_ptr.*) catch {};
                    break;
                }
            }
        }
        return result;
    }

    pub fn canvasx(self: *const Canvas, screen_x: f64) f64 {
        return screen_x + self.xview;
    }

    pub fn canvasy(self: *const Canvas, screen_y: f64) f64 {
        return screen_y + self.yview;
    }

    pub fn xview_moveto(self: *Canvas, fraction: f64) void {
        if (self.scroll_region) |sr| {
            self.xview = sr.x1 + sr.width() * fraction;
        }
    }

    pub fn yview_moveto(self: *Canvas, fraction: f64) void {
        if (self.scroll_region) |sr| {
            self.yview = sr.y1 + sr.height() * fraction;
        }
    }

    pub fn postscript(self: *const Canvas, options: PostscriptOptions) []const u8 {
        _ = self;
        _ = options;
        // Generate PostScript representation
        return "%!PS-Adobe-3.0\n";
    }

    pub const PostscriptOptions = struct {
        colormode: enum { color, gray, mono } = .color,
        file: ?[]const u8 = null,
        height: ?u32 = null,
        width: ?u32 = null,
        pageanchor: []const u8 = "center",
        rotate: bool = false,
        x: f64 = 0,
        y: f64 = 0,
    };
};

// Tests

test "point_operations" {
    const p1 = Point.init(0, 0);
    const p2 = Point.init(3, 4);

    try testing.expectEqual(@as(f64, 5.0), p1.distance(p2));

    const mid = p1.midpoint(p2);
    try testing.expectEqual(@as(f64, 1.5), mid.x);
    try testing.expectEqual(@as(f64, 2.0), mid.y);

    const translated = p1.translate(10, 20);
    try testing.expectEqual(@as(f64, 10), translated.x);
    try testing.expectEqual(@as(f64, 20), translated.y);
}

test "bounding_box" {
    const box = BoundingBox.init(10, 20, 100, 80);

    try testing.expectEqual(@as(f64, 90), box.width());
    try testing.expectEqual(@as(f64, 60), box.height());

    const center = box.center();
    try testing.expectEqual(@as(f64, 55), center.x);
    try testing.expectEqual(@as(f64, 50), center.y);

    try testing.expect(box.contains(Point.init(50, 50)));
    try testing.expect(!box.contains(Point.init(0, 0)));
}

test "bounding_box_overlap" {
    const box1 = BoundingBox.init(0, 0, 100, 100);
    const box2 = BoundingBox.init(50, 50, 150, 150);
    const box3 = BoundingBox.init(200, 200, 300, 300);

    try testing.expect(box1.overlaps(box2));
    try testing.expect(!box1.overlaps(box3));
}

test "item_type_strings" {
    try testing.expectEqualStrings("line", ItemType.line.toTclString());
    try testing.expectEqualStrings("rectangle", ItemType.rectangle.toTclString());
    try testing.expectEqualStrings("oval", ItemType.oval.toTclString());
}

test "arc_style" {
    try testing.expectEqualStrings("pieslice", ArcStyle.pieslice.toTclString());
    try testing.expectEqualStrings("arc", ArcStyle.arc.toTclString());
}

test "canvas_create_line" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createLine(&[_]f64{ 0, 0, 100, 100 }, .{});
    try testing.expectEqual(@as(u32, 1), id);
    try testing.expectEqual(@as(usize, 1), canvas.items.items.len);
}

test "canvas_create_rectangle" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createRectangle(10, 20, 100, 80, .{ .fill = "blue" });
    try testing.expectEqual(@as(u32, 1), id);

    const box = canvas.bbox(id);
    try testing.expect(box != null);
    try testing.expectEqual(@as(f64, 10), box.?.x1);
    try testing.expectEqual(@as(f64, 20), box.?.y1);
}

test "canvas_create_oval" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createOval(0, 0, 100, 100, .{ .fill = "red", .outline = "black" });
    try testing.expectEqual(@as(u32, 1), id);
}

test "canvas_delete" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id1 = try canvas.createRectangle(0, 0, 50, 50, .{});
    const id2 = try canvas.createRectangle(100, 100, 150, 150, .{});
    try testing.expectEqual(@as(usize, 2), canvas.items.items.len);

    canvas.delete(id1);
    try testing.expectEqual(@as(usize, 1), canvas.items.items.len);
    try testing.expectEqual(id2, canvas.items.items[0].id);
}

test "canvas_move" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createRectangle(0, 0, 100, 100, .{});
    canvas.move(id, 50, 50);

    const box = canvas.bbox(id);
    try testing.expect(box != null);
    try testing.expectEqual(@as(f64, 50), box.?.x1);
    try testing.expectEqual(@as(f64, 50), box.?.y1);
}

test "canvas_scale" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createRectangle(0, 0, 100, 100, .{});
    canvas.scale(id, 0, 0, 2.0, 2.0);

    const box = canvas.bbox(id);
    try testing.expect(box != null);
    try testing.expectEqual(@as(f64, 200), box.?.x2);
    try testing.expectEqual(@as(f64, 200), box.?.y2);
}

test "canvas_find_closest" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    _ = try canvas.createRectangle(0, 0, 50, 50, .{});
    const id2 = try canvas.createRectangle(100, 100, 150, 150, .{});

    const closest = canvas.findClosest(120, 120);
    try testing.expectEqual(id2, closest.?);
}

test "canvas_find_overlapping" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id1 = try canvas.createRectangle(0, 0, 100, 100, .{});
    _ = try canvas.createRectangle(200, 200, 300, 300, .{});

    const search_box = BoundingBox.init(50, 50, 150, 150);
    var found = canvas.findOverlapping(search_box);
    defer found.deinit();

    try testing.expectEqual(@as(usize, 1), found.items.len);
    try testing.expectEqual(id1, found.items[0]);
}

test "canvas_tags" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createRectangle(0, 0, 100, 100, .{});
    try canvas.addtag("selected", id);
    try canvas.addtag("movable", id);

    var tags = canvas.gettags(id);
    defer tags.deinit();
    try testing.expectEqual(@as(usize, 2), tags.items.len);
}

test "canvas_raise_lower" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id1 = try canvas.createRectangle(0, 0, 50, 50, .{});
    const id2 = try canvas.createRectangle(25, 25, 75, 75, .{});

    // id1 is at index 0, id2 at index 1
    try testing.expectEqual(id1, canvas.items.items[0].id);

    canvas.raiseItem(id1);
    // After raise, id1 should be at the end
    try testing.expectEqual(id1, canvas.items.items[1].id);

    canvas.lowerItem(id1);
    try testing.expectEqual(id1, canvas.items.items[0].id);
}

test "canvas_coords_update" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    const id = try canvas.createRectangle(0, 0, 100, 100, .{});

    // Get coords
    const c1 = try canvas.coords(id, null);
    try testing.expect(c1 != null);
    try testing.expectEqual(@as(usize, 4), c1.?.len);

    // Set new coords
    _ = try canvas.coords(id, &[_]f64{ 10, 10, 200, 200 });

    const c2 = try canvas.coords(id, null);
    try testing.expectEqual(@as(f64, 10), c2.?[0]);
    try testing.expectEqual(@as(f64, 200), c2.?[2]);
}

test "canvas_view" {
    var canvas = Canvas.init(testing.allocator);
    defer canvas.deinit();

    canvas.scroll_region = BoundingBox.init(0, 0, 1000, 800);
    canvas.xview_moveto(0.5);
    canvas.yview_moveto(0.25);

    try testing.expectEqual(@as(f64, 500), canvas.xview);
    try testing.expectEqual(@as(f64, 200), canvas.yview);

    const canvas_x = canvas.canvasx(100);
    try testing.expectEqual(@as(f64, 600), canvas_x);
}

test "line_options" {
    const opts = LineOptions{
        .arrow = .both,
        .capstyle = .round,
        .smooth = true,
    };

    try testing.expectEqual(ArrowStyle.both, opts.arrow);
    try testing.expectEqual(CapStyle.round, opts.capstyle);
    try testing.expect(opts.smooth);
}
