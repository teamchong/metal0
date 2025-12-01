//! HPACK Header Compression (RFC 7541)
//!
//! HTTP/2 uses HPACK to compress headers. Key features:
//! - Static table: 61 pre-defined header fields
//! - Dynamic table: connection-specific cached headers
//! - Huffman encoding for string literals
//! - Integer encoding with prefix bits

const std = @import("std");

/// Header name-value pair (used throughout HPACK)
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Static table (RFC 7541 Appendix A)
/// Index 1-61 of pre-defined headers
pub const StaticTable = struct {
    pub const entries = [_]Header{
        .{ .name = ":authority", .value = "" }, // 1
        .{ .name = ":method", .value = "GET" }, // 2
        .{ .name = ":method", .value = "POST" }, // 3
        .{ .name = ":path", .value = "/" }, // 4
        .{ .name = ":path", .value = "/index.html" }, // 5
        .{ .name = ":scheme", .value = "http" }, // 6
        .{ .name = ":scheme", .value = "https" }, // 7
        .{ .name = ":status", .value = "200" }, // 8
        .{ .name = ":status", .value = "204" }, // 9
        .{ .name = ":status", .value = "206" }, // 10
        .{ .name = ":status", .value = "304" }, // 11
        .{ .name = ":status", .value = "400" }, // 12
        .{ .name = ":status", .value = "404" }, // 13
        .{ .name = ":status", .value = "500" }, // 14
        .{ .name = "accept-charset", .value = "" }, // 15
        .{ .name = "accept-encoding", .value = "gzip, deflate" }, // 16
        .{ .name = "accept-language", .value = "" }, // 17
        .{ .name = "accept-ranges", .value = "" }, // 18
        .{ .name = "accept", .value = "" }, // 19
        .{ .name = "access-control-allow-origin", .value = "" }, // 20
        .{ .name = "age", .value = "" }, // 21
        .{ .name = "allow", .value = "" }, // 22
        .{ .name = "authorization", .value = "" }, // 23
        .{ .name = "cache-control", .value = "" }, // 24
        .{ .name = "content-disposition", .value = "" }, // 25
        .{ .name = "content-encoding", .value = "" }, // 26
        .{ .name = "content-language", .value = "" }, // 27
        .{ .name = "content-length", .value = "" }, // 28
        .{ .name = "content-location", .value = "" }, // 29
        .{ .name = "content-range", .value = "" }, // 30
        .{ .name = "content-type", .value = "" }, // 31
        .{ .name = "cookie", .value = "" }, // 32
        .{ .name = "date", .value = "" }, // 33
        .{ .name = "etag", .value = "" }, // 34
        .{ .name = "expect", .value = "" }, // 35
        .{ .name = "expires", .value = "" }, // 36
        .{ .name = "from", .value = "" }, // 37
        .{ .name = "host", .value = "" }, // 38
        .{ .name = "if-match", .value = "" }, // 39
        .{ .name = "if-modified-since", .value = "" }, // 40
        .{ .name = "if-none-match", .value = "" }, // 41
        .{ .name = "if-range", .value = "" }, // 42
        .{ .name = "if-unmodified-since", .value = "" }, // 43
        .{ .name = "last-modified", .value = "" }, // 44
        .{ .name = "link", .value = "" }, // 45
        .{ .name = "location", .value = "" }, // 46
        .{ .name = "max-forwards", .value = "" }, // 47
        .{ .name = "proxy-authenticate", .value = "" }, // 48
        .{ .name = "proxy-authorization", .value = "" }, // 49
        .{ .name = "range", .value = "" }, // 50
        .{ .name = "referer", .value = "" }, // 51
        .{ .name = "refresh", .value = "" }, // 52
        .{ .name = "retry-after", .value = "" }, // 53
        .{ .name = "server", .value = "" }, // 54
        .{ .name = "set-cookie", .value = "" }, // 55
        .{ .name = "strict-transport-security", .value = "" }, // 56
        .{ .name = "transfer-encoding", .value = "" }, // 57
        .{ .name = "user-agent", .value = "" }, // 58
        .{ .name = "vary", .value = "" }, // 59
        .{ .name = "via", .value = "" }, // 60
        .{ .name = "www-authenticate", .value = "" }, // 61
    };

    /// Get entry by index (1-based)
    pub fn get(index: usize) ?Header {
        if (index == 0 or index > entries.len) return null;
        return entries[index - 1];
    }

    /// Find index by name (returns first match)
    pub fn findName(name: []const u8) ?usize {
        for (entries, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                return i + 1; // 1-based index
            }
        }
        return null;
    }

    /// Find index by name and value (exact match)
    pub fn findNameValue(name: []const u8, value: []const u8) ?usize {
        for (entries, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name) and std.mem.eql(u8, entry.value, value)) {
                return i + 1;
            }
        }
        return null;
    }
};

