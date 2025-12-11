//! CPython source: Lib/modulefinder.py
//!
//! Provides functionality for finding module dependencies.
//!
//! Mirrors: CPython Lib/modulefinder.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Module - Represents a found module
// ============================================================================

/// Represents a Python module
pub const Module = struct {
    const Self = @This();

    /// Module name
    name: []const u8,
    /// File path (null for built-in modules)
    file: ?[]const u8,
    /// Path for packages
    path: ?[]const []const u8,
    /// Source code (if loaded)
    code: ?[]const u8,
    /// Global names defined
    globalnames: hashmap_helper.StringHashMap(void),
    /// Names that need to be in __starimport__ namespace
    starimports: hashmap_helper.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .name = name,
            .file = null,
            .path = null,
            .code = null,
            .globalnames = hashmap_helper.StringHashMap(void).init(allocator),
            .starimports = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.globalnames.deinit();
        self.starimports.deinit();
    }

    /// Check if this is a package
    pub fn isPackage(self: *const Self) bool {
        return self.path != null;
    }

    /// Get the source code
    pub fn getSource(self: *const Self) ?[]const u8 {
        return self.code;
    }
};

// ============================================================================
// ModuleFinder - Main class for finding modules
// ============================================================================

/// Find modules used by a script
pub const ModuleFinder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Found modules
    modules: hashmap_helper.StringHashMap(*Module),
    /// Bad modules (import errors)
    badmodules: hashmap_helper.StringHashMap(hashmap_helper.StringHashMap(void)),
    /// Search path
    path: std.ArrayList([]const u8),
    /// Debug level
    debug: i32,
    /// Exclude modules
    excludes: hashmap_helper.StringHashMap(void),
    /// Replace paths
    replace_paths: std.ArrayList(struct { old: []const u8, new: []const u8 }),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .modules = hashmap_helper.StringHashMap(*Module).init(allocator),
            .badmodules = hashmap_helper.StringHashMap(hashmap_helper.StringHashMap(void)).init(allocator),
            .path = std.ArrayList([]const u8).init(allocator),
            .debug = 0,
            .excludes = hashmap_helper.StringHashMap(void).init(allocator),
            .replace_paths = std.ArrayList(struct { old: []const u8, new: []const u8 }).init(allocator),
        };
    }

    pub fn initWithPath(allocator: std.mem.Allocator, path: []const []const u8, debug: i32, excludes: ?[]const []const u8, replace_paths: ?[]const struct { old: []const u8, new: []const u8 }) Self {
        var finder = Self.init(allocator);
        finder.debug = debug;

        for (path) |p| {
            finder.path.append(p) catch {};
        }

        if (excludes) |excl| {
            for (excl) |e| {
                finder.excludes.put(e, {}) catch {};
            }
        }

        if (replace_paths) |rp| {
            for (rp) |r| {
                finder.replace_paths.append(r) catch {};
            }
        }

        return finder;
    }

    pub fn deinit(self: *Self) void {
        for (self.modules.values()) |mod| {
            mod.deinit();
            self.allocator.destroy(mod);
        }
        self.modules.deinit();

        for (self.badmodules.values()) |*bad| {
            bad.deinit();
        }
        self.badmodules.deinit();

        self.path.deinit();
        self.excludes.deinit();
        self.replace_paths.deinit();
    }

    /// Output a message if debugging
    fn msg(self: *Self, level: i32, str: []const u8, args: anytype) void {
        if (self.debug >= level) {
            std.debug.print(str, args);
        }
    }

    /// Run on a script
    pub fn run_script(self: *Self, pathname: []const u8) !void {
        self.msg(2, "run_script({s})\n", .{pathname});

        // Read the file
        const file = try std.fs.cwd().openFile(pathname, .{});
        defer file.close();

        const code = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(code);

        // Create __main__ module
        const main_mod = try self.allocator.create(Module);
        main_mod.* = Module.init(self.allocator, "__main__");
        main_mod.file = pathname;

        try self.modules.put("__main__", main_mod);

        // Scan for imports
        try self.scan_code(code, main_mod);
    }

    /// Load a module by name
    pub fn load_module(self: *Self, fqname: []const u8, fp: ?std.fs.File, pathname: ?[]const u8) !?*Module {
        self.msg(2, "load_module({s})\n", .{fqname});

        // Check if excluded
        if (self.excludes.contains(fqname)) {
            self.msg(2, "  excluded\n", .{});
            return null;
        }

        // Check if already loaded
        if (self.modules.get(fqname)) |existing| {
            return existing;
        }

        // Create new module
        const mod = try self.allocator.create(Module);
        mod.* = Module.init(self.allocator, fqname);
        mod.file = pathname;

        // Read and scan code if file provided
        if (fp) |file| {
            const code = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
            defer self.allocator.free(code);
            mod.code = code;
            try self.scan_code(code, mod);
        }

        try self.modules.put(fqname, mod);
        return mod;
    }

    /// Find a module
    pub fn find_module(self: *Self, name: []const u8, path: ?[]const []const u8) !?struct { file: ?std.fs.File, pathname: []const u8, stuff: struct { suffix: []const u8, mode: []const u8, type_: i32 } } {
        _ = self;
        const search_path = path orelse &[_][]const u8{"."};

        for (search_path) |p| {
            // Try as package
            const pkg_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}/__init__.py", .{ p, name });
            defer std.heap.page_allocator.free(pkg_path);

            if (std.fs.cwd().openFile(pkg_path, .{})) |file| {
                return .{
                    .file = file,
                    .pathname = pkg_path,
                    .stuff = .{ .suffix = ".py", .mode = "r", .type_ = 1 }, // PKG_DIRECTORY
                };
            } else |_| {}

            // Try as module
            const mod_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.py", .{ p, name });
            defer std.heap.page_allocator.free(mod_path);

            if (std.fs.cwd().openFile(mod_path, .{})) |file| {
                return .{
                    .file = file,
                    .pathname = mod_path,
                    .stuff = .{ .suffix = ".py", .mode = "r", .type_ = 0 }, // PY_SOURCE
                };
            } else |_| {}
        }

        return null;
    }

    /// Import a module
    pub fn import_module(self: *Self, partname: []const u8, fqname: []const u8, parent: ?*Module) !?*Module {
        self.msg(3, "import_module({s}, {s})\n", .{ partname, fqname });

        // Check if excluded
        if (self.excludes.contains(fqname)) {
            return null;
        }

        // Check if already imported
        if (self.modules.get(fqname)) |existing| {
            return existing;
        }

        // Get search path
        const search_path = if (parent) |p| p.path else null;

        // Find the module
        const found = try self.find_module(partname, search_path);
        if (found) |f| {
            defer if (f.file) |file| file.close();
            return try self.load_module(fqname, f.file, f.pathname);
        }

        // Record as bad module
        var callers = hashmap_helper.StringHashMap(void).init(self.allocator);
        if (parent) |p| {
            try callers.put(p.name, {});
        }
        try self.badmodules.put(fqname, callers);

        return null;
    }

    /// Scan code for imports
    fn scan_code(self: *Self, code: []const u8, mod: *Module) !void {
        // Simple import scanner - look for 'import' and 'from' keywords
        var lines = std.mem.splitSequence(u8, code, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            if (std.mem.startsWith(u8, trimmed, "import ")) {
                const import_part = trimmed[7..];
                var modules_iter = std.mem.splitSequence(u8, import_part, ",");
                while (modules_iter.next()) |m| {
                    const module_name = std.mem.trim(u8, m, " \t");
                    // Handle "as" alias
                    var name_parts = std.mem.splitSequence(u8, module_name, " as ");
                    if (name_parts.next()) |actual_name| {
                        const clean_name = std.mem.trim(u8, actual_name, " \t");
                        if (clean_name.len > 0 and clean_name[0] != '#') {
                            _ = try self.import_module(clean_name, clean_name, mod);
                        }
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "from ")) {
                // from X import Y
                if (std.mem.indexOf(u8, trimmed, " import ")) |import_idx| {
                    const module_name = std.mem.trim(u8, trimmed[5..import_idx], " \t");
                    if (module_name.len > 0 and module_name[0] != '.') {
                        _ = try self.import_module(module_name, module_name, mod);
                    }
                }
            }
        }
    }

    /// Report findings
    pub fn report(self: *Self) void {
        std.debug.print("\n  Name                      File\n", .{});
        std.debug.print("  ----                      ----\n", .{});

        var it = self.modules.iterator();
        while (it.next()) |entry| {
            const mod = entry.value_ptr.*;
            std.debug.print("  {s: <24} {s}\n", .{
                mod.name,
                mod.file orelse "(built-in)",
            });
        }

        if (self.badmodules.count() > 0) {
            std.debug.print("\n  Missing modules:\n", .{});
            var bad_it = self.badmodules.keyIterator();
            while (bad_it.next()) |name| {
                std.debug.print("    {s}\n", .{name.*});
            }
        }
    }

    /// Get any missing modules
    pub fn anyMissing(self: *Self) []const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        for (self.badmodules.keys()) |name| {
            result.append(name) catch {};
        }
        return result.toOwnedSlice() catch &[_][]const u8{};
    }
};

