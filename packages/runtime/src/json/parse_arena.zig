/// Arena-based JSON Parser - Maximum performance for json.loads()
///
/// Key optimizations:
/// 1. Single arena allocation for entire parse (bump pointer = 2 cycles)
/// 2. Small integer cache (-10 to 256) - avoids allocation for common ints
/// 3. Key interning for repeated dictionary keys
/// 4. SIMD whitespace skipping
/// 5. SWAR string scanning (8 bytes at a time)
///
/// Memory strategy:
/// - All PyObjects, PyDict, PyList, strings allocated from arena
/// - Arena attached to root PyObject via arena_ptr field
/// - When root is freed, entire arena is freed at once
const std = @import("std");
const runtime = @import("../runtime.zig");
const JsonArena = @import("arena.zig").JsonArena;
const simd = @import("json_simd");
const JsonError = @import("errors.zig").JsonError;
const ParseResult = @import("errors.zig").ParseResult;
const hashmap_helper = @import("hashmap_helper");

/// Thread-local key cache for interning (avoids repeated allocations)
/// Using hash-based lookup instead of linear scan for O(1) cache checks
const KEY_CACHE_SIZE = 64; // Power of 2 for fast modulo
threadlocal var key_cache: [KEY_CACHE_SIZE][]const u8 = [_][]const u8{""} ** KEY_CACHE_SIZE;
threadlocal var key_cache_hash: [KEY_CACHE_SIZE]u32 = [_]u32{0} ** KEY_CACHE_SIZE;

/// Thread-local arena for current parse operation
threadlocal var current_arena: ?*JsonArena = null;

/// Small integer cache (PyPy style: -10 to 256)
/// Pre-allocated PyObjects for common small integers - avoids arena allocation
const INT_CACHE_START: i64 = -10;
const INT_CACHE_END: i64 = 257; // exclusive
const INT_CACHE_SIZE = INT_CACHE_END - INT_CACHE_START;

/// Static storage for cached integers (allocated once at startup)
var int_cache_storage: [INT_CACHE_SIZE]runtime.PyObject = undefined;
var int_cache_data: [INT_CACHE_SIZE]runtime.PyInt = undefined;
var int_cache_initialized: bool = false;

/// Initialize small integer cache (called once)
fn initIntCache() void {
    if (int_cache_initialized) return;

    for (0..INT_CACHE_SIZE) |idx| {
        const value: i64 = @as(i64, @intCast(idx)) + INT_CACHE_START;
        int_cache_data[idx] = .{ .value = value };
        int_cache_storage[idx] = .{
            .ref_count = 1, // Never freed
            .type_id = .int,
            .data = &int_cache_data[idx],
            .arena_ptr = null,
        };
    }
    int_cache_initialized = true;
}

/// Get cached integer if in range, otherwise null
inline fn getCachedInt(value: i64) ?*runtime.PyObject {
    if (value >= INT_CACHE_START and value < INT_CACHE_END) {
        const idx: usize = @intCast(value - INT_CACHE_START);
        return &int_cache_storage[idx];
    }
    return null;
}

/// Fast hash for key interning (wyhash for speed)
inline fn quickHash(key: []const u8) u32 {
    // Simple fast hash - FNV-1a style but faster
    var h: u32 = 2166136261;
    for (key) |c| {
        h = (h ^ c) *% 16777619;
    }
    return h;
}

/// Intern a key string - returns cached version if seen recently
/// O(1) hash-based lookup instead of O(n) linear scan
fn internKey(key: []const u8, arena: *JsonArena) ![]const u8 {
    const hash = quickHash(key);
    const slot = hash & (KEY_CACHE_SIZE - 1); // Fast modulo for power of 2

    // Check if this slot has our key (hash + string match)
    if (key_cache_hash[slot] == hash and std.mem.eql(u8, key_cache[slot], key)) {
        return key_cache[slot]; // Cache hit!
    }

    // Cache miss - allocate and cache
    const owned = try arena.dupeString(key);

    // Store in cache (overwrites previous)
    key_cache[slot] = owned;
    key_cache_hash[slot] = hash;

    return owned;
}

/// SIMD whitespace skip
inline fn skipWhitespace(data: []const u8, pos: usize) usize {
    return simd.skipWhitespace(data, pos);
}