/// Dynamic table entry (same structure as Header but owned)
const DynamicEntry = Header;

/// HPACK encoder/decoder context
pub const Context = struct {
    allocator: std.mem.Allocator,
    dynamic_table: std.ArrayList(DynamicEntry),
    max_table_size: usize,
    current_size: usize,

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .dynamic_table = std.ArrayList(DynamicEntry){},
            .max_table_size = 4096, // Default from RFC
            .current_size = 0,
        };
    }

    pub fn deinit(self: *Context) void {
        for (self.dynamic_table.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
        }
        self.dynamic_table.deinit(self.allocator);
    }

    /// Set maximum dynamic table size
    pub fn setMaxTableSize(self: *Context, size: usize) void {
        self.max_table_size = size;
        self.evict();
    }

    /// Add entry to dynamic table
    pub fn addEntry(self: *Context, name: []const u8, value: []const u8) !void {
        const entry_size = name.len + value.len + 32;

        // If entry is larger than max table, clear table
        if (entry_size > self.max_table_size) {
            self.clear();
            return;
        }

        // Evict until there's room
        while (self.current_size + entry_size > self.max_table_size) {
            self.evictOne();
        }

        // Add new entry at front (index 0)
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        try self.dynamic_table.insert(self.allocator, 0, .{
            .name = name_copy,
            .value = value_copy,
        });
        self.current_size += entry_size;
    }

    /// Get entry from combined table (static + dynamic)
    /// Index 1-61 = static, 62+ = dynamic
    pub fn getEntry(self: *Context, index: usize) ?Header {
        if (index <= StaticTable.entries.len) {
            return StaticTable.get(index);
        }

        const dynamic_index = index - StaticTable.entries.len - 1;
        if (dynamic_index >= self.dynamic_table.items.len) return null;

        const entry = self.dynamic_table.items[dynamic_index];
        return .{ .name = entry.name, .value = entry.value };
    }

    /// Find best matching index for name/value
    pub fn findBestMatch(self: *Context, name: []const u8, value: []const u8) struct { index: ?usize, name_only: bool } {
        // Check static table first
        if (StaticTable.findNameValue(name, value)) |idx| {
            return .{ .index = idx, .name_only = false };
        }

        // Check dynamic table
        var name_match: ?usize = null;
        for (self.dynamic_table.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                if (std.mem.eql(u8, entry.value, value)) {
                    return .{ .index = StaticTable.entries.len + 1 + i, .name_only = false };
                }
                if (name_match == null) {
                    name_match = StaticTable.entries.len + 1 + i;
                }
            }
        }

        // Check static table for name-only match
        if (name_match == null) {
            name_match = StaticTable.findName(name);
        }

        return .{ .index = name_match, .name_only = name_match != null };
    }

    fn evict(self: *Context) void {
        while (self.current_size > self.max_table_size and self.dynamic_table.items.len > 0) {
            self.evictOne();
        }
    }

    fn evictOne(self: *Context) void {
        if (self.dynamic_table.items.len == 0) return;

        const entry = self.dynamic_table.pop() orelse return;
        self.current_size -= entry.name.len + entry.value.len + 32;
        self.allocator.free(entry.name);
        self.allocator.free(entry.value);
    }

    fn clear(self: *Context) void {
        for (self.dynamic_table.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
        }
        self.dynamic_table.clearRetainingCapacity();
        self.current_size = 0;
    }
};

