//! Python 'importlib' module - Implementation of import
//!
//! Provides the implementation of the import statement.
//!
//! Mirrors: CPython Lib/importlib/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const ImportError = error{
    ModuleNotFound,
    InvalidName,
    CircularImport,
    LoaderError,
    OutOfMemory,
};

// ============================================================================
// ModuleSpec
// ============================================================================

/// Specification for a module's import-system-related state
pub const ModuleSpec = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Fully qualified module name
    name: []const u8,
    /// Module loader
    loader: ?*anyopaque = null,
    /// Module origin (typically file path)
    origin: ?[]const u8 = null,
    /// Package submodule search locations
    submodule_search_locations: ?std.ArrayList([]const u8) = null,
    /// Cached state for loader
    loader_state: ?*anyopaque = null,
    /// Whether module has location
    has_location: bool = false,
    /// Cached attribute (weak reference)
    cached: ?[]const u8 = null,
    /// Parent package name
    parent: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, loader: ?*anyopaque) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .loader = loader,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.submodule_search_locations) |*locs| {
            locs.deinit();
        }
    }

    /// Check if this is a package spec
    pub fn isPackage(self: *const Self) bool {
        return self.submodule_search_locations != null;
    }
};

// ============================================================================
// Loader Protocol
// ============================================================================

/// Abstract base class for a loader
pub const Loader = struct {
    /// Create a module based on a spec
    pub fn create_module(spec: *const ModuleSpec) ?*anyopaque {
        _ = spec;
        return null;
    }

    /// Execute the module
    pub fn exec_module(module: *anyopaque) !void {
        _ = module;
    }

    /// Return True if the loader can handle the named module
    pub fn module_repr(module: *anyopaque) []const u8 {
        _ = module;
        return "<module>";
    }
};

/// Loader for extension modules
pub const ExtensionFileLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) ExtensionFileLoader {
        return .{
            .name = name,
            .path = path,
        };
    }

    pub fn get_filename(self: *const ExtensionFileLoader) []const u8 {
        return self.path;
    }
};

/// Loader for source (.py) files
pub const SourceFileLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) SourceFileLoader {
        return .{
            .name = name,
            .path = path,
        };
    }

    pub fn get_filename(self: *const SourceFileLoader) []const u8 {
        return self.path;
    }

    pub fn get_data(self: *const SourceFileLoader, allocator: std.mem.Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }
};

/// Loader for bytecode (.pyc) files
pub const SourcelessFileLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) SourcelessFileLoader {
        return .{
            .name = name,
            .path = path,
        };
    }
};

// ============================================================================
// Finder Protocol
// ============================================================================

/// Abstract base class for path entry finders
pub const Finder = struct {
    /// Find a module spec
    pub fn find_spec(name: []const u8, path: ?[]const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = name;
        _ = path;
        _ = target;
        return null;
    }
};