/// Main entry: Parse JSON with arena allocation
/// Returns a PyObject with arena attached (arena freed when object freed)
pub fn parseWithArena(data: []const u8, backing_allocator: std.mem.Allocator) JsonError!*runtime.PyObject {
    // Estimate arena size: 4x input size is usually enough
    // (JSON objects expand due to struct overhead)
    const arena_size = @max(JsonArena.DEFAULT_SIZE, data.len * 4);

    const arena = JsonArena.init(backing_allocator, arena_size) catch return JsonError.OutOfMemory;
    errdefer arena.decref();

    // Initialize small integer cache (once per process)
    initIntCache();

    // Set thread-local for nested parsing
    current_arena = arena;
    defer current_arena = null;

    // Reset key cache for this parse (clear hashes to invalidate)
    @memset(&key_cache_hash, 0);

    const i = skipWhitespace(data, 0);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const result = try parseValue(data, i, arena);

    // Check for trailing content
    const final_pos = skipWhitespace(data, i + result.consumed);
    if (final_pos < data.len) {
        return JsonError.UnexpectedToken;
    }

    // Attach arena to root object for lifetime management
    // When root is freed, arena is freed
    result.value.arena_ptr = arena;

    return result.value;
}

/// Parse any JSON value
fn parseValue(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    const i = skipWhitespace(data, pos);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const c = data[i];
    return switch (c) {
        '{' => parseObject(data, i, arena),
        '[' => parseArray(data, i, arena),
        '"' => parseString(data, i, arena),
        '-', '0'...'9' => parseNumber(data, i, arena),
        'n' => parseNull(data, i, arena),
        't' => parseTrue(data, i, arena),
        'f' => parseFalse(data, i, arena),
        else => JsonError.UnexpectedToken,
    };
}

/// Parse null literal
fn parseNull(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos..][0..4], "null")) return JsonError.UnexpectedToken;

    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    obj.* = .{
        .ref_count = 1,
        .type_id = .none,
        .data = undefined,
        .arena_ptr = null,
    };
    return ParseResult(*runtime.PyObject).init(obj, 4);
}

/// Parse true literal
fn parseTrue(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos..][0..4], "true")) return JsonError.UnexpectedToken;

    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const int_data = arena.alloc(runtime.PyInt) catch return JsonError.OutOfMemory;
    int_data.* = .{ .value = 1 };
    obj.* = .{
        .ref_count = 1,
        .type_id = .bool,
        .data = int_data,
        .arena_ptr = null,
    };
    return ParseResult(*runtime.PyObject).init(obj, 4);
}

/// Parse false literal
fn parseFalse(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos + 5 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos..][0..5], "false")) return JsonError.UnexpectedToken;

    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const int_data = arena.alloc(runtime.PyInt) catch return JsonError.OutOfMemory;
    int_data.* = .{ .value = 0 };
    obj.* = .{
        .ref_count = 1,
        .type_id = .bool,
        .data = int_data,
        .arena_ptr = null,
    };
    return ParseResult(*runtime.PyObject).init(obj, 5);
}

/// Parse number (integer or float) - uses small int cache for common values
fn parseNumber(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    var i = pos;
    var is_float = false;

    // Optional minus
    if (i < data.len and data[i] == '-') i += 1;

    // Integer part
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;
    if (data[i] == '0') {
        i += 1;
    } else if (data[i] >= '1' and data[i] <= '9') {
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
    } else {
        return JsonError.UnexpectedToken;
    }

    // Fractional part
    if (i < data.len and data[i] == '.') {
        is_float = true;
        i += 1;
        if (i >= data.len or data[i] < '0' or data[i] > '9') return JsonError.UnexpectedToken;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
    }

    // Exponent
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        is_float = true;
        i += 1;
        if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
        if (i >= data.len or data[i] < '0' or data[i] > '9') return JsonError.UnexpectedToken;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
    }

    const num_str = data[pos..i];

    if (is_float) {
        const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
        const float_data = arena.alloc(runtime.PyFloat) catch return JsonError.OutOfMemory;
        float_data.* = .{
            .value = std.fmt.parseFloat(f64, num_str) catch return JsonError.InvalidNumber,
        };
        obj.* = .{
            .ref_count = 1,
            .type_id = .float,
            .data = float_data,
            .arena_ptr = null,
        };
        return ParseResult(*runtime.PyObject).init(obj, i - pos);
    }

    // Parse integer
    const int_value = std.fmt.parseInt(i64, num_str, 10) catch return JsonError.InvalidNumber;

    // Check small integer cache first (avoids allocation!)
    if (getCachedInt(int_value)) |cached| {
        return ParseResult(*runtime.PyObject).init(cached, i - pos);
    }

    // Not in cache - allocate from arena
    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const int_data = arena.alloc(runtime.PyInt) catch return JsonError.OutOfMemory;
    int_data.* = .{
        .value = int_value,
    };
    obj.* = .{
        .ref_count = 1,
        .type_id = .int,
        .data = int_data,
        .arena_ptr = null,
    };

    return ParseResult(*runtime.PyObject).init(obj, i - pos);
}

