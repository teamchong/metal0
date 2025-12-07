/// antigravity - XKCD Easter Egg Module
/// Mirrors cpython/Lib/antigravity.py
///
/// Python's famous "import antigravity" Easter egg.
/// Opens the XKCD comic about Python in a web browser.
///
/// The comic (https://xkcd.com/353/) shows someone flying after
/// discovering Python. "I wrote 20 short programs in Python yesterday.
/// It was wonderful. Series of numbers, file manipulation, web scraping..."
/// "I learned to mass-produce hens that day!"

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// XKCD Reference
// ============================================================================

/// The famous XKCD comic URL
pub const XKCD_URL: []const u8 = "https://xkcd.com/353/";

/// Comic title
pub const COMIC_TITLE: []const u8 = "Python";

/// Comic alt text
pub const COMIC_ALT: []const u8 =
    \\I wrote 20 short programs in Python yesterday.
    \\It was wonderful. Bestow upon me the flight of...
    \\...wait, this is a programming language, not
    \\a magic spell. Though Python does feel like magic.
;

// ============================================================================
// Geohash Implementation (Easter Egg within Easter Egg)
// ============================================================================

/// Geohash implementation from XKCD 426
/// Given a date and the Dow Jones opening, computes coordinates
/// for the "geohashing" game.
///
/// This is the actual algorithm from xkcd.com/426:
/// geohash(date, dow) = md5(date + "-" + dow)
/// Take first 16 hex chars for latitude fraction, next 16 for longitude
pub const Geohash = struct {
    /// Compute geohash coordinates
    /// date: YYYY-MM-DD format
    /// dow: Dow Jones Industrial Average opening price
    /// Returns latitude and longitude offsets (0.0 to 1.0)
    pub fn compute(date: []const u8, dow: []const u8) struct { lat: f64, lon: f64 } {
        var buf: [64]u8 = undefined;
        const input = std.fmt.bufPrint(&buf, "{s}-{s}", .{ date, dow }) catch return .{ .lat = 0.0, .lon = 0.0 };

        var hash: [std.crypto.hash.Md5.digest_length]u8 = undefined;
        std.crypto.hash.Md5.hash(input, &hash, .{});

        // Convert first 8 bytes to latitude fraction
        const lat_bytes = hash[0..8];
        var lat_val: u64 = 0;
        for (lat_bytes) |b| {
            lat_val = (lat_val << 8) | b;
        }
        const lat = @as(f64, @floatFromInt(lat_val)) / @as(f64, @floatFromInt(std.math.maxInt(u64)));

        // Convert next 8 bytes to longitude fraction
        const lon_bytes = hash[8..16];
        var lon_val: u64 = 0;
        for (lon_bytes) |b| {
            lon_val = (lon_val << 8) | b;
        }
        const lon = @as(f64, @floatFromInt(lon_val)) / @as(f64, @floatFromInt(std.math.maxInt(u64)));

        return .{ .lat = lat, .lon = lon };
    }

    /// Get full geohash coordinates given base location
    pub fn getCoordinates(
        base_lat: f64,
        base_lon: f64,
        date: []const u8,
        dow: []const u8,
    ) struct { lat: f64, lon: f64 } {
        const offset = compute(date, dow);

        // Add fractional offset to integer part of base coordinates
        const lat_int = @floor(base_lat);
        const lon_int = @floor(base_lon);

        return .{
            .lat = lat_int + offset.lat,
            .lon = lon_int + offset.lon,
        };
    }
};

/// Convenience function matching Python's geohash()
pub fn geohash(latitude: f64, longitude: f64, date: []const u8, dow: []const u8) struct { lat: f64, lon: f64 } {
    return Geohash.getCoordinates(latitude, longitude, date, dow);
}

// ============================================================================
// Browser Opening
// ============================================================================

/// Open URL in default browser
pub fn openBrowser(url: []const u8) bool {
    const cmd = switch (builtin.os.tag) {
        .macos => &[_][]const u8{ "open", url },
        .windows => &[_][]const u8{ "start", url },
        .linux => &[_][]const u8{ "xdg-open", url },
        else => return false,
    };

    var child = std.process.Child.init(cmd, std.heap.page_allocator);
    child.spawn() catch return false;
    _ = child.wait() catch return false;
    return true;
}

/// Open the XKCD comic
pub fn fly() bool {
    return openBrowser(XKCD_URL);
}

// ============================================================================
// Module Import Effect
// ============================================================================

/// Called when module is imported
/// In CPython, this opens the browser automatically
pub fn onImport() void {
    // In real Python, import antigravity opens the browser
    // We don't do this automatically in tests/library code
    // User should call fly() explicitly
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the antigravity module
pub fn init() void {
    if (initialized) return;
    initialized = true;
    // Note: We don't automatically open browser like CPython does
    // That would be annoying in a compiled context
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Fun Extras
// ============================================================================

/// The Zen of Python, for good measure
pub const ZEN_PREVIEW: []const u8 =
    \\Beautiful is better than ugly.
    \\Explicit is better than implicit.
    \\Simple is better than complex.
    \\...
    \\(Use 'import this' for the full Zen)
;

/// Flying status
pub fn isFlying() bool {
    // You're always flying with Python!
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "xkcd url" {
    try std.testing.expectEqualStrings("https://xkcd.com/353/", XKCD_URL);
}

test "geohash compute" {
    // Test with known values
    const result = Geohash.compute("2005-05-26", "10458.68");
    try std.testing.expect(result.lat >= 0.0 and result.lat <= 1.0);
    try std.testing.expect(result.lon >= 0.0 and result.lon <= 1.0);
}

test "geohash coordinates" {
    const result = geohash(37.0, -122.0, "2005-05-26", "10458.68");
    try std.testing.expect(result.lat >= 37.0 and result.lat < 38.0);
    try std.testing.expect(result.lon >= -122.0 and result.lon < -121.0);
}

test "is flying" {
    try std.testing.expect(isFlying());
}

test "comic info" {
    try std.testing.expectEqualStrings("Python", COMIC_TITLE);
    try std.testing.expect(COMIC_ALT.len > 0);
}
