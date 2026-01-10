//! test.test_tkinter.test_fonts - Tk fonts tests
//! Tests for tkinter font handling and configuration

const std = @import("std");
const testing = std.testing;

/// Font weight options
pub const FontWeight = enum {
    normal,
    bold,

    pub fn toTclString(self: FontWeight) []const u8 {
        return switch (self) {
            .normal => "normal",
            .bold => "bold",
        };
    }

    pub fn fromString(str: []const u8) FontWeight {
        if (std.mem.eql(u8, str, "bold")) return .bold;
        return .normal;
    }
};

/// Font slant options
pub const FontSlant = enum {
    roman,
    italic,

    pub fn toTclString(self: FontSlant) []const u8 {
        return switch (self) {
            .roman => "roman",
            .italic => "italic",
        };
    }

    pub fn fromString(str: []const u8) FontSlant {
        if (std.mem.eql(u8, str, "italic")) return .italic;
        return .roman;
    }
};

/// Font configuration
pub const FontConfig = struct {
    family: []const u8 = "TkDefaultFont",
    size: i32 = 12,
    weight: FontWeight = .normal,
    slant: FontSlant = .roman,
    underline: bool = false,
    overstrike: bool = false,

    pub fn withFamily(self: FontConfig, family: []const u8) FontConfig {
        var result = self;
        result.family = family;
        return result;
    }

    pub fn withSize(self: FontConfig, size: i32) FontConfig {
        var result = self;
        result.size = size;
        return result;
    }

    pub fn withWeight(self: FontConfig, weight: FontWeight) FontConfig {
        var result = self;
        result.weight = weight;
        return result;
    }

    pub fn withSlant(self: FontSlant, slant: FontSlant) FontConfig {
        var result: FontConfig = .{};
        result.slant = slant;
        return result;
    }

    pub fn makeBold(self: FontConfig) FontConfig {
        var result = self;
        result.weight = .bold;
        return result;
    }

    pub fn makeItalic(self: FontConfig) FontConfig {
        var result = self;
        result.slant = .italic;
        return result;
    }

    pub fn makeUnderline(self: FontConfig) FontConfig {
        var result = self;
        result.underline = true;
        return result;
    }
};

/// Font metrics
pub const FontMetrics = struct {
    ascent: i32 = 0,
    descent: i32 = 0,
    linespace: i32 = 0,
    fixed: bool = false,

    pub fn height(self: FontMetrics) i32 {
        return self.ascent + self.descent;
    }

    pub fn init(ascent: i32, descent: i32) FontMetrics {
        return .{
            .ascent = ascent,
            .descent = descent,
            .linespace = ascent + descent,
        };
    }
};

/// Named font representation
pub const Font = struct {
    name: []const u8,
    config: FontConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Font {
        return .{
            .name = name,
            .config = .{},
            .allocator = allocator,
        };
    }

    pub fn configure(self: *Font, config: FontConfig) void {
        self.config = config;
    }

    pub fn cget(self: *const Font, option: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, option, "-family")) return self.config.family;
        if (std.mem.eql(u8, option, "-weight")) return self.config.weight.toTclString();
        if (std.mem.eql(u8, option, "-slant")) return self.config.slant.toTclString();
        return null;
    }

    pub fn actual(self: *const Font, option: ?[]const u8) FontConfig {
        _ = option;
        return self.config;
    }

    pub fn metrics(self: *const Font) FontMetrics {
        // Calculate metrics based on size
        const ascent = @divFloor(self.config.size * 80, 100);
        const descent = @divFloor(self.config.size * 20, 100);
        return FontMetrics.init(ascent, descent);
    }

    pub fn measure(self: *const Font, text: []const u8) i32 {
        // Approximate width based on font size and text length
        const avg_char_width = @divFloor(self.config.size * 60, 100);
        return @as(i32, @intCast(text.len)) * avg_char_width;
    }

    pub fn copy(self: *const Font, new_name: []const u8) Font {
        var result = Font.init(self.allocator, new_name);
        result.config = self.config;
        return result;
    }
};