// ============================================================================
// AddPackagePath - Add package path
// ============================================================================

/// Package path registry (module-level)
var package_paths: ?hashmap_helper.StringHashMap(std.ArrayList([]const u8)) = null;

/// Initialize package paths registry
fn initPackagePaths(allocator: std.mem.Allocator) void {
    if (package_paths == null) {
        package_paths = hashmap_helper.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    }
}

/// Add a path to a package's search path (__path__ attribute)
pub fn AddPackagePath(allocator: std.mem.Allocator, packagename: []const u8, path: []const u8) void {
    initPackagePaths(allocator);

    if (package_paths) |*paths| {
        if (paths.getPtr(packagename)) |existing| {
            // Add to existing package path list
            existing.append(path) catch {};
        } else {
            // Create new path list for this package
            var path_list = std.ArrayList([]const u8).init(allocator);
            path_list.append(path) catch {};
            paths.put(packagename, path_list) catch {};
        }
    }
}

/// Get paths for a package
pub fn GetPackagePaths(packagename: []const u8) ?[]const []const u8 {
    if (package_paths) |paths| {
        if (paths.get(packagename)) |path_list| {
            return path_list.items;
        }
    }
    return null;
}

// ============================================================================
// ReplacePackage - Replace a package
// ============================================================================

/// Package replacement registry (module-level)
var package_replacements: ?hashmap_helper.StringHashMap([]const u8) = null;

