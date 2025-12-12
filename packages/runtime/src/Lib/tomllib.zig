//! Python 'tomllib' module - TOML parser
//!
//! Provides functions for parsing TOML documents.
//! Read-only; for writing TOML, use a third-party library.
//!
//! Mirrors: CPython Lib/tomllib/

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const TOMLDecodeError = error{
    InvalidSyntax,
    InvalidKey,
    InvalidValue,
    InvalidDate,
    InvalidTime,
    InvalidDateTime,
    DuplicateKey,
    UnexpectedCharacter,
    UnterminatedString,
    InvalidEscape,
    InvalidNumber,
    OutOfMemory,
};

// ============================================================================
// TOML Value Types
// ============================================================================

/// TOML value types
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: DateTime,
    date: Date,
    time: Time,
    array: std.ArrayList(Value),
    table: hashmap_helper.StringHashMap(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit(allocator);
            },
            .table => |*tbl| {
                var iter = tbl.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                tbl.deinit();
            },
            else => {},
        }
    }
};

/// TOML date
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn format(self: Date, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            self.year, self.month, self.day,
        });
    }
};

/// TOML time
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn format(self: Time, allocator: std.mem.Allocator) ![]u8 {
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.hour, self.minute, self.second, self.microsecond,
            });
        }
        return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.hour, self.minute, self.second,
        });
    }
};

/// TOML datetime
pub const DateTime = struct {
    date: Date,
    time: Time,
    offset: ?i16 = null, // Minutes from UTC

    pub fn format(self: DateTime, allocator: std.mem.Allocator) ![]u8 {
        const date_str = try self.date.format(allocator);
        defer allocator.free(date_str);
        const time_str = try self.time.format(allocator);
        defer allocator.free(time_str);

        if (self.offset) |off| {
            const sign: u8 = if (off >= 0) '+' else '-';
            const abs_off = if (off >= 0) @as(u16, @intCast(off)) else @as(u16, @intCast(-off));
            return std.fmt.allocPrint(allocator, "{s}T{s}{c}{d:0>2}:{d:0>2}", .{
                date_str, time_str, sign, abs_off / 60, abs_off % 60,
            });
        }
        return std.fmt.allocPrint(allocator, "{s}T{s}", .{ date_str, time_str });
    }
};

// ============================================================================
// Parser
// ============================================================================