/// Meta path finder that uses sys.path
pub const PathFinder = struct {
    /// Find a module spec by searching paths
    pub fn find_spec(allocator: std.mem.Allocator, name: []const u8, path: ?[]const []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = target;

        // Default search paths if none provided
        const search_paths = path orelse &[_][]const u8{
            ".", // Current directory
            "./lib",
            "/usr/lib/python3/dist-packages",
            "/usr/local/lib/python3/site-packages",
        };

        // Try to find module file
        for (search_paths) |base_path| {
            // Try as package (directory with __init__.py)
            var package_path_buf: [512]u8 = undefined;
            const package_path = std.fmt.bufPrint(&package_path_buf, "{s}/{s}/__init__.py", .{ base_path, name }) catch continue;
            if (std.fs.cwd().access(package_path, .{})) {
                return ModuleSpec.init(allocator, name, package_path) catch null;
            } else |_| {}

            // Try as module file (.py)
            var module_path_buf: [512]u8 = undefined;
            const module_path = std.fmt.bufPrint(&module_path_buf, "{s}/{s}.py", .{ base_path, name }) catch continue;
            if (std.fs.cwd().access(module_path, .{})) {
                return ModuleSpec.init(allocator, name, module_path) catch null;
            } else |_| {}

            // Try as compiled module (.pyc, .so, .zig)
            const extensions = [_][]const u8{ ".pyc", ".so", ".zig" };
            for (extensions) |ext| {
                var compiled_path_buf: [512]u8 = undefined;
                const compiled_path = std.fmt.bufPrint(&compiled_path_buf, "{s}/{s}{s}", .{ base_path, name, ext }) catch continue;
                if (std.fs.cwd().access(compiled_path, .{})) {
                    return ModuleSpec.init(allocator, name, compiled_path) catch null;
                } else |_| {}
            }
        }

        return null;
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Import a module by name
pub fn import_module(allocator: std.mem.Allocator, name: []const u8) !*anyopaque {
    _ = allocator;
    _ = name;
    return error.ModuleNotFound;
}

/// Find the spec for a module
pub fn find_spec(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) !?ModuleSpec {
    _ = package;
    return ModuleSpec.init(allocator, name, null);
}

/// Reload a previously imported module
/// In AOT compilation, modules are statically compiled, so reload returns the same module.
/// For dynamic reloading, the application would need to be recompiled.
pub fn reload(module: *anyopaque) !*anyopaque {
    // In AOT, modules are compiled into the binary at build time.
    // True dynamic reloading would require:
    // 1. Unloading the old module code
    // 2. Re-parsing and compiling the source
    // 3. Re-linking into the running process
    // For now, we return the existing module - changes require recompilation.
    return module;
}

/// Module cache for import tracking
var module_cache: ?std.StringHashMap(*anyopaque) = null;

/// Invalidate cached finders and module cache
pub fn invalidate_caches() void {
    // Clear any cached module lookups
    if (module_cache) |*cache| {
        cache.clearRetainingCapacity();
    }
    // In a full implementation, this would also clear:
    // - sys.path_importer_cache
    // - Each finder's cache via finder.invalidate_caches()
}

// ============================================================================
// importlib.util functions
// ============================================================================

pub const util = struct {
    /// Resolve a relative module name
    pub fn resolve_name(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) ![]u8 {
        if (name.len == 0) return error.InvalidName;

        if (name[0] != '.') {
            // Absolute import
            return allocator.dupe(u8, name);
        }

        // Relative import
        const pkg = package orelse return error.InvalidName;

        // Count leading dots
        var level: usize = 0;
        while (level < name.len and name[level] == '.') {
            level += 1;
        }

        // Navigate up package hierarchy
        var pkg_parts = std.mem.splitScalar(u8, pkg, '.');
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        while (pkg_parts.next()) |part| {
            try parts.append(part);
        }

        if (level > parts.items.len) {
            return error.InvalidName;
        }

        // Remove trailing parts based on level
        for (0..level - 1) |_| {
            _ = parts.pop();
        }

        // Append remaining name
        if (level < name.len) {
            try parts.append(name[level..]);
        }

        // Join with dots
        var result = std.ArrayList(u8).init(allocator);
        for (parts.items, 0..) |part, i| {
            if (i > 0) try result.append('.');
            try result.appendSlice(part);
        }

        return result.toOwnedSlice();
    }

    /// Find a spec for a module given its name and optionally a package
    pub fn find_spec(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) !?ModuleSpec {
        const full_name = try resolve_name(allocator, name, package);
        defer allocator.free(full_name);
        return ModuleSpec.init(allocator, full_name, null);
    }

    /// Create a new module based on spec
    pub fn module_from_spec(spec: *const ModuleSpec) !*anyopaque {
        _ = spec;
        return error.LoaderError;
    }

    /// Check if a module can be found
    pub fn find_loader(allocator: std.mem.Allocator, name: []const u8) !?*anyopaque {
        _ = allocator;
        _ = name;
        return null;
    }

    /// Source hash for comparison
    pub fn source_hash(source_bytes: []const u8) u64 {
        return std.hash.Wyhash.hash(0, source_bytes);
    }

    /// Check if name is a valid module name
    pub fn is_valid_module_name(name: []const u8) bool {
        if (name.len == 0) return false;

        // First character must be letter or underscore
        const first = name[0];
        if (!std.ascii.isAlphabetic(first) and first != '_') {
            return false;
        }

        // Rest must be alphanumeric, underscore, or dot
        for (name[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '.') {
                return false;
            }
        }

        return true;
    }
};

// ============================================================================
// importlib.abc abstract base classes
// ============================================================================

pub const abc = struct {
    /// Abstract base class for finders
    pub const MetaPathFinder = struct {
        pub fn find_module(name: []const u8, path: ?[]const u8) ?*anyopaque {
            _ = name;
            _ = path;
            return null;
        }
    };

    /// Abstract base class for path entry finders
    pub const PathEntryFinder = struct {
        pub fn find_spec(name: []const u8, target: ?*anyopaque) ?ModuleSpec {
            _ = name;
            _ = target;
            return null;
        }
    };

    /// Abstract base class for loaders
    pub const ABCLoader = struct {
        pub fn load_module(name: []const u8) !*anyopaque {
            _ = name;
            return error.LoaderError;
        }
    };
};

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

test "ModuleSpec init" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "test_module", null);
    defer spec.deinit();

    try std.testing.expectEqualStrings("test_module", spec.name);
    try std.testing.expect(!spec.isPackage());
}

test "ModuleSpec isPackage" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "test_pkg", null);
    spec.submodule_search_locations = std.ArrayList([]const u8).init(allocator);
    defer spec.deinit();

    try std.testing.expect(spec.isPackage());
}

test "SourceFileLoader init" {
    const loader = SourceFileLoader.init("mymodule", "/path/to/mymodule.py");
    try std.testing.expectEqualStrings("mymodule", loader.name);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", loader.get_filename());
}

test "util.resolve_name absolute" {
    const allocator = std.testing.allocator;
    const result = try util.resolve_name(allocator, "os.path", null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("os.path", result);
}

test "util.is_valid_module_name" {
    try std.testing.expect(util.is_valid_module_name("mymodule"));
    try std.testing.expect(util.is_valid_module_name("my_module"));
    try std.testing.expect(util.is_valid_module_name("my.module"));
    try std.testing.expect(util.is_valid_module_name("_private"));
    try std.testing.expect(!util.is_valid_module_name(""));
    try std.testing.expect(!util.is_valid_module_name("123module"));
}

test "util.source_hash" {
    const hash1 = util.source_hash("print('hello')");
    const hash2 = util.source_hash("print('hello')");
    const hash3 = util.source_hash("print('world')");

    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}
