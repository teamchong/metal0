//! test.test_tkinter.test_geometry - Tk geometry tests
//! Tests for tkinter geometry managers: pack, grid, and place

const std = @import("std");
const testing = std.testing;

/// Side for pack geometry manager
pub const Side = enum {
    top,
    bottom,
    left,
    right,

    pub fn toTclString(self: Side) []const u8 {
        return switch (self) {
            .top => "top",
            .bottom => "bottom",
            .left => "left",
            .right => "right",
        };
    }
};

/// Fill mode for pack geometry manager
pub const Fill = enum {
    none,
    x,
    y,
    both,

    pub fn toTclString(self: Fill) []const u8 {
        return switch (self) {
            .none => "none",
            .x => "x",
            .y => "y",
            .both => "both",
        };
    }
};

/// Anchor positions for widgets
pub const Anchor = enum {
    n,
    ne,
    e,
    se,
    s,
    sw,
    w,
    nw,
    center,

    pub fn toTclString(self: Anchor) []const u8 {
        return switch (self) {
            .n => "n",
            .ne => "ne",
            .e => "e",
            .se => "se",
            .s => "s",
            .sw => "sw",
            .w => "w",
            .nw => "nw",
            .center => "center",
        };
    }
};

/// Sticky options for grid geometry manager
pub const Sticky = packed struct {
    n: bool = false,
    s: bool = false,
    e: bool = false,
    w: bool = false,
    _padding: u4 = 0,

    pub fn none() Sticky {
        return .{};
    }

    pub fn nsew() Sticky {
        return .{ .n = true, .s = true, .e = true, .w = true };
    }

    pub fn ns() Sticky {
        return .{ .n = true, .s = true };
    }

    pub fn ew() Sticky {
        return .{ .e = true, .w = true };
    }

    pub fn toTclString(self: Sticky, buf: []u8) []const u8 {
        var pos: usize = 0;
        if (self.n) {
            buf[pos] = 'n';
            pos += 1;
        }
        if (self.s) {
            buf[pos] = 's';
            pos += 1;
        }
        if (self.e) {
            buf[pos] = 'e';
            pos += 1;
        }
        if (self.w) {
            buf[pos] = 'w';
            pos += 1;
        }
        if (pos == 0) return "";
        return buf[0..pos];
    }
};

/// Pack geometry manager options
pub const PackOptions = struct {
    side: Side = .top,
    fill: Fill = .none,
    expand: bool = false,
    anchor: Anchor = .center,
    padx: u32 = 0,
    pady: u32 = 0,
    ipadx: u32 = 0,
    ipady: u32 = 0,
    before: ?[]const u8 = null,
    after: ?[]const u8 = null,
    in_widget: ?[]const u8 = null,
};

/// Grid geometry manager options
pub const GridOptions = struct {
    row: u32 = 0,
    column: u32 = 0,
    rowspan: u32 = 1,
    columnspan: u32 = 1,
    sticky: Sticky = .{},
    padx: u32 = 0,
    pady: u32 = 0,
    ipadx: u32 = 0,
    ipady: u32 = 0,
    in_widget: ?[]const u8 = null,
};

/// Place geometry manager options
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
    bordermode: BorderMode = .inside,
    in_widget: ?[]const u8 = null,

    pub const BorderMode = enum { inside, outside, ignore };
};

/// Grid row/column configuration
pub const GridRowColConfig = struct {
    weight: u32 = 0,
    minsize: u32 = 0,
    pad: u32 = 0,
    uniform: ?[]const u8 = null,
};

/// Geometry info returned by geometry managers
pub const GeometryInfo = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    req_width: u32 = 0,
    req_height: u32 = 0,
};

