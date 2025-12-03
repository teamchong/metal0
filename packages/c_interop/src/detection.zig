// Import Detection Module
// Scans AST for import statements and detects C library dependencies

const std = @import("std");
const mapper = @import("mapper.zig");
const registry = @import("registry.zig");

/// Detected import information
pub const DetectedImport = struct {
    package_name: []const u8,
    alias: ?[]const u8,
    mapping: *const mapper.CLibraryMapping,
};

/// Context for tracking detected imports during compilation
pub const ImportContext = struct {
    imports: std.ArrayList(DetectedImport),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImportContext {
        return .{
            .imports = std.ArrayList(DetectedImport){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportContext) void {
        self.imports.deinit(self.allocator);
    }

    /// Register an import statement
    pub fn registerImport(
        self: *ImportContext,
        package_name: []const u8,
        alias: ?[]const u8,
    ) !void {
        const reg = try registry.getGlobalRegistry();

        // Check if this package has a C library mapping
        if (reg.findByPackage(package_name)) |mapping| {
            try self.imports.append(self.allocator, .{
                .package_name = package_name,
                .alias = alias,
                .mapping = mapping,
            });

            std.debug.print("[C Interop] Detected mapped package: {s}", .{package_name});
            if (alias) |a| {
                std.debug.print(" as {s}", .{a});
            }
            std.debug.print("\n", .{});
        }
    }

    /// Check if a function call should be mapped to C
    pub fn shouldMapFunction(
        self: *const ImportContext,
        func_name: []const u8,
    ) ?*const mapper.FunctionMapping {
        const reg = registry.getGlobalRegistry() catch return null;

        // Try direct lookup (e.g., "sqlite3.connect")
        if (reg.findFunction(func_name)) |mapping| {
            return mapping;
        }

        // Try with alias replacement (e.g., "db.connect" → "sqlite3.connect")
        for (self.imports.items) |import| {
            if (import.alias) |alias| {
                if (std.mem.startsWith(u8, func_name, alias)) {
                    // Replace alias with package name
                    const after_dot = func_name[alias.len..];

                    var buf: [256]u8 = undefined;
                    const full_name = std.fmt.bufPrint(
                        &buf,
                        "{s}{s}",
                        .{ import.package_name, after_dot },
                    ) catch continue;

                    if (reg.findFunction(full_name)) |mapping| {
                        return mapping;
                    }
                }
            }
        }

        return null;
    }

    /// Get all required C libraries for linking
    pub fn getRequiredLibraries(self: *const ImportContext) []const mapper.LibraryInfo {
        var libs = std.ArrayList(mapper.LibraryInfo){};
        defer libs.deinit(self.allocator);

        for (self.imports.items) |import| {
            for (import.mapping.libraries) |lib| {
                libs.append(self.allocator, lib) catch continue;
            }
        }

        return libs.toOwnedSlice(self.allocator) catch &[_]mapper.LibraryInfo{};
    }

    /// Get all required headers for @cImport
    pub fn getRequiredHeaders(self: *const ImportContext, allocator: std.mem.Allocator) ![]const []const u8 {
        var headers = std.ArrayList([]const u8){};

        for (self.imports.items) |import| {
            for (import.mapping.libraries) |lib| {
                for (lib.headers) |header| {
                    try headers.append(allocator, header);
                }
            }
        }

        return headers.toOwnedSlice(allocator);
    }

    /// Generate @cImport block for all detected libraries
    pub fn generateCImportBlock(self: *const ImportContext, allocator: std.mem.Allocator) ![]const u8 {
        if (self.imports.items.len == 0) {
            return "";
        }

        var buf = std.ArrayList(u8){};
        const writer = buf.writer(allocator);

        try writer.writeAll("const c = @cImport({\n");

        const headers = try self.getRequiredHeaders(allocator);
        defer allocator.free(headers);

        for (headers) |header| {
            try writer.print("    @cInclude(\"{s}\");\n", .{header});
        }

        try writer.writeAll("});\n\n");

        return buf.toOwnedSlice(allocator);
    }
};

test "ImportContext basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Initialize registry (empty by default)
    try registry.initGlobalRegistry(allocator);
    defer registry.deinitGlobalRegistry(allocator);

    var ctx = ImportContext.init(allocator);
    defer ctx.deinit();

    // Register sqlite3 import
    try ctx.registerImport("sqlite3", "db");

    // Test function mapping (no mappings registered in empty registry)
    const should_map = ctx.shouldMapFunction("db.connect");
    try testing.expect(should_map == null); // Empty registry
}