/// Font descriptor parser (Tk font description format)
pub const FontDescriptor = struct {
    /// Parse font from string like "Helvetica 12 bold italic"
    pub fn parse(desc: []const u8) !FontConfig {
        var config = FontConfig{};
        var it = std.mem.tokenizeAny(u8, desc, " ");

        // First token is family
        if (it.next()) |family| {
            config.family = family;
        }

        // Remaining tokens
        while (it.next()) |token| {
            // Try to parse as size
            if (std.fmt.parseInt(i32, token, 10)) |size| {
                config.size = size;
            } else |_| {
                // Check for weight
                if (std.mem.eql(u8, token, "bold")) {
                    config.weight = .bold;
                } else if (std.mem.eql(u8, token, "normal")) {
                    config.weight = .normal;
                }
                // Check for slant
                else if (std.mem.eql(u8, token, "italic")) {
                    config.slant = .italic;
                } else if (std.mem.eql(u8, token, "roman")) {
                    config.slant = .roman;
                }
                // Check for decoration
                else if (std.mem.eql(u8, token, "underline")) {
                    config.underline = true;
                } else if (std.mem.eql(u8, token, "overstrike")) {
                    config.overstrike = true;
                }
            }
        }

        return config;
    }

    /// Format font config as string
    pub fn format(config: FontConfig, buf: []u8) []const u8 {
        var pos: usize = 0;

        // Family
        const family_len = config.family.len;
        @memcpy(buf[pos..][0..family_len], config.family);
        pos += family_len;
        buf[pos] = ' ';
        pos += 1;

        // Size
        const size_str = std.fmt.bufPrint(buf[pos..], "{d}", .{config.size}) catch return buf[0..pos];
        pos += size_str.len;

        // Weight
        if (config.weight == .bold) {
            const s = " bold";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }

        // Slant
        if (config.slant == .italic) {
            const s = " italic";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }

        // Decorations
        if (config.underline) {
            const s = " underline";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }

        if (config.overstrike) {
            const s = " overstrike";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
        }

        return buf[0..pos];
    }
};

