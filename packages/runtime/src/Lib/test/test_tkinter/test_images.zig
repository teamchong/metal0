//! test.test_tkinter.test_images - Tk images tests
//! Tests for tkinter image handling (PhotoImage, BitmapImage)

const std = @import("std");
const testing = std.testing;

/// Image types supported by Tk
pub const ImageType = enum {
    photo,
    bitmap,

    pub fn toTclString(self: ImageType) []const u8 {
        return switch (self) {
            .photo => "photo",
            .bitmap => "bitmap",
        };
    }
};

/// Color format for pixel data
pub const PixelFormat = enum {
    rgb,
    rgba,
    grayscale,
    binary,

    pub fn bytesPerPixel(self: PixelFormat) u8 {
        return switch (self) {
            .rgb => 3,
            .rgba => 4,
            .grayscale => 1,
            .binary => 1,
        };
    }
};

/// RGB color value
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn withAlpha(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromHex(hex: u32) Color {
        return .{
            .r = @truncate((hex >> 16) & 0xFF),
            .g = @truncate((hex >> 8) & 0xFF),
            .b = @truncate(hex & 0xFF),
        };
    }

    pub fn toHex(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | self.b;
    }

    pub fn toHexString(self: Color, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch "";
    }

    pub fn blend(self: Color, other: Color, factor: f32) Color {
        const f = std.math.clamp(factor, 0.0, 1.0);
        const inv_f = 1.0 - f;
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * inv_f + @as(f32, @floatFromInt(other.r)) * f),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * inv_f + @as(f32, @floatFromInt(other.g)) * f),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * inv_f + @as(f32, @floatFromInt(other.b)) * f),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * inv_f + @as(f32, @floatFromInt(other.a)) * f),
        };
    }

    pub fn isTransparent(self: Color) bool {
        return self.a == 0;
    }

    // Common colors
    pub const black = Color.init(0, 0, 0);
    pub const white = Color.init(255, 255, 255);
    pub const red = Color.init(255, 0, 0);
    pub const green = Color.init(0, 255, 0);
    pub const blue = Color.init(0, 0, 255);
    pub const transparent = Color.withAlpha(0, 0, 0, 0);
};

/// Image subsample/zoom options
pub const ImageTransform = struct {
    subsample_x: u32 = 1,
    subsample_y: u32 = 1,
    zoom_x: u32 = 1,
    zoom_y: u32 = 1,

    pub fn none() ImageTransform {
        return .{};
    }

    pub fn subsample(x: u32, y: u32) ImageTransform {
        return .{ .subsample_x = x, .subsample_y = y };
    }

    pub fn zoom(x: u32, y: u32) ImageTransform {
        return .{ .zoom_x = x, .zoom_y = y };
    }

    pub fn getResultSize(self: ImageTransform, width: u32, height: u32) struct { width: u32, height: u32 } {
        const w = (width / self.subsample_x) * self.zoom_x;
        const h = (height / self.subsample_y) * self.zoom_y;
        return .{ .width = w, .height = h };
    }
};

