//! pyproject.toml Parser
//!
//! Parses PEP 621 pyproject.toml files for project metadata and dependencies.
//!
//! Supports:
//! - [project] section (PEP 621)
//! - [project.dependencies] - required dependencies
//! - [project.optional-dependencies] - optional/extra dependencies
//! - [build-system] - build requirements
//! - [tool.metal0] - metal0-specific configuration
//!
//! Reference: https://peps.python.org/pep-0621/

const std = @import("std");
const toml = @import("toml.zig");
const pep508 = @import("pep508.zig");

/// Parsed pyproject.toml
pub const PyProject = struct {
    /// Project name
    name: ?[]const u8 = null,
    /// Project version
    version: ?[]const u8 = null,
    /// Project description
    description: ?[]const u8 = null,
    /// Required Python version
    requires_python: ?[]const u8 = null,
    /// Required dependencies
    dependencies: []const pep508.Dependency = &.{},
    /// Optional dependencies by extra name
    optional_dependencies: std.StringHashMap([]const pep508.Dependency),
    /// Build system requirements
    build_requires: []const pep508.Dependency = &.{},
    /// Build backend
    build_backend: ?[]const u8 = null,
    /// metal0-specific config
    metal0_config: Metal0Config = .{},

    allocator: std.mem.Allocator,
    /// Backing storage for string slices
    _toml: ?toml.Table = null,

    pub const Metal0Config = struct {
        /// Target platform for compilation
        target: ?[]const u8 = null,
        /// Optimization level
        optimize: ?[]const u8 = null,
        /// Additional compiler flags
        flags: []const []const u8 = &.{},
    };

    pub fn deinit(self: *PyProject) void {
        // Free dependencies
        for (self.dependencies) |*dep| {
            pep508.freeDependency(self.allocator, @constCast(dep));
        }
        self.allocator.free(self.dependencies);

        // Free optional dependencies
        var it = self.optional_dependencies.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*) |*dep| {
                pep508.freeDependency(self.allocator, @constCast(dep));
            }
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.optional_dependencies.deinit();

        // Free build requires
        for (self.build_requires) |*dep| {
            pep508.freeDependency(self.allocator, @constCast(dep));
        }
        self.allocator.free(self.build_requires);

        // Free TOML backing
        if (self._toml) |*t| {
            t.deinit(self.allocator);
        }
    }

    /// Get all dependencies including specified extras
    pub fn getAllDependencies(self: PyProject, extras: []const []const u8) ![]const pep508.Dependency {
        var all = std.ArrayList(pep508.Dependency){};
        errdefer all.deinit(self.allocator);

        // Add required dependencies
        for (self.dependencies) |dep| {
            try all.append(self.allocator, dep);
        }

        // Add optional dependencies for requested extras
        for (extras) |extra| {
            if (self.optional_dependencies.get(extra)) |deps| {
                for (deps) |dep| {
                    try all.append(self.allocator, dep);
                }
            }
        }

        return all.toOwnedSlice(self.allocator);
    }
};

/// Parse pyproject.toml from string
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !PyProject {
    var table = try toml.parse(allocator, source);
    errdefer table.deinit(allocator);

    var result = PyProject{
        .allocator = allocator,
        .optional_dependencies = std.StringHashMap([]const pep508.Dependency).init(allocator),
        ._toml = table,
    };
    errdefer result.deinit();

    // Parse [project] section
    if (table.getTable("project")) |project| {
        result.name = project.getString("name");
        result.version = project.getString("version");
        result.description = project.getString("description");
        result.requires_python = project.getString("requires-python");

        // Parse dependencies array
        if (project.getArray("dependencies")) |deps_arr| {
            var deps = std.ArrayList(pep508.Dependency){};
            errdefer deps.deinit(allocator);

            for (deps_arr) |dep_val| {
                if (dep_val.getString()) |dep_str| {
                    const dep = pep508.parseDependency(allocator, dep_str) catch continue;
                    try deps.append(allocator, dep);
                }
            }
            result.dependencies = try deps.toOwnedSlice(allocator);
        }

        // Parse optional-dependencies
        if (project.getTable("optional-dependencies")) |opt_deps| {
            var opt_it = opt_deps.entries.iterator();
            while (opt_it.next()) |entry| {
                const extra_name = entry.key_ptr.*;
                if (entry.value_ptr.*.getArray()) |extra_deps_arr| {
                    var extra_deps = std.ArrayList(pep508.Dependency){};
                    errdefer extra_deps.deinit(allocator);

                    for (extra_deps_arr) |dep_val| {
                        if (dep_val.getString()) |dep_str| {
                            const dep = pep508.parseDependency(allocator, dep_str) catch continue;
                            try extra_deps.append(allocator, dep);
                        }
                    }

                    const name_copy = try allocator.dupe(u8, extra_name);
                    try result.optional_dependencies.put(name_copy, try extra_deps.toOwnedSlice(allocator));
                }
            }
        }
    }

    // Parse [build-system] section
    if (table.getTable("build-system")) |build_system| {
        result.build_backend = build_system.getString("build-backend");

        if (build_system.getArray("requires")) |requires_arr| {
            var requires = std.ArrayList(pep508.Dependency){};
            errdefer requires.deinit(allocator);

            for (requires_arr) |req_val| {
                if (req_val.getString()) |req_str| {
                    const dep = pep508.parseDependency(allocator, req_str) catch continue;
                    try requires.append(allocator, dep);
                }
            }
            result.build_requires = try requires.toOwnedSlice(allocator);
        }
    }

    // Parse [tool.metal0] section
    if (table.getTable("tool")) |tool| {
        if (tool.getTable("metal0")) |metal0| {
            result.metal0_config.target = metal0.getString("target");
            result.metal0_config.optimize = metal0.getString("optimize");

            if (metal0.getArray("flags")) |flags_arr| {
                var flags = std.ArrayList([]const u8){};
                errdefer flags.deinit(allocator);

                for (flags_arr) |flag_val| {
                    if (flag_val.getString()) |flag_str| {
                        try flags.append(allocator, flag_str);
                    }
                }
                result.metal0_config.flags = try flags.toOwnedSlice(allocator);
            }
        }
    }

    return result;
}