/// HPACK Encoder
pub const Encoder = struct {
    context: *Context,

    pub fn init(context: *Context) Encoder {
        return .{ .context = context };
    }

    /// Encode headers to HPACK format
    pub fn encode(self: *Encoder, allocator: std.mem.Allocator, headers: []const Header) ![]u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        for (headers) |header| {
            try self.encodeHeader(allocator, &result, header.name, header.value);
        }

        return try result.toOwnedSlice(allocator);
    }

    fn encodeHeader(self: *Encoder, allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
        const match = self.context.findBestMatch(name, value);

        if (match.index != null and !match.name_only) {
            // Indexed header field (Section 6.1)
            // Format: 1xxxxxxx
            try encodeInteger(allocator, out, match.index.?, 7, 0x80);
        } else if (match.index != null) {
            // Literal with incremental indexing, indexed name (Section 6.2.1)
            // Format: 01xxxxxx
            try encodeInteger(allocator, out, match.index.?, 6, 0x40);
            try encodeString(allocator, out, value);
            try self.context.addEntry(name, value);
        } else {
            // Literal with incremental indexing, new name (Section 6.2.1)
            // Format: 01000000
            try out.append(allocator, 0x40);
            try encodeString(allocator, out, name);
            try encodeString(allocator, out, value);
            try self.context.addEntry(name, value);
        }
    }
};

/// HPACK Decoder
pub const Decoder = struct {
    context: *Context,

    pub fn init(context: *Context) Decoder {
        return .{ .context = context };
    }

    /// Decode HPACK data to headers
    pub fn decode(self: *Decoder, allocator: std.mem.Allocator, data: []const u8) ![]Header {
        var headers = std.ArrayList(Header){};
        errdefer {
            for (headers.items) |h| {
                allocator.free(h.name);
                allocator.free(h.value);
            }
            headers.deinit(allocator);
        }

        var pos: usize = 0;
        while (pos < data.len) {
            const header = try self.decodeHeader(allocator, data, &pos);
            try headers.append(allocator, header);
        }

        return try headers.toOwnedSlice(allocator);
    }

    fn decodeHeader(self: *Decoder, allocator: std.mem.Allocator, data: []const u8, pos: *usize) !Header {
        if (pos.* >= data.len) return error.UnexpectedEnd;

        const first_byte = data[pos.*];

        if ((first_byte & 0x80) != 0) {
            // Indexed header field (Section 6.1)
            const index = try decodeInteger(data, pos, 7);
            const entry = self.context.getEntry(index) orelse return error.InvalidIndex;
            return .{
                .name = try allocator.dupe(u8, entry.name),
                .value = try allocator.dupe(u8, entry.value),
            };
        } else if ((first_byte & 0xC0) == 0x40) {
            // Literal with incremental indexing (Section 6.2.1)
            const index = try decodeInteger(data, pos, 6);
            var name: []const u8 = undefined;
            var name_owned = false;

            if (index > 0) {
                const entry = self.context.getEntry(index) orelse return error.InvalidIndex;
                name = try allocator.dupe(u8, entry.name);
                name_owned = true;
            } else {
                name = try decodeString(allocator, data, pos);
                name_owned = true;
            }
            errdefer if (name_owned) allocator.free(name);

            const value = try decodeString(allocator, data, pos);
            errdefer allocator.free(value);

            try self.context.addEntry(name, value);

            return .{ .name = name, .value = value };
        } else if ((first_byte & 0xF0) == 0x00) {
            // Literal without indexing (Section 6.2.2)
            const index = try decodeInteger(data, pos, 4);
            var name: []const u8 = undefined;

            if (index > 0) {
                const entry = self.context.getEntry(index) orelse return error.InvalidIndex;
                name = try allocator.dupe(u8, entry.name);
            } else {
                name = try decodeString(allocator, data, pos);
            }
            errdefer allocator.free(name);

            const value = try decodeString(allocator, data, pos);

            return .{ .name = name, .value = value };
        } else if ((first_byte & 0xF0) == 0x10) {
            // Literal never indexed (Section 6.2.3)
            const index = try decodeInteger(data, pos, 4);
            var name: []const u8 = undefined;

            if (index > 0) {
                const entry = self.context.getEntry(index) orelse return error.InvalidIndex;
                name = try allocator.dupe(u8, entry.name);
            } else {
                name = try decodeString(allocator, data, pos);
            }
            errdefer allocator.free(name);

            const value = try decodeString(allocator, data, pos);

            return .{ .name = name, .value = value };
        } else if ((first_byte & 0xE0) == 0x20) {
            // Dynamic table size update (Section 6.3)
            const new_size = try decodeInteger(data, pos, 5);
            self.context.setMaxTableSize(new_size);
            // Recursive call to get actual header
            return self.decodeHeader(allocator, data, pos);
        }

        return error.InvalidHeaderField;
    }
};