/// Pack geometry manager
pub const PackManager = struct {
    widgets: std.ArrayList(PackedWidget),
    allocator: std.mem.Allocator,

    const PackedWidget = struct {
        id: []const u8,
        options: PackOptions,
        geometry: GeometryInfo = .{},
    };

    pub fn init(allocator: std.mem.Allocator) PackManager {
        return .{
            .widgets = std.ArrayList(PackedWidget).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackManager) void {
        self.widgets.deinit();
    }

    pub fn pack(self: *PackManager, widget_id: []const u8, options: PackOptions) !void {
        try self.widgets.append(.{ .id = widget_id, .options = options });
    }

    pub fn packForget(self: *PackManager, widget_id: []const u8) void {
        var i: usize = 0;
        while (i < self.widgets.items.len) {
            if (std.mem.eql(u8, self.widgets.items[i].id, widget_id)) {
                _ = self.widgets.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn packInfo(self: *const PackManager, widget_id: []const u8) ?PackOptions {
        for (self.widgets.items) |pw| {
            if (std.mem.eql(u8, pw.id, widget_id)) {
                return pw.options;
            }
        }
        return null;
    }

    pub fn packSlaves(self: *const PackManager) []const PackedWidget {
        return self.widgets.items;
    }

    pub fn packConfigure(self: *PackManager, widget_id: []const u8, options: PackOptions) void {
        for (self.widgets.items) |*pw| {
            if (std.mem.eql(u8, pw.id, widget_id)) {
                pw.options = options;
                return;
            }
        }
    }

    pub fn packPropagate(self: *PackManager, enable: bool) void {
        _ = self;
        _ = enable;
        // Control size propagation
    }

    /// Calculate layout for all packed widgets
    pub fn layout(self: *PackManager, container_width: u32, container_height: u32) void {
        var remaining_x: i32 = 0;
        var remaining_y: i32 = 0;
        var remaining_w: u32 = container_width;
        var remaining_h: u32 = container_height;

        for (self.widgets.items) |*pw| {
            const opts = pw.options;
            const widget_w: u32 = 50; // Default widget size
            const widget_h: u32 = 25;

            switch (opts.side) {
                .top => {
                    pw.geometry.x = remaining_x;
                    pw.geometry.y = remaining_y;
                    pw.geometry.width = if (opts.fill == .x or opts.fill == .both) remaining_w else widget_w;
                    pw.geometry.height = widget_h;
                    remaining_y += @intCast(widget_h + opts.pady * 2);
                    remaining_h -|= widget_h + opts.pady * 2;
                },
                .bottom => {
                    pw.geometry.x = remaining_x;
                    pw.geometry.y = @intCast(remaining_h - widget_h);
                    pw.geometry.width = if (opts.fill == .x or opts.fill == .both) remaining_w else widget_w;
                    pw.geometry.height = widget_h;
                    remaining_h -|= widget_h + opts.pady * 2;
                },
                .left => {
                    pw.geometry.x = remaining_x;
                    pw.geometry.y = remaining_y;
                    pw.geometry.width = widget_w;
                    pw.geometry.height = if (opts.fill == .y or opts.fill == .both) remaining_h else widget_h;
                    remaining_x += @intCast(widget_w + opts.padx * 2);
                    remaining_w -|= widget_w + opts.padx * 2;
                },
                .right => {
                    pw.geometry.x = @intCast(remaining_w - widget_w);
                    pw.geometry.y = remaining_y;
                    pw.geometry.width = widget_w;
                    pw.geometry.height = if (opts.fill == .y or opts.fill == .both) remaining_h else widget_h;
                    remaining_w -|= widget_w + opts.padx * 2;
                },
            }
        }
    }
};

/// Grid geometry manager
pub const GridManager = struct {
    cells: std.ArrayList(GridCell),
    row_config: std.AutoHashMap(u32, GridRowColConfig),
    column_config: std.AutoHashMap(u32, GridRowColConfig),
    allocator: std.mem.Allocator,

    const GridCell = struct {
        id: []const u8,
        options: GridOptions,
        geometry: GeometryInfo = .{},
    };

    pub fn init(allocator: std.mem.Allocator) GridManager {
        return .{
            .cells = std.ArrayList(GridCell).init(allocator),
            .row_config = std.AutoHashMap(u32, GridRowColConfig).init(allocator),
            .column_config = std.AutoHashMap(u32, GridRowColConfig).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GridManager) void {
        self.cells.deinit();
        self.row_config.deinit();
        self.column_config.deinit();
    }

    pub fn grid(self: *GridManager, widget_id: []const u8, options: GridOptions) !void {
        try self.cells.append(.{ .id = widget_id, .options = options });
    }

    pub fn gridForget(self: *GridManager, widget_id: []const u8) void {
        var i: usize = 0;
        while (i < self.cells.items.len) {
            if (std.mem.eql(u8, self.cells.items[i].id, widget_id)) {
                _ = self.cells.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn gridInfo(self: *const GridManager, widget_id: []const u8) ?GridOptions {
        for (self.cells.items) |cell| {
            if (std.mem.eql(u8, cell.id, widget_id)) {
                return cell.options;
            }
        }
        return null;
    }

    pub fn gridSlaves(self: *const GridManager, row: ?u32, column: ?u32) []const GridCell {
        // In a full implementation, this would filter by row/column
        _ = row;
        _ = column;
        return self.cells.items;
    }

    pub fn gridRowconfigure(self: *GridManager, index: u32, config: GridRowColConfig) !void {
        try self.row_config.put(index, config);
    }

    pub fn gridColumnconfigure(self: *GridManager, index: u32, config: GridRowColConfig) !void {
        try self.column_config.put(index, config);
    }

    pub fn gridSize(self: *const GridManager) struct { rows: u32, columns: u32 } {
        var max_row: u32 = 0;
        var max_col: u32 = 0;
        for (self.cells.items) |cell| {
            const row_end = cell.options.row + cell.options.rowspan;
            const col_end = cell.options.column + cell.options.columnspan;
            if (row_end > max_row) max_row = row_end;
            if (col_end > max_col) max_col = col_end;
        }
        return .{ .rows = max_row, .columns = max_col };
    }

    pub fn gridBbox(self: *const GridManager, row: ?u32, column: ?u32, row2: ?u32, column2: ?u32) GeometryInfo {
        _ = self;
        _ = row;
        _ = column;
        _ = row2;
        _ = column2;
        // Return bounding box for grid area
        return .{};
    }

    /// Calculate layout for all grid cells
    pub fn layout(self: *GridManager, container_width: u32, container_height: u32) void {
        const size = self.gridSize();
        if (size.rows == 0 or size.columns == 0) return;

        const cell_width = container_width / size.columns;
        const cell_height = container_height / size.rows;

        for (self.cells.items) |*cell| {
            const opts = cell.options;
            cell.geometry.x = @intCast(opts.column * cell_width + opts.padx);
            cell.geometry.y = @intCast(opts.row * cell_height + opts.pady);
            cell.geometry.width = cell_width * opts.columnspan - opts.padx * 2;
            cell.geometry.height = cell_height * opts.rowspan - opts.pady * 2;
        }
    }
};

/// Place geometry manager
pub const PlaceManager = struct {
    widgets: std.ArrayList(PlacedWidget),
    allocator: std.mem.Allocator,

    const PlacedWidget = struct {
        id: []const u8,
        options: PlaceOptions,
        geometry: GeometryInfo = .{},
    };

    pub fn init(allocator: std.mem.Allocator) PlaceManager {
        return .{
            .widgets = std.ArrayList(PlacedWidget).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PlaceManager) void {
        self.widgets.deinit();
    }

    pub fn place(self: *PlaceManager, widget_id: []const u8, options: PlaceOptions) !void {
        try self.widgets.append(.{ .id = widget_id, .options = options });
    }

    pub fn placeForget(self: *PlaceManager, widget_id: []const u8) void {
        var i: usize = 0;
        while (i < self.widgets.items.len) {
            if (std.mem.eql(u8, self.widgets.items[i].id, widget_id)) {
                _ = self.widgets.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn placeInfo(self: *const PlaceManager, widget_id: []const u8) ?PlaceOptions {
        for (self.widgets.items) |pw| {
            if (std.mem.eql(u8, pw.id, widget_id)) {
                return pw.options;
            }
        }
        return null;
    }

    pub fn placeConfigure(self: *PlaceManager, widget_id: []const u8, options: PlaceOptions) void {
        for (self.widgets.items) |*pw| {
            if (std.mem.eql(u8, pw.id, widget_id)) {
                pw.options = options;
                return;
            }
        }
    }

    pub fn placeSlaves(self: *const PlaceManager) []const PlacedWidget {
        return self.widgets.items;
    }

    /// Calculate layout for all placed widgets
    pub fn layout(self: *PlaceManager, container_width: u32, container_height: u32) void {
        for (self.widgets.items) |*pw| {
            const opts = pw.options;

            // Calculate x position
            var x: i32 = 0;
            if (opts.x) |abs_x| {
                x = abs_x;
            }
            x += @intFromFloat(opts.relx * @as(f64, @floatFromInt(container_width)));

            // Calculate y position
            var y: i32 = 0;
            if (opts.y) |abs_y| {
                y = abs_y;
            }
            y += @intFromFloat(opts.rely * @as(f64, @floatFromInt(container_height)));

            // Calculate width
            var width: u32 = 50; // Default
            if (opts.width) |w| {
                width = w;
            } else if (opts.relwidth) |rw| {
                width = @intFromFloat(rw * @as(f64, @floatFromInt(container_width)));
            }

            // Calculate height
            var height: u32 = 25; // Default
            if (opts.height) |h| {
                height = h;
            } else if (opts.relheight) |rh| {
                height = @intFromFloat(rh * @as(f64, @floatFromInt(container_height)));
            }

            // Apply anchor adjustment
            switch (opts.anchor) {
                .center => {
                    x -= @intCast(width / 2);
                    y -= @intCast(height / 2);
                },
                .n => {
                    x -= @intCast(width / 2);
                },
                .ne => {
                    x -= @intCast(width);
                },
                .e => {
                    x -= @intCast(width);
                    y -= @intCast(height / 2);
                },
                .se => {
                    x -= @intCast(width);
                    y -= @intCast(height);
                },
                .s => {
                    x -= @intCast(width / 2);
                    y -= @intCast(height);
                },
                .sw => {
                    y -= @intCast(height);
                },
                .w => {
                    y -= @intCast(height / 2);
                },
                .nw => {},
            }

            pw.geometry = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            };
        }
    }
};

/// Window geometry string parser (WxH+X+Y format)
pub const WindowGeometry = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    x: ?i32 = null,
    y: ?i32 = null,

    pub fn parse(geometry_str: []const u8) !WindowGeometry {
        var result = WindowGeometry{};
        var i: usize = 0;
        var num_start: usize = 0;
        var parsing_width = true;
        var parsing_x = false;
        var sign: i32 = 1;

        while (i < geometry_str.len) {
            const c = geometry_str[i];
            if (c == 'x' or c == 'X') {
                if (parsing_width and i > num_start) {
                    result.width = std.fmt.parseInt(u32, geometry_str[num_start..i], 10) catch return error.InvalidGeometry;
                    parsing_width = false;
                    num_start = i + 1;
                }
            } else if (c == '+' or c == '-') {
                if (!parsing_width and !parsing_x and i > num_start) {
                    result.height = std.fmt.parseInt(u32, geometry_str[num_start..i], 10) catch return error.InvalidGeometry;
                }
                if (parsing_x and i > num_start) {
                    const val = std.fmt.parseInt(i32, geometry_str[num_start..i], 10) catch return error.InvalidGeometry;
                    result.x = val * sign;
                    parsing_x = false;
                }
                sign = if (c == '-') -1 else 1;
                parsing_x = true;
                num_start = i + 1;
            }
            i += 1;
        }

        // Parse remaining number
        if (i > num_start) {
            if (parsing_x) {
                const val = std.fmt.parseInt(i32, geometry_str[num_start..i], 10) catch return error.InvalidGeometry;
                if (result.x == null) {
                    result.x = val * sign;
                } else {
                    result.y = val * sign;
                }
            } else if (!parsing_width) {
                result.height = std.fmt.parseInt(u32, geometry_str[num_start..i], 10) catch return error.InvalidGeometry;
            }
        }

        return result;
    }

    pub fn format(self: WindowGeometry, buf: []u8) []const u8 {
        var pos: usize = 0;
        if (self.width) |w| {
            const w_str = std.fmt.bufPrint(buf[pos..], "{d}", .{w}) catch return "";
            pos += w_str.len;
        }
        if (self.height) |h| {
            buf[pos] = 'x';
            pos += 1;
            const h_str = std.fmt.bufPrint(buf[pos..], "{d}", .{h}) catch return "";
            pos += h_str.len;
        }
        if (self.x) |x| {
            if (x >= 0) {
                buf[pos] = '+';
                pos += 1;
            }
            const x_str = std.fmt.bufPrint(buf[pos..], "{d}", .{x}) catch return "";
            pos += x_str.len;
        }
        if (self.y) |y| {
            if (y >= 0) {
                buf[pos] = '+';
                pos += 1;
            }
            const y_str = std.fmt.bufPrint(buf[pos..], "{d}", .{y}) catch return "";
            pos += y_str.len;
        }
        return buf[0..pos];
    }
};

/// Wm (window manager) geometry methods
pub const WmGeometry = struct {
    minsize: struct { width: u32, height: u32 } = .{ .width = 1, .height = 1 },
    maxsize: struct { width: u32, height: u32 } = .{ .width = 0, .height = 0 }, // 0 = no limit
    resizable: struct { width: bool, height: bool } = .{ .width = true, .height = true },
    aspect: ?struct { min_numer: u32, min_denom: u32, max_numer: u32, max_denom: u32 } = null,

    pub fn setMinsize(self: *WmGeometry, width: u32, height: u32) void {
        self.minsize = .{ .width = width, .height = height };
    }

    pub fn setMaxsize(self: *WmGeometry, width: u32, height: u32) void {
        self.maxsize = .{ .width = width, .height = height };
    }

    pub fn setResizable(self: *WmGeometry, width: bool, height: bool) void {
        self.resizable = .{ .width = width, .height = height };
    }

    pub fn constrainSize(self: *const WmGeometry, width: u32, height: u32) struct { width: u32, height: u32 } {
        var w = width;
        var h = height;

        w = @max(w, self.minsize.width);
        h = @max(h, self.minsize.height);

        if (self.maxsize.width > 0) {
            w = @min(w, self.maxsize.width);
        }
        if (self.maxsize.height > 0) {
            h = @min(h, self.maxsize.height);
        }

        return .{ .width = w, .height = h };
    }
};

// Tests

test "side_enum" {
    try testing.expectEqualStrings("top", Side.top.toTclString());
    try testing.expectEqualStrings("bottom", Side.bottom.toTclString());
    try testing.expectEqualStrings("left", Side.left.toTclString());
    try testing.expectEqualStrings("right", Side.right.toTclString());
}

test "fill_enum" {
    try testing.expectEqualStrings("none", Fill.none.toTclString());
    try testing.expectEqualStrings("both", Fill.both.toTclString());
}

test "anchor_enum" {
    try testing.expectEqualStrings("center", Anchor.center.toTclString());
    try testing.expectEqualStrings("nw", Anchor.nw.toTclString());
}

test "sticky_options" {
    var buf: [8]u8 = undefined;

    const none = Sticky.none();
    try testing.expectEqualStrings("", none.toTclString(&buf));

    const nsew = Sticky.nsew();
    try testing.expectEqualStrings("nsew", nsew.toTclString(&buf));

    const ns = Sticky.ns();
    try testing.expectEqualStrings("ns", ns.toTclString(&buf));
}

test "pack_manager_basic" {
    var pack = PackManager.init(testing.allocator);
    defer pack.deinit();

    try pack.pack(".label1", .{ .side = .top, .fill = .x });
    try pack.pack(".button1", .{ .side = .bottom });

    const info = pack.packInfo(".label1");
    try testing.expect(info != null);
    try testing.expectEqual(Side.top, info.?.side);
    try testing.expectEqual(Fill.x, info.?.fill);

    try testing.expectEqual(@as(usize, 2), pack.packSlaves().len);
}

test "pack_manager_forget" {
    var pack = PackManager.init(testing.allocator);
    defer pack.deinit();

    try pack.pack(".w1", .{});
    try pack.pack(".w2", .{});
    try testing.expectEqual(@as(usize, 2), pack.packSlaves().len);

    pack.packForget(".w1");
    try testing.expectEqual(@as(usize, 1), pack.packSlaves().len);
}

test "pack_manager_layout" {
    var pack = PackManager.init(testing.allocator);
    defer pack.deinit();

    try pack.pack(".top", .{ .side = .top });
    try pack.pack(".left", .{ .side = .left });

    pack.layout(400, 300);

    const slaves = pack.packSlaves();
    try testing.expectEqual(@as(i32, 0), slaves[0].geometry.x);
    try testing.expectEqual(@as(i32, 0), slaves[0].geometry.y);
}

test "grid_manager_basic" {
    var grid = GridManager.init(testing.allocator);
    defer grid.deinit();

    try grid.grid(".label", .{ .row = 0, .column = 0 });
    try grid.grid(".entry", .{ .row = 0, .column = 1, .sticky = Sticky.ew() });
    try grid.grid(".button", .{ .row = 1, .column = 0, .columnspan = 2 });

    const size = grid.gridSize();
    try testing.expectEqual(@as(u32, 2), size.rows);
    try testing.expectEqual(@as(u32, 2), size.columns);

    const info = grid.gridInfo(".entry");
    try testing.expect(info != null);
    try testing.expectEqual(@as(u32, 1), info.?.column);
}

test "grid_manager_configure" {
    var grid = GridManager.init(testing.allocator);
    defer grid.deinit();

    try grid.gridRowconfigure(0, .{ .weight = 1 });
    try grid.gridColumnconfigure(0, .{ .weight = 1, .minsize = 100 });

    const row_cfg = grid.row_config.get(0);
    try testing.expect(row_cfg != null);
    try testing.expectEqual(@as(u32, 1), row_cfg.?.weight);
}

test "grid_manager_layout" {
    var grid = GridManager.init(testing.allocator);
    defer grid.deinit();

    try grid.grid(".w1", .{ .row = 0, .column = 0 });
    try grid.grid(".w2", .{ .row = 0, .column = 1 });
    try grid.grid(".w3", .{ .row = 1, .column = 0, .columnspan = 2 });

    grid.layout(400, 200);

    const cells = grid.gridSlaves(null, null);
    try testing.expectEqual(@as(usize, 3), cells.len);
}

test "place_manager_basic" {
    var place = PlaceManager.init(testing.allocator);
    defer place.deinit();

    try place.place(".button", .{ .x = 100, .y = 50, .width = 80, .height = 25 });

    const info = place.placeInfo(".button");
    try testing.expect(info != null);
    try testing.expectEqual(@as(?i32, 100), info.?.x);
    try testing.expectEqual(@as(?i32, 50), info.?.y);
}

test "place_manager_relative" {
    var place = PlaceManager.init(testing.allocator);
    defer place.deinit();

    try place.place(".centered", .{
        .relx = 0.5,
        .rely = 0.5,
        .anchor = .center,
    });

    place.layout(400, 300);

    const slaves = place.placeSlaves();
    // Center at 200, 150, then adjust for anchor
    try testing.expectEqual(@as(usize, 1), slaves.len);
}

test "place_manager_forget" {
    var place = PlaceManager.init(testing.allocator);
    defer place.deinit();

    try place.place(".w1", .{});
    try place.place(".w2", .{});

    place.placeForget(".w1");
    try testing.expectEqual(@as(usize, 1), place.placeSlaves().len);
}

test "window_geometry_parse" {
    const geom1 = try WindowGeometry.parse("800x600+100+50");
    try testing.expectEqual(@as(?u32, 800), geom1.width);
    try testing.expectEqual(@as(?u32, 600), geom1.height);
    try testing.expectEqual(@as(?i32, 100), geom1.x);
    try testing.expectEqual(@as(?i32, 50), geom1.y);

    const geom2 = try WindowGeometry.parse("640x480");
    try testing.expectEqual(@as(?u32, 640), geom2.width);
    try testing.expectEqual(@as(?u32, 480), geom2.height);
    try testing.expect(geom2.x == null);
}

test "window_geometry_format" {
    var buf: [64]u8 = undefined;

    const geom = WindowGeometry{ .width = 800, .height = 600, .x = 100, .y = 50 };
    const str = geom.format(&buf);
    try testing.expectEqualStrings("800x600+100+50", str);
}

test "wm_geometry_constraints" {
    var wm = WmGeometry{};
    wm.setMinsize(200, 150);
    wm.setMaxsize(1920, 1080);

    const constrained = wm.constrainSize(100, 100);
    try testing.expectEqual(@as(u32, 200), constrained.width);
    try testing.expectEqual(@as(u32, 150), constrained.height);

    const constrained2 = wm.constrainSize(2000, 2000);
    try testing.expectEqual(@as(u32, 1920), constrained2.width);
    try testing.expectEqual(@as(u32, 1080), constrained2.height);
}

test "wm_geometry_resizable" {
    var wm = WmGeometry{};
    try testing.expect(wm.resizable.width);
    try testing.expect(wm.resizable.height);

    wm.setResizable(false, true);
    try testing.expect(!wm.resizable.width);
    try testing.expect(wm.resizable.height);
}

test "pack_options_defaults" {
    const opts = PackOptions{};
    try testing.expectEqual(Side.top, opts.side);
    try testing.expectEqual(Fill.none, opts.fill);
    try testing.expect(!opts.expand);
}

test "grid_options_span" {
    const opts = GridOptions{ .row = 1, .column = 2, .rowspan = 3, .columnspan = 2 };
    try testing.expectEqual(@as(u32, 1), opts.row);
    try testing.expectEqual(@as(u32, 2), opts.column);
    try testing.expectEqual(@as(u32, 3), opts.rowspan);
    try testing.expectEqual(@as(u32, 2), opts.columnspan);
}

test "place_options_relative" {
    const opts = PlaceOptions{ .relx = 0.5, .rely = 0.5, .relwidth = 0.8, .relheight = 0.6 };
    try testing.expectEqual(@as(f64, 0.5), opts.relx);
    try testing.expectEqual(@as(f64, 0.5), opts.rely);
    try testing.expectEqual(@as(?f64, 0.8), opts.relwidth);
    try testing.expectEqual(@as(?f64, 0.6), opts.relheight);
}
