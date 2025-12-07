/// this - The Zen of Python
/// Mirrors cpython/Lib/this.py
///
/// Tim Peters' famous "Zen of Python" Easter egg.
/// Type "import this" in Python to see it.
///
/// The original module uses a ROT13 cipher for the text,
/// which is a beautiful meta-joke: the Zen says "Simple is
/// better than complex" but the implementation is needlessly
/// complex by encoding the text.

const std = @import("std");

// ============================================================================
// The Zen of Python (Decoded)
// ============================================================================

/// The Zen of Python, by Tim Peters
pub const ZEN: []const u8 =
    \\The Zen of Python, by Tim Peters
    \\
    \\Beautiful is better than ugly.
    \\Explicit is better than implicit.
    \\Simple is better than complex.
    \\Complex is better than complicated.
    \\Flat is better than nested.
    \\Sparse is better than dense.
    \\Readability counts.
    \\Special cases aren't special enough to break the rules.
    \\Although practicality beats purity.
    \\Errors should never pass silently.
    \\Unless explicitly silenced.
    \\In the face of ambiguity, refuse the temptation to guess.
    \\There should be one-- and preferably only one --obvious way to do it.
    \\Although that way may not be obvious at first unless you're Dutch.
    \\Now is better than never.
    \\Although never is often better than *right* now.
    \\If the implementation is hard to explain, it's a bad idea.
    \\If the implementation is easy to explain, it may be a good idea.
    \\Namespaces are one honking great idea -- let's do more of those!
;

// ============================================================================
// ROT13 (The Original Encoding)
// ============================================================================

/// The encoded form (ROT13) as it appears in CPython's this.py
pub const s: []const u8 =
    \\Gur Mra bs Clguba, ol Gvz Crgref
    \\
    \\Ornhgvshy vf orggre guna htyl.
    \\Rkcyvpvg vf orggre guna vzcyvpvg.
    \\Fvzcyr vf orggre guna pbzcyrk.
    \\Pbzcyrk vf orggre guna pbzcyvpngrq.
    \\Syng vf orggre guna arfgrq.
    \\Fcnefr vf orggre guna qrafr.
    \\Ernqnovyvgl pbhagf.
    \\Fcrpvny pnfrf nera'g fcrpvny rabhtu gb oernx gur ehyrf.
    \\Nygubhtu cenpgvpnyvgl orngf chevgl.
    \\Reebef fubhyq arire cnff fvyragyl.
    \\Hayrff rkcyvpvgyl fvyraprq.
    \\Va gur snpr bs nzovthvgl, ershfr gur grzcgngvba gb thrff.
    \\Gurer fubhyq or bar-- naq cersrenoyl bayl bar --boivbhf jnl gb qb vg.
    \\Nygubhtu gung jnl znl abg or boivbhf ng svefg hayrff lbh'er Qhgpu.
    \\Abj vf orggre guna arire.
    \\Nygubhtu arire vf bsgra orggre guna *evtug* abj.
    \\Vs gur vzcyrzragngvba vf uneq gb rkcynva, vg'f n onq vqrn.
    \\Vs gur vzcyrzragngvba vf rnfl gb rkcynva, vg znl or n tbbq vqrn.
    \\Anzrfcnprf ner bar ubaxvat terng vqrn -- yrg'f qb zber bs gubfr!
;

/// The cipher dictionary (d in this.py)
/// Maps encoded char to decoded char
pub const d: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = @intCast(i);
    }
    // ROT13 mapping for letters
    for ('A'..'N') |c| {
        table[c] = c + 13;
        table[c + 32] = c + 32 + 13; // lowercase
    }
    for ('N'..'Z' + 1) |c| {
        table[c] = c - 13;
        table[c + 32] = c + 32 - 13; // lowercase
    }
    break :blk table;
};

// ============================================================================
// ROT13 Functions
// ============================================================================

/// Apply ROT13 cipher to a string
pub fn rot13(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = d[c];
    }
    return result;
}

/// Apply ROT13 in place (comptime version)
pub fn rot13Comptime(comptime input: []const u8) *const [input.len]u8 {
    comptime {
        var result: [input.len]u8 = undefined;
        for (input, 0..) |c, i| {
            result[i] = d[c];
        }
        return &result;
    }
}

/// Decode the encoded Zen
pub fn decode(allocator: std.mem.Allocator) ![]u8 {
    return rot13(allocator, s);
}