/// Font manager for named fonts
pub const FontManager = struct {
    fonts: std.StringHashMap(Font),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FontManager {
        return .{
            .fonts = std.StringHashMap(Font).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FontManager) void {
        self.fonts.deinit();
    }

    pub fn create(self: *FontManager, name: []const u8, config: FontConfig) !void {
        var font = Font.init(self.allocator, name);
        font.config = config;
        try self.fonts.put(name, font);
    }

    pub fn delete(self: *FontManager, name: []const u8) bool {
        return self.fonts.remove(name);
    }

    pub fn get(self: *const FontManager, name: []const u8) ?*const Font {
        if (self.fonts.getPtr(name)) |ptr| {
            return ptr;
        }
        return null;
    }

    pub fn getPtr(self: *FontManager, name: []const u8) ?*Font {
        return self.fonts.getPtr(name);
    }

    pub fn configure(self: *FontManager, name: []const u8, config: FontConfig) bool {
        if (self.fonts.getPtr(name)) |font| {
            font.config = config;
            return true;
        }
        return false;
    }

    pub fn names(self: *const FontManager) std.StringHashMap(Font).KeyIterator {
        return self.fonts.keyIterator();
    }

    pub fn families(self: *const FontManager) []const []const u8 {
        _ = self;
        // Return available font families
        return &[_][]const u8{
            "Arial",
            "Courier",
            "Courier New",
            "Helvetica",
            "Times",
            "Times New Roman",
            "TkDefaultFont",
            "TkTextFont",
            "TkFixedFont",
            "TkMenuFont",
            "TkHeadingFont",
            "TkCaptionFont",
            "TkSmallCaptionFont",
            "TkIconFont",
            "TkTooltipFont",
        };
    }
};

/// System font names
pub const SystemFonts = struct {
    pub const TkDefaultFont = "TkDefaultFont";
    pub const TkTextFont = "TkTextFont";
    pub const TkFixedFont = "TkFixedFont";
    pub const TkMenuFont = "TkMenuFont";
    pub const TkHeadingFont = "TkHeadingFont";
    pub const TkCaptionFont = "TkCaptionFont";
    pub const TkSmallCaptionFont = "TkSmallCaptionFont";
    pub const TkIconFont = "TkIconFont";
    pub const TkTooltipFont = "TkTooltipFont";

    pub fn isSystemFont(name: []const u8) bool {
        const system_fonts = [_][]const u8{
            TkDefaultFont,
            TkTextFont,
            TkFixedFont,
            TkMenuFont,
            TkHeadingFont,
            TkCaptionFont,
            TkSmallCaptionFont,
            TkIconFont,
            TkTooltipFont,
        };

        for (system_fonts) |sf| {
            if (std.mem.eql(u8, name, sf)) return true;
        }
        return false;
    }

    pub fn getDefaultConfig(name: []const u8) FontConfig {
        if (std.mem.eql(u8, name, TkFixedFont)) {
            return .{ .family = "Courier", .size = 10 };
        }
        if (std.mem.eql(u8, name, TkHeadingFont)) {
            return .{ .family = "TkDefaultFont", .size = 12, .weight = .bold };
        }
        if (std.mem.eql(u8, name, TkCaptionFont)) {
            return .{ .family = "TkDefaultFont", .size = 10, .weight = .bold };
        }
        if (std.mem.eql(u8, name, TkSmallCaptionFont)) {
            return .{ .family = "TkDefaultFont", .size = 8 };
        }
        if (std.mem.eql(u8, name, TkTooltipFont)) {
            return .{ .family = "TkDefaultFont", .size = 10 };
        }
        return .{ .family = "TkDefaultFont", .size = 12 };
    }
};

/// Font selection dialog result
pub const FontSelection = struct {
    family: []const u8,
    size: i32,
    weight: FontWeight,
    slant: FontSlant,
    underline: bool,
    overstrike: bool,

    pub fn toConfig(self: FontSelection) FontConfig {
        return .{
            .family = self.family,
            .size = self.size,
            .weight = self.weight,
            .slant = self.slant,
            .underline = self.underline,
            .overstrike = self.overstrike,
        };
    }
};

/// XLFD (X Logical Font Description) parser
pub const XLFDParser = struct {
    /// Parse X11 font name format
    /// Format: -foundry-family-weight-slant-setwidth-addstyle-pixels-points-resx-resy-spacing-avgwidth-registry-encoding
    pub fn parse(xlfd: []const u8) !FontConfig {
        var config = FontConfig{};

        if (xlfd.len == 0 or xlfd[0] != '-') {
            return error.InvalidXLFD;
        }

        var parts: [14][]const u8 = undefined;
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, xlfd[1..], '-');

        while (it.next()) |part| {
            if (count < 14) {
                parts[count] = part;
                count += 1;
            }
        }

        if (count < 14) {
            return error.InvalidXLFD;
        }

        // parts[1] = family
        config.family = parts[1];

        // parts[2] = weight
        if (std.mem.eql(u8, parts[2], "bold")) {
            config.weight = .bold;
        }

        // parts[3] = slant (r=roman, i=italic, o=oblique)
        if (std.mem.eql(u8, parts[3], "i") or std.mem.eql(u8, parts[3], "o")) {
            config.slant = .italic;
        }

        // parts[7] = points (in tenths of a point)
        if (std.fmt.parseInt(i32, parts[7], 10)) |points| {
            config.size = @divFloor(points, 10);
        } else |_| {}

        return config;
    }
};

// Tests

