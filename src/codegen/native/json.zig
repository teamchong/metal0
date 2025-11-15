/// JSON module - json.loads() and json.dumps() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for json.loads(json_string)
/// NOTE: Leaks arena allocator - std.json.parseFromSlice allocates internal arena
/// Memory is freed at program exit (acceptable for short-lived AOT programs)
/// TODO: Implement scope-based cleanup for long-running programs
pub fn genJsonLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Parse JSON and extract value
    // parseFromSlice creates internal arena - we extract value but don't deinit the Parsed struct
    // This leaks the arena but memory is reclaimed at program exit
    try self.output.appendSlice(self.allocator, "blk: { const parsed = try std.json.parseFromSlice(std.json.Value, allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", .{}); break :blk parsed.value; }");
}

/// Generate code for json.dumps(obj)
/// Maps to: std.json.stringifyAlloc(allocator, value, .{})
pub fn genJsonDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate: std.json.stringifyAlloc(allocator, value, .{})
    try self.output.appendSlice(self.allocator, "std.json.stringifyAlloc(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", .{})");
}