/// Parse pyproject.toml from file
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !PyProject {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);
    return parse(allocator, content);
}

/// Find pyproject.toml by walking up from a directory
pub fn findPyproject(allocator: std.mem.Allocator, start_path: []const u8) !?[]const u8 {
    var current = try allocator.dupe(u8, start_path);
    defer allocator.free(current);

    while (true) {
        const pyproject_path = try std.fs.path.join(allocator, &.{ current, "pyproject.toml" });

        // Check if pyproject.toml exists
        if (std.fs.cwd().access(pyproject_path, .{})) |_| {
            return pyproject_path;
        } else |_| {
            allocator.free(pyproject_path);
        }

        // Go up one directory
        const parent = std.fs.path.dirname(current);
        if (parent == null or std.mem.eql(u8, parent.?, current)) {
            return null;
        }

        const new_current = try allocator.dupe(u8, parent.?);
        allocator.free(current);
        current = new_current;
    }
}

test "parse minimal pyproject.toml" {
    const allocator = std.testing.allocator;
    const source =
        \\[project]
        \\name = "myproject"
        \\version = "1.0.0"
        \\dependencies = ["numpy>=1.0", "pandas"]
    ;

    var pyproject = try parse(allocator, source);
    defer pyproject.deinit();

    try std.testing.expectEqualStrings("myproject", pyproject.name.?);
    try std.testing.expectEqualStrings("1.0.0", pyproject.version.?);
    try std.testing.expectEqual(@as(usize, 2), pyproject.dependencies.len);
    try std.testing.expectEqualStrings("numpy", pyproject.dependencies[0].name);
    try std.testing.expectEqualStrings("pandas", pyproject.dependencies[1].name);
}

test "parse pyproject.toml with build-system" {
    const allocator = std.testing.allocator;
    const source =
        \\[build-system]
        \\requires = ["setuptools>=42", "wheel"]
        \\build-backend = "setuptools.build_meta"
        \\
        \\[project]
        \\name = "test"
        \\version = "0.1.0"
    ;

    var pyproject = try parse(allocator, source);
    defer pyproject.deinit();

    try std.testing.expectEqualStrings("setuptools.build_meta", pyproject.build_backend.?);
    try std.testing.expectEqual(@as(usize, 2), pyproject.build_requires.len);
}

test "parse pyproject.toml with optional dependencies" {
    const allocator = std.testing.allocator;
    const source =
        \\[project]
        \\name = "test"
        \\version = "0.1.0"
        \\dependencies = ["requests"]
        \\
        \\[project.optional-dependencies]
        \\dev = ["pytest", "black"]
        \\docs = ["sphinx"]
    ;

    var pyproject = try parse(allocator, source);
    defer pyproject.deinit();

    try std.testing.expectEqual(@as(usize, 1), pyproject.dependencies.len);

    const dev_deps = pyproject.optional_dependencies.get("dev").?;
    try std.testing.expectEqual(@as(usize, 2), dev_deps.len);

    const docs_deps = pyproject.optional_dependencies.get("docs").?;
    try std.testing.expectEqual(@as(usize, 1), docs_deps.len);
}