test "font_weight" {
    try testing.expectEqualStrings("normal", FontWeight.normal.toTclString());
    try testing.expectEqualStrings("bold", FontWeight.bold.toTclString());
    try testing.expectEqual(FontWeight.bold, FontWeight.fromString("bold"));
    try testing.expectEqual(FontWeight.normal, FontWeight.fromString("normal"));
}

test "font_slant" {
    try testing.expectEqualStrings("roman", FontSlant.roman.toTclString());
    try testing.expectEqualStrings("italic", FontSlant.italic.toTclString());
    try testing.expectEqual(FontSlant.italic, FontSlant.fromString("italic"));
    try testing.expectEqual(FontSlant.roman, FontSlant.fromString("roman"));
}

test "font_config_defaults" {
    const config = FontConfig{};
    try testing.expectEqualStrings("TkDefaultFont", config.family);
    try testing.expectEqual(@as(i32, 12), config.size);
    try testing.expectEqual(FontWeight.normal, config.weight);
    try testing.expectEqual(FontSlant.roman, config.slant);
}

test "font_config_modifiers" {
    var config = FontConfig{};
    config = config.withFamily("Arial").withSize(14).withWeight(.bold);

    try testing.expectEqualStrings("Arial", config.family);
    try testing.expectEqual(@as(i32, 14), config.size);
    try testing.expectEqual(FontWeight.bold, config.weight);
}

test "font_config_convenience" {
    const config = FontConfig{};
    const bold = config.makeBold();
    const italic = config.makeItalic();
    const underline = config.makeUnderline();

    try testing.expectEqual(FontWeight.bold, bold.weight);
    try testing.expectEqual(FontSlant.italic, italic.slant);
    try testing.expect(underline.underline);
}

test "font_metrics" {
    const metrics = FontMetrics.init(10, 3);
    try testing.expectEqual(@as(i32, 10), metrics.ascent);
    try testing.expectEqual(@as(i32, 3), metrics.descent);
    try testing.expectEqual(@as(i32, 13), metrics.height());
}

test "font_basic" {
    var font = Font.init(testing.allocator, "MyFont");
    font.configure(.{ .family = "Arial", .size = 14, .weight = .bold });

    try testing.expectEqualStrings("MyFont", font.name);
    try testing.expectEqualStrings("Arial", font.config.family);
    try testing.expectEqual(@as(i32, 14), font.config.size);
}

test "font_cget" {
    var font = Font.init(testing.allocator, "TestFont");
    font.configure(.{ .family = "Helvetica", .weight = .bold, .slant = .italic });

    try testing.expectEqualStrings("Helvetica", font.cget("-family").?);
    try testing.expectEqualStrings("bold", font.cget("-weight").?);
    try testing.expectEqualStrings("italic", font.cget("-slant").?);
}

test "font_measure" {
    var font = Font.init(testing.allocator, "TestFont");
    font.configure(.{ .size = 10 });

    const width = font.measure("Hello");
    try testing.expect(width > 0);
}

test "font_metrics_from_font" {
    var font = Font.init(testing.allocator, "TestFont");
    font.configure(.{ .size = 12 });

    const metrics = font.metrics();
    try testing.expect(metrics.ascent > 0);
    try testing.expect(metrics.descent > 0);
}

test "font_descriptor_parse" {
    const config = try FontDescriptor.parse("Helvetica 12 bold italic");
    try testing.expectEqualStrings("Helvetica", config.family);
    try testing.expectEqual(@as(i32, 12), config.size);
    try testing.expectEqual(FontWeight.bold, config.weight);
    try testing.expectEqual(FontSlant.italic, config.slant);
}

test "font_descriptor_parse_simple" {
    const config = try FontDescriptor.parse("Arial 10");
    try testing.expectEqualStrings("Arial", config.family);
    try testing.expectEqual(@as(i32, 10), config.size);
    try testing.expectEqual(FontWeight.normal, config.weight);
}