// ============================================================================
// Individual Aphorisms
// ============================================================================

/// Get a specific aphorism by index (0-19)
pub fn getAphorism(index: usize) ?[]const u8 {
    const aphorisms = [_][]const u8{
        "Beautiful is better than ugly.",
        "Explicit is better than implicit.",
        "Simple is better than complex.",
        "Complex is better than complicated.",
        "Flat is better than nested.",
        "Sparse is better than dense.",
        "Readability counts.",
        "Special cases aren't special enough to break the rules.",
        "Although practicality beats purity.",
        "Errors should never pass silently.",
        "Unless explicitly silenced.",
        "In the face of ambiguity, refuse the temptation to guess.",
        "There should be one-- and preferably only one --obvious way to do it.",
        "Although that way may not be obvious at first unless you're Dutch.",
        "Now is better than never.",
        "Although never is often better than *right* now.",
        "If the implementation is hard to explain, it's a bad idea.",
        "If the implementation is easy to explain, it may be a good idea.",
        "Namespaces are one honking great idea -- let's do more of those!",
    };

    if (index >= aphorisms.len) return null;
    return aphorisms[index];
}

/// Number of aphorisms
pub const APHORISM_COUNT: usize = 19;

// ============================================================================
// Print Functions
// ============================================================================

/// Print the Zen (called on import in Python)
pub fn printZen() void {
    std.debug.print("{s}\n", .{ZEN});
}

/// Print a random aphorism
pub fn printRandom(seed: u64) void {
    var rng = std.Random.DefaultPrng.init(seed);
    const index = rng.random().uintLessThan(usize, APHORISM_COUNT);
    if (getAphorism(index)) |aphorism| {
        std.debug.print("{s}\n", .{aphorism});
    }
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the this module
/// In CPython, this prints the Zen on import
pub fn init() void {
    if (initialized) return;
    initialized = true;
    // Note: We don't automatically print like CPython does
    // That would be annoying in a compiled context
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Fun Extras
// ============================================================================

/// Author of the Zen
pub const AUTHOR: []const u8 = "Tim Peters";

/// PEP 20 reference
pub const PEP: []const u8 = "PEP 20 -- The Zen of Python";

/// Check if text follows the Zen (joke function)
pub fn isZenCompliant(code: []const u8) bool {
    // If it's readable and simple, it's probably Zen-compliant
    // This is of course a joke - you can't really check this programmatically
    _ = code;
    return true; // Everything is beautiful in its own way
}

// ============================================================================
// Tests
// ============================================================================

test "zen content" {
    try std.testing.expect(std.mem.indexOf(u8, ZEN, "Beautiful") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZEN, "Tim Peters") != null);
}

test "rot13 decode" {
    const allocator = std.testing.allocator;
    const decoded = try decode(allocator);
    defer allocator.free(decoded);

    // Should match the Zen
    try std.testing.expect(std.mem.indexOf(u8, decoded, "Beautiful") != null);
}

test "rot13 roundtrip" {
    const allocator = std.testing.allocator;

    const original = "Hello, World!";
    const encoded = try rot13(allocator, original);
    defer allocator.free(encoded);

    const decoded = try rot13(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(original, decoded);
}

test "get aphorism" {
    const first = getAphorism(0);
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Beautiful is better than ugly.", first.?);

    const last = getAphorism(18);
    try std.testing.expect(last != null);
    try std.testing.expect(std.mem.indexOf(u8, last.?, "Namespaces") != null);

    const invalid = getAphorism(100);
    try std.testing.expect(invalid == null);
}

test "aphorism count" {
    try std.testing.expectEqual(@as(usize, 19), APHORISM_COUNT);
}

test "cipher table" {
    // A -> N, N -> A
    try std.testing.expectEqual(@as(u8, 'N'), d['A']);
    try std.testing.expectEqual(@as(u8, 'A'), d['N']);
    // a -> n, n -> a
    try std.testing.expectEqual(@as(u8, 'n'), d['a']);
    try std.testing.expectEqual(@as(u8, 'a'), d['n']);
    // Non-letters unchanged
    try std.testing.expectEqual(@as(u8, ' '), d[' ']);
    try std.testing.expectEqual(@as(u8, '!'), d['!']);
}

test "author info" {
    try std.testing.expectEqualStrings("Tim Peters", AUTHOR);
}