/// Photo image (true color image)
pub const PhotoImage = struct {
    name: []const u8,
    width: u32,
    height: u32,
    pixels: std.ArrayList(u8),
    format: PixelFormat = .rgba,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) PhotoImage {
        return .{
            .name = name,
            .width = 0,
            .height = 0,
            .pixels = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PhotoImage) void {
        self.pixels.deinit();
    }

    pub fn create(allocator: std.mem.Allocator, name: []const u8, width: u32, height: u32) !PhotoImage {
        var img = PhotoImage.init(allocator, name);
        img.width = width;
        img.height = height;
        const size = width * height * img.format.bytesPerPixel();
        try img.pixels.resize(size);
        @memset(img.pixels.items, 0);
        return img;
    }

    pub fn blank(self: *PhotoImage) void {
        @memset(self.pixels.items, 0);
    }

    pub fn put(self: *PhotoImage, color: Color, x: u32, y: u32) void {
        if (x >= self.width or y >= self.height) return;

        const idx = (y * self.width + x) * self.format.bytesPerPixel();
        if (idx + 3 >= self.pixels.items.len) return;

        self.pixels.items[idx] = color.r;
        self.pixels.items[idx + 1] = color.g;
        self.pixels.items[idx + 2] = color.b;
        if (self.format == .rgba and idx + 3 < self.pixels.items.len) {
            self.pixels.items[idx + 3] = color.a;
        }
    }

    pub fn get(self: *const PhotoImage, x: u32, y: u32) ?Color {
        if (x >= self.width or y >= self.height) return null;

        const idx = (y * self.width + x) * self.format.bytesPerPixel();
        if (idx + 2 >= self.pixels.items.len) return null;

        return Color{
            .r = self.pixels.items[idx],
            .g = self.pixels.items[idx + 1],
            .b = self.pixels.items[idx + 2],
            .a = if (self.format == .rgba and idx + 3 < self.pixels.items.len) self.pixels.items[idx + 3] else 255,
        };
    }

    pub fn putBlock(self: *PhotoImage, data: []const u8, x: u32, y: u32, block_width: u32, block_height: u32) void {
        const bpp = self.format.bytesPerPixel();
        var dy: u32 = 0;
        while (dy < block_height and y + dy < self.height) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < block_width and x + dx < self.width) : (dx += 1) {
                const src_idx = (dy * block_width + dx) * bpp;
                const dst_idx = ((y + dy) * self.width + (x + dx)) * bpp;

                if (src_idx + bpp <= data.len and dst_idx + bpp <= self.pixels.items.len) {
                    @memcpy(self.pixels.items[dst_idx..][0..bpp], data[src_idx..][0..bpp]);
                }
            }
        }
    }

    pub fn copy(self: *PhotoImage, source: *const PhotoImage, transform: ImageTransform) !void {
        const result_size = transform.getResultSize(source.width, source.height);
        self.width = result_size.width;
        self.height = result_size.height;

        const size = self.width * self.height * self.format.bytesPerPixel();
        try self.pixels.resize(size);

        const bpp = self.format.bytesPerPixel();

        var dy: u32 = 0;
        while (dy < self.height) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < self.width) : (dx += 1) {
                const src_x = (dx / transform.zoom_x) * transform.subsample_x;
                const src_y = (dy / transform.zoom_y) * transform.subsample_y;

                if (src_x < source.width and src_y < source.height) {
                    const src_idx = (src_y * source.width + src_x) * bpp;
                    const dst_idx = (dy * self.width + dx) * bpp;

                    if (src_idx + bpp <= source.pixels.items.len and dst_idx + bpp <= self.pixels.items.len) {
                        @memcpy(self.pixels.items[dst_idx..][0..bpp], source.pixels.items[src_idx..][0..bpp]);
                    }
                }
            }
        }
    }

    pub fn subsample(self: *const PhotoImage, x: u32, y: u32) !PhotoImage {
        var result = PhotoImage.init(self.allocator, "subsampled");
        const transform = ImageTransform.subsample(x, y);
        try result.copy(self, transform);
        return result;
    }

    pub fn zoom(self: *const PhotoImage, x: u32, y: u32) !PhotoImage {
        var result = PhotoImage.init(self.allocator, "zoomed");
        const transform = ImageTransform.zoom(x, y);
        try result.copy(self, transform);
        return result;
    }

    pub fn transparencyGet(self: *const PhotoImage, x: u32, y: u32) bool {
        if (self.format != .rgba) return false;
        if (self.get(x, y)) |color| {
            return color.isTransparent();
        }
        return false;
    }

    pub fn transparencySet(self: *PhotoImage, x: u32, y: u32, transparent: bool) void {
        if (self.format != .rgba) return;
        if (x >= self.width or y >= self.height) return;

        const idx = (y * self.width + x) * 4 + 3;
        if (idx < self.pixels.items.len) {
            self.pixels.items[idx] = if (transparent) 0 else 255;
        }
    }

    pub fn data(self: *const PhotoImage) []const u8 {
        return self.pixels.items;
    }
};