test "font_descriptor_format" {
    var buf: [128]u8 = undefined;
    const config = FontConfig{ .family = "Courier", .size = 10, .weight = .bold };
    const str = FontDescriptor.format(config, &buf);
    try testing.expect(std.mem.indexOf(u8, str, "Courier") != null);
    try testing.expect(std.mem.indexOf(u8, str, "10") != null);
    try testing.expect(std.mem.indexOf(u8, str, "bold") != null);
}

test "font_manager_create" {
    var manager = FontManager.init(testing.allocator);
    defer manager.deinit();

    try manager.create("MyFont", .{ .family = "Arial", .size = 14 });

    const font = manager.get("MyFont");
    try testing.expect(font != null);
    try testing.expectEqualStrings("Arial", font.?.config.family);
}

test "font_manager_configure" {
    var manager = FontManager.init(testing.allocator);
    defer manager.deinit();

    try manager.create("MyFont", .{ .family = "Arial", .size = 14 });
    const success = manager.configure("MyFont", .{ .family = "Helvetica", .size = 16 });

    try testing.expect(success);
    const font = manager.get("MyFont");
    try testing.expectEqualStrings("Helvetica", font.?.config.family);
}

test "font_manager_delete" {
    var manager = FontManager.init(testing.allocator);
    defer manager.deinit();

    try manager.create("TempFont", .{});
    try testing.expect(manager.get("TempFont") != null);

    const deleted = manager.delete("TempFont");
    try testing.expect(deleted);
    try testing.expect(manager.get("TempFont") == null);
}

test "font_manager_families" {
    var manager = FontManager.init(testing.allocator);
    defer manager.deinit();

    const families = manager.families();
    try testing.expect(families.len > 0);
}

test "system_fonts" {
    try testing.expect(SystemFonts.isSystemFont("TkDefaultFont"));
    try testing.expect(SystemFonts.isSystemFont("TkFixedFont"));
    try testing.expect(!SystemFonts.isSystemFont("MyCustomFont"));
}

test "system_font_defaults" {
    const fixed = SystemFonts.getDefaultConfig(SystemFonts.TkFixedFont);
    try testing.expectEqualStrings("Courier", fixed.family);

    const heading = SystemFonts.getDefaultConfig(SystemFonts.TkHeadingFont);
    try testing.expectEqual(FontWeight.bold, heading.weight);
}

test "font_selection" {
    const selection = FontSelection{
        .family = "Arial",
        .size = 12,
        .weight = .bold,
        .slant = .roman,
        .underline = false,
        .overstrike = false,
    };

    const config = selection.toConfig();
    try testing.expectEqualStrings("Arial", config.family);
    try testing.expectEqual(@as(i32, 12), config.size);
    try testing.expectEqual(FontWeight.bold, config.weight);
}

test "font_copy" {
    var original = Font.init(testing.allocator, "Original");
    original.configure(.{ .family = "Helvetica", .size = 14, .weight = .bold });

    const copied = original.copy("Copied");
    try testing.expectEqualStrings("Copied", copied.name);
    try testing.expectEqualStrings("Helvetica", copied.config.family);
    try testing.expectEqual(@as(i32, 14), copied.config.size);
}

test "xlfd_parse" {
    const xlfd = "-*-helvetica-bold-r-*-*-*-120-*-*-*-*-*-*";
    const config = try XLFDParser.parse(xlfd);
    try testing.expectEqualStrings("helvetica", config.family);
    try testing.expectEqual(FontWeight.bold, config.weight);
    try testing.expectEqual(@as(i32, 12), config.size);
}

test "xlfd_parse_italic" {
    const xlfd = "-*-times-medium-i-*-*-*-140-*-*-*-*-*-*";
    const config = try XLFDParser.parse(xlfd);
    try testing.expectEqualStrings("times", config.family);
    try testing.expectEqual(FontSlant.italic, config.slant);
    try testing.expectEqual(@as(i32, 14), config.size);
}
