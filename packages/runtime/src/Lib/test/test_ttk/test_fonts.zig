//! test.test_ttk.test_fonts - Tk font handling tests
const std = @import("std");

/// Font weight values
pub const FontWeight = enum {
    normal,
    bold,

    pub fn toString(self: FontWeight) []const u8 {
        return switch (self) {
            .normal => "normal",
            .bold => "bold",
        };
    }
};

/// Font slant values
pub const FontSlant = enum {
    roman,
    italic,

    pub fn toString(self: FontSlant) []const u8 {
        return switch (self) {
            .roman => "roman",
            .italic => "italic",
        };
    }
};

/// Font underline state
pub const FontUnderline = enum {
    none,
    single,
    double,
};

/// Font descriptor
pub const Font = struct {
    family: []const u8,
    size: i32 = 12,
    weight: FontWeight = .normal,
    slant: FontSlant = .roman,
    underline: bool = false,
    overstrike: bool = false,

    pub fn init(family: []const u8) Font {
        return .{ .family = family };
    }

    pub fn withSize(self: Font, size: i32) Font {
        var copy = self;
        copy.size = size;
        return copy;
    }

    pub fn withWeight(self: Font, weight: FontWeight) Font {
        var copy = self;
        copy.weight = weight;
        return copy;
    }

    pub fn withSlant(self: Font, slant: FontSlant) Font {
        var copy = self;
        copy.slant = slant;
        return copy;
    }

    pub fn isBold(self: *const Font) bool {
        return self.weight == .bold;
    }

    pub fn isItalic(self: *const Font) bool {
        return self.slant == .italic;
    }

    pub fn equals(self: *const Font, other: *const Font) bool {
        return std.mem.eql(u8, self.family, other.family) and
            self.size == other.size and
            self.weight == other.weight and
            self.slant == other.slant;
    }
};

/// Named font (registered in Tk)
pub const NamedFont = struct {
    name: []const u8,
    font: Font,

    pub fn init(name: []const u8, font: Font) NamedFont {
        return .{ .name = name, .font = font };
    }

    pub fn configure(self: *NamedFont, font: Font) void {
        self.font = font;
    }

    pub fn actual(self: *const NamedFont) Font {
        return self.font;
    }
};

/// Font metrics
pub const FontMetrics = struct {
    ascent: i32,
    descent: i32,
    linespace: i32,
    fixed: bool,

    pub fn init(ascent: i32, descent: i32) FontMetrics {
        return .{
            .ascent = ascent,
            .descent = descent,
            .linespace = ascent + descent,
            .fixed = false,
        };
    }

    pub fn height(self: *const FontMetrics) i32 {
        return self.linespace;
    }
};

/// Font family information
pub const FontFamily = struct {
    name: []const u8,
    fixed: bool = false,
    scalable: bool = true,

    pub fn init(name: []const u8) FontFamily {
        return .{ .name = name };
    }
};

/// Font manager
pub const FontManager = struct {
    fonts: std.StringHashMap(NamedFont),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FontManager {
        return .{
            .fonts = std.StringHashMap(NamedFont).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FontManager) void {
        self.fonts.deinit();
    }

    pub fn create(self: *FontManager, name: []const u8, font: Font) !void {
        try self.fonts.put(name, NamedFont.init(name, font));
    }

    pub fn get(self: *FontManager, name: []const u8) ?*NamedFont {
        return self.fonts.getPtr(name);
    }

    pub fn delete(self: *FontManager, name: []const u8) bool {
        return self.fonts.remove(name);
    }

    pub fn names(self: *const FontManager) usize {
        return self.fonts.count();
    }
};

/// Measure text width
pub fn measureText(font: *const Font, text: []const u8) i32 {
    // Simplified: assume average char width based on size
    const avg_width: i32 = @divTrunc(font.size * 6, 10);
    return avg_width * @as(i32, @intCast(text.len));
}

/// Get available font families
pub fn families() []const []const u8 {
    return &[_][]const u8{
        "Helvetica",
        "Times",
        "Courier",
        "Arial",
        "System",
    };
}

test "Font creation" {
    const font = Font.init("Helvetica")
        .withSize(14)
        .withWeight(.bold);

    try std.testing.expectEqualStrings("Helvetica", font.family);
    try std.testing.expectEqual(@as(i32, 14), font.size);
    try std.testing.expect(font.isBold());
    try std.testing.expect(!font.isItalic());
}

test "Font with slant" {
    const font = Font.init("Times")
        .withSlant(.italic);

    try std.testing.expect(font.isItalic());
    try std.testing.expect(!font.isBold());
}

test "Font equality" {
    const f1 = Font.init("Arial").withSize(12);
    const f2 = Font.init("Arial").withSize(12);
    const f3 = Font.init("Arial").withSize(14);

    try std.testing.expect(f1.equals(&f2));
    try std.testing.expect(!f1.equals(&f3));
}

test "FontMetrics" {
    const metrics = FontMetrics.init(10, 3);
    try std.testing.expectEqual(@as(i32, 10), metrics.ascent);
    try std.testing.expectEqual(@as(i32, 3), metrics.descent);
    try std.testing.expectEqual(@as(i32, 13), metrics.height());
}

test "NamedFont" {
    var named = NamedFont.init("TkDefaultFont", Font.init("Helvetica"));
    try std.testing.expectEqualStrings("TkDefaultFont", named.name);

    named.configure(Font.init("Arial").withSize(14));
    try std.testing.expectEqualStrings("Arial", named.actual().family);
}

test "FontManager" {
    const allocator = std.testing.allocator;
    var mgr = FontManager.init(allocator);
    defer mgr.deinit();

    try mgr.create("myFont", Font.init("Courier").withSize(10));
    try std.testing.expectEqual(@as(usize, 1), mgr.names());
    try std.testing.expect(mgr.get("myFont") != null);

    _ = mgr.delete("myFont");
    try std.testing.expect(mgr.get("myFont") == null);
}

test "measureText" {
    const font = Font.init("Courier").withSize(10);
    const width = measureText(&font, "Hello");
    try std.testing.expect(width > 0);
}

test "font families" {
    const fams = families();
    try std.testing.expect(fams.len >= 3);
}