/// TOML Parser
pub const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    /// Parse the TOML document
    pub fn parse(self: *Self) !hashmap_helper.StringHashMap(Value) {
        var root = hashmap_helper.StringHashMap(Value).init(self.allocator);
        var current_table = &root;

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;

            const c = self.source[self.pos];

            if (c == '[') {
                // Table header
                self.pos += 1;
                const is_array = self.pos < self.source.len and self.source[self.pos] == '[';
                if (is_array) self.pos += 1;

                const key = try self.parseKey();
                _ = key;

                self.skipWhitespace();
                if (self.pos >= self.source.len or self.source[self.pos] != ']') {
                    return error.InvalidSyntax;
                }
                self.pos += 1;
                if (is_array) {
                    if (self.pos >= self.source.len or self.source[self.pos] != ']') {
                        return error.InvalidSyntax;
                    }
                    self.pos += 1;
                }

                // Navigate to/create nested tables from key path like "a.b.c"
                current_table = &root;
                var key_parts = std.mem.splitScalar(u8, key, '.');
                while (key_parts.next()) |part| {
                    if (current_table.get(part)) |existing| {
                        // Table already exists, navigate into it
                        switch (existing) {
                            .table => |*tbl| current_table = tbl,
                            else => return error.InvalidSyntax, // Redefining as table
                        }
                    } else {
                        // Create new nested table
                        var new_table = hashmap_helper.StringHashMap(Value).init(self.allocator);
                        try current_table.put(part, .{ .table = new_table });
                        // Get pointer to the just-inserted table
                        if (current_table.getPtr(part)) |ptr| {
                            current_table = &ptr.table;
                        }
                    }
                }
            } else if (c == '\n') {
                self.pos += 1;
                self.line += 1;
                self.column = 1;
            } else if (c != '#') {
                // Key-value pair
                const key = try self.parseKey();
                self.skipWhitespace();

                if (self.pos >= self.source.len or self.source[self.pos] != '=') {
                    return error.InvalidSyntax;
                }
                self.pos += 1;
                self.skipWhitespace();

                const value = try self.parseValue();
                try current_table.put(key, value);
            }
        }

        return root;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t') {
                self.pos += 1;
                self.column += 1;
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndComments(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t') {
                self.pos += 1;
                self.column += 1;
            } else if (c == '#') {
                // Skip to end of line
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else if (c == '\n') {
                self.pos += 1;
                self.line += 1;
                self.column = 1;
            } else {
                break;
            }
        }
    }

    fn parseKey(self: *Self) ![]const u8 {
        const start = self.pos;

        if (self.pos < self.source.len and self.source[self.pos] == '"') {
            // Quoted key
            return try self.parseBasicString();
        }

        // Bare key
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_' or c == '-')
            {
                self.pos += 1;
            } else {
                break;
            }
        }

        if (self.pos == start) return error.InvalidKey;
        return self.source[start..self.pos];
    }

    fn parseValue(self: *Self) TOMLDecodeError!Value {
        if (self.pos >= self.source.len) return error.InvalidSyntax;

        const c = self.source[self.pos];

        if (c == '"') {
            const s = try self.parseBasicString();
            return Value{ .string = s };
        } else if (c == '\'') {
            const s = try self.parseLiteralString();
            return Value{ .string = s };
        } else if (c == 't' or c == 'f') {
            return try self.parseBoolean();
        } else if (c == '[') {
            return try self.parseArray();
        } else if (c == '{') {
            return try self.parseInlineTable();
        } else if (c == '-' or c == '+' or (c >= '0' and c <= '9')) {
            return try self.parseNumber();
        }

        return error.InvalidValue;
    }

    fn parseBasicString(self: *Self) ![]const u8 {
        if (self.source[self.pos] != '"') return error.InvalidSyntax;
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                self.pos += 2; // Skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        if (self.pos >= self.source.len) return error.UnterminatedString;

        const result = self.source[start..self.pos];
        self.pos += 1; // Skip closing quote
        return result;
    }

    fn parseLiteralString(self: *Self) ![]const u8 {
        if (self.source[self.pos] != '\'') return error.InvalidSyntax;
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '\'') {
            self.pos += 1;
        }

        if (self.pos >= self.source.len) return error.UnterminatedString;

        const result = self.source[start..self.pos];
        self.pos += 1;
        return result;
    }

    fn parseBoolean(self: *Self) !Value {
        if (self.pos + 4 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 4], "true")) {
            self.pos += 4;
            return Value{ .boolean = true };
        } else if (self.pos + 5 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 5], "false")) {
            self.pos += 5;
            return Value{ .boolean = false };
        }
        return error.InvalidValue;
    }

    fn parseNumber(self: *Self) !Value {
        const start = self.pos;
        var is_float = false;

        // Skip sign
        if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
            self.pos += 1;
        }

        // Parse digits
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c >= '0' and c <= '9') {
                self.pos += 1;
            } else if (c == '_') {
                self.pos += 1;
            } else if (c == '.' or c == 'e' or c == 'E') {
                is_float = true;
                self.pos += 1;
            } else {
                break;
            }
        }

        const num_str = self.source[start..self.pos];

        if (is_float) {
            const f = std.fmt.parseFloat(f64, num_str) catch return error.InvalidNumber;
            return Value{ .float = f };
        } else {
            const i = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidNumber;
            return Value{ .integer = i };
        }
    }

    fn parseArray(self: *Self) !Value {
        if (self.source[self.pos] != '[') return error.InvalidSyntax;
        self.pos += 1;

        var arr: std.ArrayList(Value) = .{};

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;

            if (self.source[self.pos] == ']') {
                self.pos += 1;
                break;
            }

            const value = try self.parseValue();
            try arr.append(self.allocator, value);

            self.skipWhitespaceAndComments();
            if (self.pos < self.source.len and self.source[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return Value{ .array = arr };
    }

    fn parseInlineTable(self: *Self) !Value {
        if (self.source[self.pos] != '{') return error.InvalidSyntax;
        self.pos += 1;

        var tbl = hashmap_helper.StringHashMap(Value).init(self.allocator);

        while (self.pos < self.source.len) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;

            if (self.source[self.pos] == '}') {
                self.pos += 1;
                break;
            }

            const key = try self.parseKey();
            self.skipWhitespace();

            if (self.pos >= self.source.len or self.source[self.pos] != '=') {
                return error.InvalidSyntax;
            }
            self.pos += 1;
            self.skipWhitespace();

            const value = try self.parseValue();
            try tbl.put(key, value);

            self.skipWhitespace();
            if (self.pos < self.source.len and self.source[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return Value{ .table = tbl };
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Parse a TOML string
pub fn loads(allocator: std.mem.Allocator, s: []const u8) !hashmap_helper.StringHashMap(Value) {
    var parser = Parser.init(allocator, s);
    return parser.parse();
}

/// Parse a TOML file
pub fn load(allocator: std.mem.Allocator, fp: std.fs.File) !hashmap_helper.StringHashMap(Value) {
    const content = try fp.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);
    return loads(allocator, content);
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Date format" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2024, .month = 1, .day = 15 };
    const s = try date.format(allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("2024-01-15", s);
}

test "Time format" {
    const allocator = std.testing.allocator;
    const time = Time{ .hour = 14, .minute = 30, .second = 0 };
    const s = try time.format(allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("14:30:00", s);
}

test "loads simple" {
    const allocator = std.testing.allocator;
    const toml = "name = \"test\"\nvalue = 42";
    var result = try loads(allocator, toml);
    defer {
        var iter = result.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        result.deinit();
    }

    try std.testing.expect(result.contains("name"));
    try std.testing.expect(result.contains("value"));
}

test "loads boolean" {
    const allocator = std.testing.allocator;
    const toml = "enabled = true\ndisabled = false";
    var result = try loads(allocator, toml);
    defer {
        var iter = result.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        result.deinit();
    }

    try std.testing.expect(result.get("enabled").?.boolean == true);
    try std.testing.expect(result.get("disabled").?.boolean == false);
}

test "loads array" {
    const allocator = std.testing.allocator;
    const toml = "items = [1, 2, 3]";
    var result = try loads(allocator, toml);
    defer {
        var iter = result.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        result.deinit();
    }

    const items = result.get("items").?.array;
    try std.testing.expectEqual(@as(usize, 3), items.items.len);
}
