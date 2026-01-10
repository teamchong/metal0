//! test.test_ttk.test_images - Tk image handling tests
const std = @import("std");

/// Image types
pub const ImageType = enum {
    photo,
    bitmap,

    pub fn toString(self: ImageType) []const u8 {
        return switch (self) {
            .photo => "photo",
            .bitmap => "bitmap",
        };
    }
};

/// Pixel format
pub const PixelFormat = enum {
    rgb,
    rgba,
    grayscale,

    pub fn bytesPerPixel(self: PixelFormat) usize {
        return switch (self) {
            .rgb => 3,
            .rgba => 4,
            .grayscale => 1,
        };
    }
};

/// Color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn grayscale(value: u8) Color {
        return .{ .r = value, .g = value, .b = value };
    }

    pub fn toHex(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn equals(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and
            self.b == other.b and self.a == other.a;
    }
};

/// Photo image (full-color)
pub const PhotoImage = struct {
    name: []const u8,
    width: u32,
    height: u32,
    data: ?[]u8 = null,
    format: PixelFormat = .rgba,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, width: u32, height: u32) !PhotoImage {
        const bpp = PixelFormat.rgba.bytesPerPixel();
        const data = try allocator.alloc(u8, width * height * bpp);
        @memset(data, 0);

        return .{
            .name = name,
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PhotoImage) void {
        if (self.data) |d| {
            self.allocator.free(d);
        }
    }

    pub fn put(self: *PhotoImage, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        if (self.data) |data| {
            const bpp = self.format.bytesPerPixel();
            const offset = (y * self.width + x) * bpp;
            if (offset + bpp <= data.len) {
                data[offset] = color.r;
                if (bpp > 1) data[offset + 1] = color.g;
                if (bpp > 2) data[offset + 2] = color.b;
                if (bpp > 3) data[offset + 3] = color.a;
            }
        }
    }

    pub fn get(self: *const PhotoImage, x: u32, y: u32) ?Color {
        if (x >= self.width or y >= self.height) return null;
        if (self.data) |data| {
            const bpp = self.format.bytesPerPixel();
            const offset = (y * self.width + x) * bpp;
            if (offset + bpp <= data.len) {
                return Color{
                    .r = data[offset],
                    .g = if (bpp > 1) data[offset + 1] else data[offset],
                    .b = if (bpp > 2) data[offset + 2] else data[offset],
                    .a = if (bpp > 3) data[offset + 3] else 255,
                };
            }
        }
        return null;
    }

    pub fn blank(self: *PhotoImage) void {
        if (self.data) |data| {
            @memset(data, 0);
        }
    }

    pub fn copy(self: *PhotoImage, source: *const PhotoImage) void {
        if (self.data != null and source.data != null and
            self.width == source.width and self.height == source.height) {
            @memcpy(self.data.?, source.data.?);
        }
    }
};

/// Bitmap image (two-color)
pub const BitmapImage = struct {
    name: []const u8,
    width: u32,
    height: u32,
    data: ?[]u1 = null,
    foreground: Color = Color.rgb(0, 0, 0),
    background: ?Color = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, width: u32, height: u32) !BitmapImage {
        const data = try allocator.alloc(u1, width * height);
        @memset(data, 0);

        return .{
            .name = name,
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BitmapImage) void {
        if (self.data) |d| {
            self.allocator.free(d);
        }
    }

    pub fn setPixel(self: *BitmapImage, x: u32, y: u32, value: bool) void {
        if (x >= self.width or y >= self.height) return;
        if (self.data) |data| {
            data[y * self.width + x] = if (value) 1 else 0;
        }
    }

    pub fn getPixel(self: *const BitmapImage, x: u32, y: u32) bool {
        if (x >= self.width or y >= self.height) return false;
        if (self.data) |data| {
            return data[y * self.width + x] == 1;
        }
        return false;
    }
};

/// Image manager
pub const ImageManager = struct {
    photos: std.StringHashMap(*PhotoImage),
    bitmaps: std.StringHashMap(*BitmapImage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImageManager {
        return .{
            .photos = std.StringHashMap(*PhotoImage).init(allocator),
            .bitmaps = std.StringHashMap(*BitmapImage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImageManager) void {
        self.photos.deinit();
        self.bitmaps.deinit();
    }

    pub fn imageCount(self: *const ImageManager) usize {
        return self.photos.count() + self.bitmaps.count();
    }
};

/// Supported file formats
pub const ImageFormat = enum {
    gif,
    ppm,
    pgm,
    png,

    pub fn extension(self: ImageFormat) []const u8 {
        return switch (self) {
            .gif => ".gif",
            .ppm => ".ppm",
            .pgm => ".pgm",
            .png => ".png",
        };
    }
};

test "Color creation" {
    const c = Color.rgb(255, 128, 64);
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 128), c.g);
    try std.testing.expectEqual(@as(u8, 64), c.b);
    try std.testing.expectEqual(@as(u8, 255), c.a);
}

test "Color grayscale" {
    const c = Color.grayscale(128);
    try std.testing.expectEqual(@as(u8, 128), c.r);
    try std.testing.expectEqual(@as(u8, 128), c.g);
    try std.testing.expectEqual(@as(u8, 128), c.b);
}

test "Color toHex" {
    const c = Color.rgb(255, 0, 128);
    try std.testing.expectEqual(@as(u32, 0xFF0080), c.toHex());
}

test "Color equality" {
    const c1 = Color.rgb(100, 150, 200);
    const c2 = Color.rgb(100, 150, 200);
    const c3 = Color.rgb(100, 150, 201);

    try std.testing.expect(c1.equals(c2));
    try std.testing.expect(!c1.equals(c3));
}

test "PhotoImage creation" {
    const allocator = std.testing.allocator;
    var img = try PhotoImage.init(allocator, "test", 10, 10);
    defer img.deinit();

    try std.testing.expectEqual(@as(u32, 10), img.width);
    try std.testing.expectEqual(@as(u32, 10), img.height);
}

test "PhotoImage pixel operations" {
    const allocator = std.testing.allocator;
    var img = try PhotoImage.init(allocator, "test", 10, 10);
    defer img.deinit();

    const red = Color.rgb(255, 0, 0);
    img.put(5, 5, red);

    const pixel = img.get(5, 5);
    try std.testing.expect(pixel != null);
    try std.testing.expectEqual(@as(u8, 255), pixel.?.r);
    try std.testing.expectEqual(@as(u8, 0), pixel.?.g);
}

test "BitmapImage" {
    const allocator = std.testing.allocator;
    var bmp = try BitmapImage.init(allocator, "test_bmp", 8, 8);
    defer bmp.deinit();

    bmp.setPixel(0, 0, true);
    bmp.setPixel(1, 1, true);

    try std.testing.expect(bmp.getPixel(0, 0));
    try std.testing.expect(bmp.getPixel(1, 1));
    try std.testing.expect(!bmp.getPixel(2, 2));
}

test "PixelFormat bytesPerPixel" {
    try std.testing.expectEqual(@as(usize, 3), PixelFormat.rgb.bytesPerPixel());
    try std.testing.expectEqual(@as(usize, 4), PixelFormat.rgba.bytesPerPixel());
    try std.testing.expectEqual(@as(usize, 1), PixelFormat.grayscale.bytesPerPixel());
}

test "ImageManager" {
    const allocator = std.testing.allocator;
    var mgr = ImageManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 0), mgr.imageCount());
}