/// Parse string (uses SIMD for fast quote/escape detection)
fn parseString(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    // Use SIMD to find closing quote AND detect escapes in single pass
    const str_start = pos + 1;
    const result = simd.findClosingQuoteAndEscapes(data[str_start..]) orelse
        return JsonError.UnexpectedEndOfInput;

    const i = str_start + result.quote_pos;
    const has_escape = result.has_escapes;

    const str_content = data[str_start..i];
    const consumed = i + 1 - pos;

    // Allocate string content
    var final_str: []const u8 = undefined;
    if (has_escape) {
        // Need to unescape
        final_str = unescapeString(str_content, arena) catch return JsonError.OutOfMemory;
    } else {
        // Zero-copy: just duplicate into arena
        final_str = arena.dupeString(str_content) catch return JsonError.OutOfMemory;
    }

    // Create PyString
    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const str_data = arena.alloc(runtime.PyString) catch return JsonError.OutOfMemory;
    str_data.* = .{
        .data = final_str,
        .source = null, // Owned by arena (arena handles cleanup)
    };
    obj.* = .{
        .ref_count = 1,
        .type_id = .string,
        .data = str_data,
        .arena_ptr = null,
    };

    return ParseResult(*runtime.PyObject).init(obj, consumed);
}

/// Unescape JSON string - optimized to copy non-escape segments in bulk
fn unescapeString(str: []const u8, arena: *JsonArena) ![]const u8 {
    // Allocate max possible size
    const dest = try arena.allocSlice(u8, str.len);
    var j: usize = 0;
    var i: usize = 0;

    while (i < str.len) {
        // Find next backslash (start of escape sequence)
        const copy_start = i;
        while (i < str.len and str[i] != '\\') : (i += 1) {}

        // Bulk copy non-escape segment
        const copy_len = i - copy_start;
        if (copy_len > 0) {
            @memcpy(dest[j..][0..copy_len], str[copy_start..][0..copy_len]);
            j += copy_len;
        }

        // Handle escape sequence if found
        if (i < str.len and str[i] == '\\' and i + 1 < str.len) {
            const escape_char = str[i + 1];
            switch (escape_char) {
                '"' => dest[j] = '"',
                '\\' => dest[j] = '\\',
                '/' => dest[j] = '/',
                'b' => dest[j] = '\x08',
                'f' => dest[j] = '\x0C',
                'n' => dest[j] = '\n',
                'r' => dest[j] = '\r',
                't' => dest[j] = '\t',
                'u' => {
                    // Unicode escape: \uXXXX
                    if (i + 6 <= str.len) {
                        const hex = str[i + 2 .. i + 6];
                        const code = std.fmt.parseInt(u16, hex, 16) catch {
                            dest[j] = '?';
                            j += 1;
                            i += 6;
                            continue;
                        };
                        // Simple ASCII handling for now
                        if (code < 128) {
                            dest[j] = @truncate(code);
                        } else {
                            // UTF-8 encode (simplified)
                            dest[j] = '?';
                        }
                        j += 1;
                        i += 6;
                        continue;
                    }
                    dest[j] = '?';
                },
                else => dest[j] = escape_char,
            }
            j += 1;
            i += 2;
        }
    }

    return dest[0..j];
}