/// Encode integer with prefix (RFC 7541 Section 5.1)
fn encodeInteger(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: usize, prefix_bits: u4, prefix: u8) !void {
    const max_prefix: usize = (@as(usize, 1) << prefix_bits) - 1;

    if (value < max_prefix) {
        try out.append(allocator, prefix | @as(u8, @truncate(value)));
    } else {
        try out.append(allocator, prefix | @as(u8, @truncate(max_prefix)));
        var remaining = value - max_prefix;
        while (remaining >= 128) {
            try out.append(allocator, @as(u8, @truncate(remaining & 0x7F)) | 0x80);
            remaining >>= 7;
        }
        try out.append(allocator, @truncate(remaining));
    }
}

/// Decode integer with prefix (RFC 7541 Section 5.1)
fn decodeInteger(data: []const u8, pos: *usize, prefix_bits: u4) !usize {
    if (pos.* >= data.len) return error.UnexpectedEnd;

    const max_prefix: usize = (@as(usize, 1) << prefix_bits) - 1;
    var value: usize = data[pos.*] & @as(u8, @truncate(max_prefix));
    pos.* += 1;

    if (value < max_prefix) {
        return value;
    }

    var shift: u6 = 0;
    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;
        value += @as(usize, byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            return value;
        }
        shift += 7;
        if (shift > 63) return error.IntegerOverflow;
    }

    return error.UnexpectedEnd;
}

/// Encode string literal (RFC 7541 Section 5.2)
fn encodeString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), str: []const u8) !void {
    // For simplicity, use raw string (no Huffman encoding)
    // First bit = 0 means no Huffman
    try encodeInteger(allocator, out, str.len, 7, 0x00);
    try out.appendSlice(allocator, str);
}

/// Decode string literal (RFC 7541 Section 5.2)
fn decodeString(allocator: std.mem.Allocator, data: []const u8, pos: *usize) ![]const u8 {
    if (pos.* >= data.len) return error.UnexpectedEnd;

    const huffman = (data[pos.*] & 0x80) != 0;
    const length = try decodeInteger(data, pos, 7);

    if (pos.* + length > data.len) return error.UnexpectedEnd;

    const str_data = data[pos.* .. pos.* + length];
    pos.* += length;

    if (huffman) {
        // Huffman decode
        return huffmanDecode(allocator, str_data);
    }

    return try allocator.dupe(u8, str_data);
}

/// Simplified Huffman decoder (RFC 7541 Appendix B)
/// For full implementation, would need complete Huffman tree
fn huffmanDecode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    // Simplified: just return raw bytes for now
    // Full implementation would decode Huffman codes
    return try allocator.dupe(u8, data);
}

// ============================================================================
// Tests
// ============================================================================

test "StaticTable lookup" {
    // :method GET is index 2
    const entry = StaticTable.get(2).?;
    try std.testing.expectEqualStrings(":method", entry.name);
    try std.testing.expectEqualStrings("GET", entry.value);

    // :path / is index 4
    const path = StaticTable.get(4).?;
    try std.testing.expectEqualStrings(":path", path.name);
    try std.testing.expectEqualStrings("/", path.value);
}

test "StaticTable findNameValue" {
    const idx = StaticTable.findNameValue(":method", "GET");
    try std.testing.expectEqual(@as(?usize, 2), idx);

    const idx2 = StaticTable.findNameValue(":scheme", "https");
    try std.testing.expectEqual(@as(?usize, 7), idx2);
}

test "Context dynamic table" {
    const allocator = std.testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try ctx.addEntry("custom-header", "custom-value");

    // Dynamic entry is at index 62 (after static table)
    const entry = ctx.getEntry(62).?;
    try std.testing.expectEqualStrings("custom-header", entry.name);
    try std.testing.expectEqualStrings("custom-value", entry.value);
}

test "Integer encoding/decoding roundtrip" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Test small value
    try encodeInteger(allocator, &buf, 10, 5, 0x00);
    var pos: usize = 0;
    const val1 = try decodeInteger(buf.items, &pos, 5);
    try std.testing.expectEqual(@as(usize, 10), val1);

    // Test value requiring continuation
    buf.clearRetainingCapacity();
    try encodeInteger(allocator, &buf, 1337, 5, 0x00);
    pos = 0;
    const val2 = try decodeInteger(buf.items, &pos, 5);
    try std.testing.expectEqual(@as(usize, 1337), val2);
}
