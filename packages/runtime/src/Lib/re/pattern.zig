/// Pattern compilation and management for 're' module
const std = @import("std");
const runtime = @import("../../runtime.zig");
const types = @import("types.zig");

pub const CompiledPattern = types.CompiledPattern;
pub const Regex = types.Regex;

/// Python re flags (subset - ignoring flags for now in basic implementation)
pub const IGNORECASE: i64 = 2;
pub const MULTILINE: i64 = 8;
pub const DOTALL: i64 = 16;
pub const VERBOSE: i64 = 64;

/// Python-compatible compile() function
/// Usage: pattern = re.compile(r"hello")
pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !*runtime.PyObject {
    return compileWithFlags(allocator, pattern, 0);
}

/// compile with flags
pub fn compileWithFlags(allocator: std.mem.Allocator, pattern: []const u8, flags: i64) !*runtime.PyObject {
    // Transform pattern based on flags
    var actual_pattern = pattern;
    if (flags & IGNORECASE != 0) {
        // For case-insensitive, we'd need to transform the pattern
        // Basic approach: wrap in (?i) if regex engine supports it
        const prefixed = try std.fmt.allocPrint(allocator, "(?i){s}", .{pattern});
        actual_pattern = prefixed;
    }

    // Compile the regex
    const regex = try Regex.compile(allocator, actual_pattern);

    // Create compiled pattern object
    const compiled = try allocator.create(CompiledPattern);
    compiled.* = .{
        .regex = regex,
        .pattern = try allocator.dupe(u8, pattern),
        .flags = flags,
        .allocator = allocator,
    };

    // Wrap in PyObject as opaque pointer
    // Using .object type_id since regex is an object type
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .object,
        .data = @ptrCast(compiled),
    };

    return obj;
}

/// Create a None PyObject
pub fn createNone(allocator: std.mem.Allocator) !*runtime.PyObject {
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .none,
        .data = undefined,
    };
    return obj;
}

test "re.compile basic" {
    const allocator = std.testing.allocator;

    const pattern_obj = try compile(allocator, "hello");
    defer runtime.decref(pattern_obj, allocator);

    try std.testing.expect(pattern_obj.ref_count == 1);
}