/// Parse array
fn parseArray(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '[') return JsonError.UnexpectedToken;

    // Create PyList with arena allocator
    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const list_data = arena.alloc(runtime.PyList) catch return JsonError.OutOfMemory;

    // Initialize with arena allocator
    list_data.* = .{
        .items = .{},
        .allocator = arena.allocator(),
    };
    obj.* = .{
        .ref_count = 1,
        .type_id = .list,
        .data = list_data,
        .arena_ptr = null,
    };

    var i = skipWhitespace(data, pos + 1);

    // Empty array
    if (i < data.len and data[i] == ']') {
        return ParseResult(*runtime.PyObject).init(obj, i + 1 - pos);
    }

    // Parse elements
    while (true) {
        const value_result = try parseValue(data, i, arena);
        list_data.items.append(arena.allocator(), value_result.value) catch return JsonError.OutOfMemory;
        i += value_result.consumed;

        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        if (data[i] == ']') {
            return ParseResult(*runtime.PyObject).init(obj, i + 1 - pos);
        } else if (data[i] == ',') {
            i = skipWhitespace(data, i + 1);
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}

/// Quick count of object keys (for pre-sizing dict)
/// Returns 0 if can't determine (falls back to dynamic sizing)
fn countObjectKeys(data: []const u8, pos: usize) usize {
    if (pos >= data.len or data[pos] != '{') return 0;

    var count: usize = 0;
    var i = pos + 1;
    var depth: usize = 1;

    while (i < data.len and depth > 0) {
        const c = data[i];
        switch (c) {
            '"' => {
                // Skip string
                i += 1;
                while (i < data.len) {
                    if (data[i] == '\\') {
                        i += 2;
                    } else if (data[i] == '"') {
                        i += 1;
                        break;
                    } else {
                        i += 1;
                    }
                }
                // Count as a key if we're at depth 1 and next non-ws is ':'
                if (depth == 1) {
                    var j = i;
                    while (j < data.len and (data[j] == ' ' or data[j] == '\t' or data[j] == '\n' or data[j] == '\r')) : (j += 1) {}
                    if (j < data.len and data[j] == ':') {
                        count += 1;
                    }
                }
            },
            '{', '[' => {
                depth += 1;
                i += 1;
            },
            '}', ']' => {
                depth -= 1;
                i += 1;
            },
            else => i += 1,
        }
    }

    return count;
}

/// Parse object (dict)
fn parseObject(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '{') return JsonError.UnexpectedToken;

    // Create PyDict with arena allocator
    const obj = arena.alloc(runtime.PyObject) catch return JsonError.OutOfMemory;
    const dict_data = arena.alloc(runtime.PyDict) catch return JsonError.OutOfMemory;

    // Use @TypeOf to get the exact map type from PyDict to avoid module path conflicts
    dict_data.* = .{
        .map = @TypeOf(dict_data.map).init(arena.allocator()),
    };
    obj.* = .{
        .ref_count = 1,
        .type_id = .dict,
        .data = dict_data,
        .arena_ptr = null,
    };

    var i = skipWhitespace(data, pos + 1);

    // Empty object
    if (i < data.len and data[i] == '}') {
        return ParseResult(*runtime.PyObject).init(obj, i + 1 - pos);
    }

    // Note: Pre-sizing was tested but double-scanning hurts performance
    // Arena allocator already handles the resize overhead efficiently

    // Parse key-value pairs
    while (true) {
        // Parse key (must be string)
        if (i >= data.len or data[i] != '"') return JsonError.UnexpectedToken;

        // Parse key string directly (no PyObject wrapper needed)
        const key_result = try parseKeyString(data, i, arena);
        i += key_result.consumed;

        // Expect colon
        i = skipWhitespace(data, i);
        if (i >= data.len or data[i] != ':') return JsonError.UnexpectedToken;
        i = skipWhitespace(data, i + 1);

        // Parse value
        const value_result = try parseValue(data, i, arena);
        i += value_result.consumed;

        // Add to dict (no resize needed - we pre-sized!)
        dict_data.map.put(key_result.value, value_result.value) catch return JsonError.OutOfMemory;

        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        if (data[i] == '}') {
            return ParseResult(*runtime.PyObject).init(obj, i + 1 - pos);
        } else if (data[i] == ',') {
            i = skipWhitespace(data, i + 1);
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}

/// Parse key string - returns raw string (with interning, uses SIMD)
fn parseKeyString(data: []const u8, pos: usize, arena: *JsonArena) JsonError!ParseResult([]const u8) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    // Use SIMD to find closing quote AND detect escapes in single pass
    const key_start = pos + 1;
    const result = simd.findClosingQuoteAndEscapes(data[key_start..]) orelse
        return JsonError.UnexpectedEndOfInput;

    const i = key_start + result.quote_pos;
    const has_escape = result.has_escapes;

    const key_content = data[key_start..i];
    const consumed = i + 1 - pos;

    var final_key: []const u8 = undefined;
    if (has_escape) {
        final_key = unescapeString(key_content, arena) catch return JsonError.OutOfMemory;
    } else {
        // Use key interning for non-escaped keys
        final_key = internKey(key_content, arena) catch return JsonError.OutOfMemory;
    }

    return ParseResult([]const u8).init(final_key, consumed);
}
