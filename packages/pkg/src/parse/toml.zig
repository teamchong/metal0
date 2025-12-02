//! TOML Parser
//!
//! Minimal TOML parser for pyproject.toml files.
//! Supports: strings, arrays, tables, inline tables, basic types.
//!
//! Reference: https://toml.io/en/v1.0.0

const std = @import("std");

pub const TomlError = error{
    UnexpectedCharacter,
    UnterminatedString,
    InvalidEscape,
    InvalidNumber,
    UnexpectedEOF,
    InvalidKey,
    DuplicateKey,
    InvalidTable,
    OutOfMemory,
};

/// TOML Value types
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const Value,
    table: Table,

    pub fn getString(self: Value) ?[]const u8 {
        return if (self == .string) self.string else null;
    }

    pub fn getInt(self: Value) ?i64 {
        return if (self == .integer) self.integer else null;
    }

    pub fn getBool(self: Value) ?bool {
        return if (self == .boolean) self.boolean else null;
    }

    pub fn getArray(self: Value) ?[]const Value {
        return if (self == .array) self.array else null;
    }

    pub fn getTable(self: Value) ?Table {
        return if (self == .table) self.table else null;
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*v| {
                    var mv = @constCast(v);
                    mv.deinit(allocator);
                }
                allocator.free(arr);
            },
            .table => |*t| {
                var mt = @constCast(t);
                mt.deinit(allocator);
            },
            else => {},
        }
    }
};

/// TOML Table (key-value pairs)
pub const Table = struct {
    entries: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{ .entries = std.StringHashMap(Value).init(allocator) };
    }

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            var v = entry.value_ptr;
            v.deinit(allocator);
        }
        self.entries.deinit();
    }

    pub fn get(self: Table, key: []const u8) ?Value {
        return self.entries.get(key);
    }

    pub fn getTable(self: Table, key: []const u8) ?Table {
        if (self.entries.get(key)) |v| {
            return v.getTable();
        }
        return null;
    }

    pub fn getString(self: Table, key: []const u8) ?[]const u8 {
        if (self.entries.get(key)) |v| {
            return v.getString();
        }
        return null;
    }

    pub fn getArray(self: Table, key: []const u8) ?[]const Value {
        if (self.entries.get(key)) |v| {
            return v.getArray();
        }
        return null;
    }
};