/// Initialize package replacements registry
fn initPackageReplacements(allocator: std.mem.Allocator) void {
    if (package_replacements == null) {
        package_replacements = hashmap_helper.StringHashMap([]const u8).init(allocator);
    }
}

/// Replace a package with another (redirect imports)
pub fn ReplacePackage(allocator: std.mem.Allocator, oldname: []const u8, newname: []const u8) void {
    initPackageReplacements(allocator);

    if (package_replacements) |*replacements| {
        replacements.put(oldname, newname) catch {};
    }
}

/// Get replacement name for a package (if any)
pub fn GetPackageReplacement(packagename: []const u8) ?[]const u8 {
    if (package_replacements) |replacements| {
        return replacements.get(packagename);
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "Module init" {
    const allocator = std.testing.allocator;
    var mod = Module.init(allocator, "test_module");
    defer mod.deinit();

    try std.testing.expectEqualStrings("test_module", mod.name);
    try std.testing.expect(mod.file == null);
    try std.testing.expect(!mod.isPackage());
}

test "ModuleFinder init" {
    const allocator = std.testing.allocator;
    var finder = ModuleFinder.init(allocator);
    defer finder.deinit();

    try std.testing.expectEqual(@as(usize, 0), finder.modules.count());
    try std.testing.expectEqual(@as(i32, 0), finder.debug);
}

test "ModuleFinder initWithPath" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "/usr/lib/python", "/usr/local/lib/python" };
    var finder = ModuleFinder.initWithPath(allocator, &paths, 1, null, null);
    defer finder.deinit();

    try std.testing.expectEqual(@as(usize, 2), finder.path.items.len);
    try std.testing.expectEqual(@as(i32, 1), finder.debug);
}

test "ModuleFinder with excludes" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{"."};
    const excludes = [_][]const u8{ "os", "sys" };
    var finder = ModuleFinder.initWithPath(allocator, &paths, 0, &excludes, null);
    defer finder.deinit();

    try std.testing.expect(finder.excludes.contains("os"));
    try std.testing.expect(finder.excludes.contains("sys"));
}

test "Module isPackage" {
    const allocator = std.testing.allocator;
    var mod = Module.init(allocator, "pkg");
    defer mod.deinit();

    try std.testing.expect(!mod.isPackage());

    const paths = [_][]const u8{"/some/path"};
    mod.path = &paths;
    try std.testing.expect(mod.isPackage());
}

test "ModuleFinder anyMissing empty" {
    const allocator = std.testing.allocator;
    var finder = ModuleFinder.init(allocator);
    defer finder.deinit();

    const missing = finder.anyMissing();
    try std.testing.expectEqual(@as(usize, 0), missing.len);
}