/// Bitmap image (two-color image)
pub const BitmapImage = struct {
    name: []const u8,
    width: u32,
    height: u32,
    bits: std.ArrayList(u8),
    foreground: Color = Color.black,
    background: ?Color = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) BitmapImage {
        return .{
            .name = name,
            .width = 0,
            .height = 0,
            .bits = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BitmapImage) void {
        self.bits.deinit();
    }

    pub fn create(allocator: std.mem.Allocator, name: []const u8, width: u32, height: u32) !BitmapImage {
        var img = BitmapImage.init(allocator, name);
        img.width = width;
        img.height = height;
        const bytes_per_row = (width + 7) / 8;
        const size = bytes_per_row * height;
        try img.bits.resize(size);
        @memset(img.bits.items, 0);
        return img;
    }

    pub fn setBit(self: *BitmapImage, x: u32, y: u32, value: bool) void {
        if (x >= self.width or y >= self.height) return;

        const bytes_per_row = (self.width + 7) / 8;
        const byte_idx = y * bytes_per_row + x / 8;
        const bit_idx: u3 = @intCast(x % 8);

        if (byte_idx < self.bits.items.len) {
            if (value) {
                self.bits.items[byte_idx] |= @as(u8, 1) << bit_idx;
            } else {
                self.bits.items[byte_idx] &= ~(@as(u8, 1) << bit_idx);
            }
        }
    }

    pub fn getBit(self: *const BitmapImage, x: u32, y: u32) bool {
        if (x >= self.width or y >= self.height) return false;

        const bytes_per_row = (self.width + 7) / 8;
        const byte_idx = y * bytes_per_row + x / 8;
        const bit_idx: u3 = @intCast(x % 8);

        if (byte_idx < self.bits.items.len) {
            return (self.bits.items[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
        }
        return false;
    }

    pub fn configure(self: *BitmapImage, foreground: ?Color, background: ?Color) void {
        if (foreground) |fg| self.foreground = fg;
        self.background = background;
    }
};

/// Image file format detection
pub const ImageFormat = enum {
    gif,
    png,
    ppm,
    pgm,
    pbm,
    xbm,
    unknown,

    pub fn fromExtension(ext: []const u8) ImageFormat {
        if (std.mem.eql(u8, ext, ".gif")) return .gif;
        if (std.mem.eql(u8, ext, ".png")) return .png;
        if (std.mem.eql(u8, ext, ".ppm")) return .ppm;
        if (std.mem.eql(u8, ext, ".pgm")) return .pgm;
        if (std.mem.eql(u8, ext, ".pbm")) return .pbm;
        if (std.mem.eql(u8, ext, ".xbm")) return .xbm;
        return .unknown;
    }

    pub fn fromMagic(data: []const u8) ImageFormat {
        if (data.len < 4) return .unknown;

        // GIF
        if (data.len >= 6 and std.mem.eql(u8, data[0..6], "GIF87a") or std.mem.eql(u8, data[0..6], "GIF89a")) {
            return .gif;
        }

        // PNG
        if (data[0] == 0x89 and std.mem.eql(u8, data[1..4], "PNG")) {
            return .png;
        }

        // PPM/PGM/PBM
        if (data[0] == 'P') {
            if (data[1] == '6' or data[1] == '3') return .ppm;
            if (data[1] == '5' or data[1] == '2') return .pgm;
            if (data[1] == '4' or data[1] == '1') return .pbm;
        }

        return .unknown;
    }
};

/// Image manager for named images
pub const ImageManager = struct {
    photos: std.StringHashMap(PhotoImage),
    bitmaps: std.StringHashMap(BitmapImage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImageManager {
        return .{
            .photos = std.StringHashMap(PhotoImage).init(allocator),
            .bitmaps = std.StringHashMap(BitmapImage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImageManager) void {
        var photo_it = self.photos.iterator();
        while (photo_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.photos.deinit();

        var bitmap_it = self.bitmaps.iterator();
        while (bitmap_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.bitmaps.deinit();
    }

    pub fn createPhoto(self: *ImageManager, name: []const u8, width: u32, height: u32) !*PhotoImage {
        const photo = try PhotoImage.create(self.allocator, name, width, height);
        try self.photos.put(name, photo);
        return self.photos.getPtr(name).?;
    }

    pub fn createBitmap(self: *ImageManager, name: []const u8, width: u32, height: u32) !*BitmapImage {
        const bitmap = try BitmapImage.create(self.allocator, name, width, height);
        try self.bitmaps.put(name, bitmap);
        return self.bitmaps.getPtr(name).?;
    }

    pub fn getPhoto(self: *ImageManager, name: []const u8) ?*PhotoImage {
        return self.photos.getPtr(name);
    }

    pub fn getBitmap(self: *ImageManager, name: []const u8) ?*BitmapImage {
        return self.bitmaps.getPtr(name);
    }

    pub fn deletePhoto(self: *ImageManager, name: []const u8) bool {
        if (self.photos.getPtr(name)) |photo| {
            photo.deinit();
            return self.photos.remove(name);
        }
        return false;
    }

    pub fn deleteBitmap(self: *ImageManager, name: []const u8) bool {
        if (self.bitmaps.getPtr(name)) |bitmap| {
            bitmap.deinit();
            return self.bitmaps.remove(name);
        }
        return false;
    }

    pub fn names(self: *const ImageManager, image_type: ?ImageType) std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(self.allocator);

        if (image_type == null or image_type == .photo) {
            var it = self.photos.keyIterator();
            while (it.next()) |key| {
                result.append(key.*) catch {};
            }
        }

        if (image_type == null or image_type == .bitmap) {
            var it = self.bitmaps.keyIterator();
            while (it.next()) |key| {
                result.append(key.*) catch {};
            }
        }

        return result;
    }
};

// Tests

test "color_basic" {
    const c = Color.init(255, 128, 64);
    try testing.expectEqual(@as(u8, 255), c.r);
    try testing.expectEqual(@as(u8, 128), c.g);
    try testing.expectEqual(@as(u8, 64), c.b);
    try testing.expectEqual(@as(u8, 255), c.a);
}

test "color_with_alpha" {
    const c = Color.withAlpha(100, 150, 200, 128);
    try testing.expectEqual(@as(u8, 128), c.a);
}

test "color_from_hex" {
    const c = Color.fromHex(0xFF8040);
    try testing.expectEqual(@as(u8, 255), c.r);
    try testing.expectEqual(@as(u8, 128), c.g);
    try testing.expectEqual(@as(u8, 64), c.b);
}

test "color_to_hex" {
    const c = Color.init(255, 128, 64);
    try testing.expectEqual(@as(u32, 0xFF8040), c.toHex());
}

test "color_to_hex_string" {
    const c = Color.init(255, 0, 128);
    var buf: [16]u8 = undefined;
    const str = c.toHexString(&buf);
    try testing.expectEqualStrings("#ff0080", str);
}

test "color_blend" {
    const black = Color.black;
    const white = Color.white;
    const gray = black.blend(white, 0.5);

    try testing.expect(gray.r > 100 and gray.r < 150);
    try testing.expect(gray.g > 100 and gray.g < 150);
    try testing.expect(gray.b > 100 and gray.b < 150);
}

test "color_transparent" {
    try testing.expect(Color.transparent.isTransparent());
    try testing.expect(!Color.black.isTransparent());
}

test "pixel_format" {
    try testing.expectEqual(@as(u8, 3), PixelFormat.rgb.bytesPerPixel());
    try testing.expectEqual(@as(u8, 4), PixelFormat.rgba.bytesPerPixel());
    try testing.expectEqual(@as(u8, 1), PixelFormat.grayscale.bytesPerPixel());
}

test "image_transform" {
    const transform = ImageTransform.subsample(2, 2);
    const size = transform.getResultSize(100, 100);
    try testing.expectEqual(@as(u32, 50), size.width);
    try testing.expectEqual(@as(u32, 50), size.height);

    const zoom_transform = ImageTransform.zoom(2, 2);
    const zoom_size = zoom_transform.getResultSize(100, 100);
    try testing.expectEqual(@as(u32, 200), zoom_size.width);
    try testing.expectEqual(@as(u32, 200), zoom_size.height);
}

test "photo_image_create" {
    var img = try PhotoImage.create(testing.allocator, "test", 100, 100);
    defer img.deinit();

    try testing.expectEqualStrings("test", img.name);
    try testing.expectEqual(@as(u32, 100), img.width);
    try testing.expectEqual(@as(u32, 100), img.height);
}

test "photo_image_put_get" {
    var img = try PhotoImage.create(testing.allocator, "test", 10, 10);
    defer img.deinit();

    img.put(Color.red, 5, 5);
    const color = img.get(5, 5);

    try testing.expect(color != null);
    try testing.expectEqual(@as(u8, 255), color.?.r);
    try testing.expectEqual(@as(u8, 0), color.?.g);
    try testing.expectEqual(@as(u8, 0), color.?.b);
}

test "photo_image_blank" {
    var img = try PhotoImage.create(testing.allocator, "test", 10, 10);
    defer img.deinit();

    img.put(Color.red, 5, 5);
    img.blank();

    const color = img.get(5, 5);
    try testing.expect(color != null);
    try testing.expectEqual(@as(u8, 0), color.?.r);
}

test "photo_image_transparency" {
    var img = try PhotoImage.create(testing.allocator, "test", 10, 10);
    defer img.deinit();

    img.put(Color.red, 5, 5);
    try testing.expect(!img.transparencyGet(5, 5));

    img.transparencySet(5, 5, true);
    try testing.expect(img.transparencyGet(5, 5));
}

test "bitmap_image_create" {
    var img = try BitmapImage.create(testing.allocator, "test", 16, 16);
    defer img.deinit();

    try testing.expectEqual(@as(u32, 16), img.width);
    try testing.expectEqual(@as(u32, 16), img.height);
}

test "bitmap_image_set_get" {
    var img = try BitmapImage.create(testing.allocator, "test", 16, 16);
    defer img.deinit();

    try testing.expect(!img.getBit(5, 5));

    img.setBit(5, 5, true);
    try testing.expect(img.getBit(5, 5));

    img.setBit(5, 5, false);
    try testing.expect(!img.getBit(5, 5));
}

test "bitmap_image_configure" {
    var img = try BitmapImage.create(testing.allocator, "test", 8, 8);
    defer img.deinit();

    img.configure(Color.blue, Color.white);
    try testing.expectEqual(@as(u8, 0), img.foreground.r);
    try testing.expectEqual(@as(u8, 0), img.foreground.g);
    try testing.expectEqual(@as(u8, 255), img.foreground.b);
    try testing.expect(img.background != null);
}

test "image_format_from_extension" {
    try testing.expectEqual(ImageFormat.gif, ImageFormat.fromExtension(".gif"));
    try testing.expectEqual(ImageFormat.png, ImageFormat.fromExtension(".png"));
    try testing.expectEqual(ImageFormat.ppm, ImageFormat.fromExtension(".ppm"));
    try testing.expectEqual(ImageFormat.unknown, ImageFormat.fromExtension(".xyz"));
}

test "image_format_from_magic" {
    const gif_magic = "GIF89a";
    try testing.expectEqual(ImageFormat.gif, ImageFormat.fromMagic(gif_magic));

    const png_magic = [_]u8{ 0x89, 'P', 'N', 'G' };
    try testing.expectEqual(ImageFormat.png, ImageFormat.fromMagic(&png_magic));

    const ppm_magic = "P6\n";
    try testing.expectEqual(ImageFormat.ppm, ImageFormat.fromMagic(ppm_magic));
}

test "image_manager_create_photo" {
    var manager = ImageManager.init(testing.allocator);
    defer manager.deinit();

    const photo = try manager.createPhoto("myimage", 50, 50);
    try testing.expectEqualStrings("myimage", photo.name);

    const retrieved = manager.getPhoto("myimage");
    try testing.expect(retrieved != null);
}

test "image_manager_create_bitmap" {
    var manager = ImageManager.init(testing.allocator);
    defer manager.deinit();

    const bitmap = try manager.createBitmap("mybitmap", 16, 16);
    try testing.expectEqualStrings("mybitmap", bitmap.name);

    const retrieved = manager.getBitmap("mybitmap");
    try testing.expect(retrieved != null);
}

test "image_manager_delete" {
    var manager = ImageManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.createPhoto("temp", 10, 10);
    try testing.expect(manager.getPhoto("temp") != null);

    const deleted = manager.deletePhoto("temp");
    try testing.expect(deleted);
    try testing.expect(manager.getPhoto("temp") == null);
}

test "image_manager_names" {
    var manager = ImageManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.createPhoto("photo1", 10, 10);
    _ = try manager.createPhoto("photo2", 10, 10);
    _ = try manager.createBitmap("bitmap1", 8, 8);

    var all_names = manager.names(null);
    defer all_names.deinit();
    try testing.expectEqual(@as(usize, 3), all_names.items.len);

    var photo_names = manager.names(.photo);
    defer photo_names.deinit();
    try testing.expectEqual(@as(usize, 2), photo_names.items.len);
}

test "photo_image_data" {
    var img = try PhotoImage.create(testing.allocator, "test", 2, 2);
    defer img.deinit();

    img.put(Color.red, 0, 0);
    const data_slice = img.data();

    try testing.expect(data_slice.len > 0);
    try testing.expectEqual(@as(u8, 255), data_slice[0]); // R of first pixel
}