/// TOML Parser
pub const Parser = struct {
    source: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{
            .source = source,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) TomlError!Table {
        var root = Table.init(self.allocator);
        errdefer root.deinit(self.allocator);

        var current_table: *Table = &root;
        var current_path = std.ArrayList([]const u8){};
        defer {
            for (current_path.items) |key| self.allocator.free(key);
            current_path.deinit(self.allocator);
        }

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;

            const c = self.source[self.pos];

            if (c == '[') {
                // Table header
                self.pos += 1;
                const is_array_table = self.pos < self.source.len and self.source[self.pos] == '[';
                if (is_array_table) self.pos += 1;

                // Parse table path (free old keys first)
                for (current_path.items) |old_key| {
                    self.allocator.free(old_key);
                }
                current_path.clearRetainingCapacity();
                while (true) {
                    self.skipWhitespace();
                    const key = try self.parseKey();
                    current_path.append(self.allocator, key) catch return error.OutOfMemory;
                    self.skipWhitespace();
                    if (self.pos >= self.source.len) return error.InvalidTable;
                    if (self.source[self.pos] == ']') break;
                    if (self.source[self.pos] != '.') return error.InvalidTable;
                    self.pos += 1;
                }
                self.pos += 1; // skip ]
                if (is_array_table) {
                    if (self.pos >= self.source.len or self.source[self.pos] != ']') return error.InvalidTable;
                    self.pos += 1;
                }

                // Navigate to or create the table
                current_table = &root;
                for (current_path.items) |path_key| {
                    // Create nested table if it doesn't exist
                    if (!current_table.entries.contains(path_key)) {
                        const key_copy = self.allocator.dupe(u8, path_key) catch return error.OutOfMemory;
                        const new_table = Table.init(self.allocator);
                        current_table.entries.put(key_copy, .{ .table = new_table }) catch return error.OutOfMemory;
                    }
                    // Navigate into the table
                    if (current_table.entries.getPtr(path_key)) |ptr| {
                        if (ptr.* == .table) {
                            current_table = &ptr.table;
                        }
                    }
                }
            } else if (c == '\n' or c == '\r') {
                self.pos += 1;
            } else {
                // Key-value pair
                const key = try self.parseKey();
                self.skipWhitespace();
                if (self.pos >= self.source.len or self.source[self.pos] != '=') {
                    self.allocator.free(key);
                    return error.InvalidKey;
                }
                self.pos += 1; // skip =
                self.skipWhitespace();
                const value = try self.parseValue();

                // Handle dotted keys (e.g., project.name = "foo")
                var target = current_table;
                var key_parts = std.ArrayList([]const u8){};
                defer key_parts.deinit(self.allocator);

                // Split key by dots (simple split, doesn't handle quoted dots)
                var start: usize = 0;
                for (key, 0..) |kc, ki| {
                    if (kc == '.') {
                        key_parts.append(self.allocator, key[start..ki]) catch return error.OutOfMemory;
                        start = ki + 1;
                    }
                }
                key_parts.append(self.allocator, key[start..]) catch return error.OutOfMemory;

                // Navigate to nested table for all but last key part
                for (key_parts.items[0 .. key_parts.items.len - 1]) |part| {
                    if (!target.entries.contains(part)) {
                        const part_copy = self.allocator.dupe(u8, part) catch return error.OutOfMemory;
                        const nested = Table.init(self.allocator);
                        target.entries.put(part_copy, .{ .table = nested }) catch return error.OutOfMemory;
                    }
                    if (target.entries.getPtr(part)) |ptr| {
                        if (ptr.* == .table) {
                            target = &ptr.table;
                        }
                    }
                }

                const final_key = key_parts.items[key_parts.items.len - 1];
                const final_key_copy = self.allocator.dupe(u8, final_key) catch return error.OutOfMemory;
                target.entries.put(final_key_copy, value) catch return error.OutOfMemory;
                self.allocator.free(key);
            }
        }

        return root;
    }

    fn parseKey(self: *Parser) TomlError![]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return error.UnexpectedEOF;

        const c = self.source[self.pos];

        // Quoted key
        if (c == '"' or c == '\'') {
            return self.parseString();
        }

        // Bare key
        const start = self.pos;
        while (self.pos < self.source.len) {
            const kc = self.source[self.pos];
            if (std.ascii.isAlphanumeric(kc) or kc == '_' or kc == '-') {
                self.pos += 1;
            } else {
                break;
            }
        }
        if (self.pos == start) return error.InvalidKey;
        return self.allocator.dupe(u8, self.source[start..self.pos]) catch error.OutOfMemory;
    }

    fn parseValue(self: *Parser) TomlError!Value {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return error.UnexpectedEOF;

        const c = self.source[self.pos];

        // String
        if (c == '"' or c == '\'') {
            const s = try self.parseString();
            return .{ .string = s };
        }

        // Array
        if (c == '[') {
            return self.parseArray();
        }

        // Inline table
        if (c == '{') {
            return self.parseInlineTable();
        }

        // Boolean
        if (self.source.len >= self.pos + 4) {
            if (std.mem.eql(u8, self.source[self.pos .. self.pos + 4], "true")) {
                self.pos += 4;
                return .{ .boolean = true };
            }
        }
        if (self.source.len >= self.pos + 5) {
            if (std.mem.eql(u8, self.source[self.pos .. self.pos + 5], "false")) {
                self.pos += 5;
                return .{ .boolean = false };
            }
        }

        // Number
        return self.parseNumber();
    }

    fn parseString(self: *Parser) TomlError![]const u8 {
        const quote = self.source[self.pos];
        self.pos += 1;

        // Check for multi-line string
        const is_multiline = self.pos + 1 < self.source.len and
            self.source[self.pos] == quote and
            self.source[self.pos + 1] == quote;
        if (is_multiline) {
            self.pos += 2;
            // Skip initial newline
            if (self.pos < self.source.len and self.source[self.pos] == '\n') {
                self.pos += 1;
            } else if (self.pos + 1 < self.source.len and
                self.source[self.pos] == '\r' and self.source[self.pos + 1] == '\n')
            {
                self.pos += 2;
            }
        }

        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            // Check for end of string
            if (is_multiline) {
                if (self.pos + 2 < self.source.len and
                    self.source[self.pos] == quote and
                    self.source[self.pos + 1] == quote and
                    self.source[self.pos + 2] == quote)
                {
                    self.pos += 3;
                    return result.toOwnedSlice(self.allocator) catch error.OutOfMemory;
                }
            } else {
                if (c == quote) {
                    self.pos += 1;
                    return result.toOwnedSlice(self.allocator) catch error.OutOfMemory;
                }
                if (c == '\n') return error.UnterminatedString;
            }

            // Handle escapes in double-quoted strings
            if (c == '\\' and quote == '"') {
                self.pos += 1;
                if (self.pos >= self.source.len) return error.InvalidEscape;
                const escaped = self.source[self.pos];
                self.pos += 1;
                const replacement: u8 = switch (escaped) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    else => return error.InvalidEscape,
                };
                result.append(self.allocator, replacement) catch return error.OutOfMemory;
            } else {
                result.append(self.allocator, c) catch return error.OutOfMemory;
                self.pos += 1;
            }
        }

        return error.UnterminatedString;
    }

    fn parseArray(self: *Parser) TomlError!Value {
        self.pos += 1; // skip [

        var items = std.ArrayList(Value){};
        errdefer {
            for (items.items) |*v| v.deinit(self.allocator);
            items.deinit(self.allocator);
        }

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) return error.UnexpectedEOF;

            if (self.source[self.pos] == ']') {
                self.pos += 1;
                return .{ .array = items.toOwnedSlice(self.allocator) catch return error.OutOfMemory };
            }

            const value = try self.parseValue();
            items.append(self.allocator, value) catch return error.OutOfMemory;

            self.skipWhitespaceAndComments();
            if (self.pos < self.source.len and self.source[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return error.UnexpectedEOF;
    }

    fn parseInlineTable(self: *Parser) TomlError!Value {
        self.pos += 1; // skip {

        var table = Table.init(self.allocator);
        errdefer table.deinit(self.allocator);

        while (self.pos < self.source.len) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) return error.UnexpectedEOF;

            if (self.source[self.pos] == '}') {
                self.pos += 1;
                return .{ .table = table };
            }

            const key = try self.parseKey();
            self.skipWhitespace();
            if (self.pos >= self.source.len or self.source[self.pos] != '=') {
                self.allocator.free(key);
                return error.InvalidKey;
            }
            self.pos += 1;
            self.skipWhitespace();
            const value = try self.parseValue();

            table.entries.put(key, value) catch return error.OutOfMemory;

            self.skipWhitespace();
            if (self.pos < self.source.len and self.source[self.pos] == ',') {
                self.pos += 1;
            }
        }

        return error.UnexpectedEOF;
    }

    fn parseNumber(self: *Parser) TomlError!Value {
        const start = self.pos;
        var has_dot = false;

        // Handle sign
        if (self.pos < self.source.len and (self.source[self.pos] == '-' or self.source[self.pos] == '+')) {
            self.pos += 1;
        }

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isDigit(c) or c == '_') {
                self.pos += 1;
            } else if (c == '.' and !has_dot) {
                has_dot = true;
                self.pos += 1;
            } else if (c == 'e' or c == 'E') {
                has_dot = true; // treat as float
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '-' or self.source[self.pos] == '+')) {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }

        if (self.pos == start) return error.InvalidNumber;

        // Remove underscores for parsing
        var clean = std.ArrayList(u8){};
        defer clean.deinit(self.allocator);
        for (self.source[start..self.pos]) |c| {
            if (c != '_') clean.append(self.allocator, c) catch return error.OutOfMemory;
        }

        if (has_dot) {
            const f = std.fmt.parseFloat(f64, clean.items) catch return error.InvalidNumber;
            return .{ .float = f };
        } else {
            const i = std.fmt.parseInt(i64, clean.items, 10) catch return error.InvalidNumber;
            return .{ .integer = i };
        }
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '#') {
                // Skip to end of line
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }
};

/// Parse TOML from string
pub fn parse(allocator: std.mem.Allocator, source: []const u8) TomlError!Table {
    var parser = Parser.init(allocator, source);
    return parser.parse();
}

/// Parse TOML from file
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !Table {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);
    return parse(allocator, content);
}

test "parse basic string" {
    const allocator = std.testing.allocator;
    const source = "name = \"hello\"";
    var table = try parse(allocator, source);
    defer table.deinit(allocator);
    try std.testing.expectEqualStrings("hello", table.getString("name").?);
}

test "parse array" {
    const allocator = std.testing.allocator;
    const source = "deps = [\"numpy\", \"pandas\"]";
    var table = try parse(allocator, source);
    defer table.deinit(allocator);
    const arr = table.getArray("deps").?;
    try std.testing.expectEqual(@as(usize, 2), arr.len);
    try std.testing.expectEqualStrings("numpy", arr[0].getString().?);
    try std.testing.expectEqualStrings("pandas", arr[1].getString().?);
}

test "parse boolean" {
    const allocator = std.testing.allocator;
    const source = "enabled = true\ndisabled = false";
    var table = try parse(allocator, source);
    defer table.deinit(allocator);
    try std.testing.expect(table.get("enabled").?.getBool().?);
    try std.testing.expect(!table.get("disabled").?.getBool().?);
}

test "parse number" {
    const allocator = std.testing.allocator;
    const source = "count = 42\nprice = 3.14";
    var table = try parse(allocator, source);
    defer table.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 42), table.get("count").?.getInt().?);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), table.get("price").?.float, 0.001);
}
