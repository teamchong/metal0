//! test.test_import.test_finder - Finder testing
//!
//! Tests for Python's import finders including:
//! - MetaPathFinder interface
//! - PathEntryFinder interface
//! - BuiltinImporter
//! - FrozenImporter
//! - PathFinder
//! - FileFinder
//! - find_spec() and find_module() protocols

const std = @import("std");
const Allocator = std.mem.Allocator;

/// FinderError - Errors that can occur during module finding
pub const FinderError = error{
    ModuleNotFound,
    InvalidPath,
    InvalidFinder,
    OutOfMemory,
};

/// ModuleSpec - Specification for loading a module
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*const Loader,
    origin: ?[]const u8,
    cached: ?[]const u8,
    parent: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    has_location: bool,
    loader_state: ?*anyopaque,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .cached = null,
            .parent = null,
            .submodule_search_locations = null,
            .has_location = false,
            .loader_state = null,
        };
    }

    pub fn withLoader(self: ModuleSpec, loader: *const Loader) ModuleSpec {
        var spec = self;
        spec.loader = loader;
        return spec;
    }

    pub fn withOrigin(self: ModuleSpec, origin: []const u8) ModuleSpec {
        var spec = self;
        spec.origin = origin;
        spec.has_location = true;
        return spec;
    }

    pub fn isPackage(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }
};

/// Loader interface stub
pub const Loader = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        create_module: *const fn (*anyopaque, *const ModuleSpec) ?*Module,
        exec_module: *const fn (*anyopaque, *Module) anyerror!void,
    };
};

/// Module representation stub
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __path__: ?[]const []const u8,
};

/// MetaPathFinder - Abstract base for meta path finders
/// These are checked in order for every import
pub const MetaPathFinder = struct {
    vtable: *const VTable,
    context: *anyopaque,
    name: []const u8,

    pub const VTable = struct {
        /// Find a module spec for the given module name
        find_spec: *const fn (
            *anyopaque,
            []const u8,
            ?[]const u8,
            ?*Module,
        ) ?*ModuleSpec,

        /// Legacy find_module (deprecated)
        find_module: *const fn (
            *anyopaque,
            []const u8,
            ?[]const u8,
        ) ?*const Loader,

        /// Invalidate any cached data
        invalidate_caches: *const fn (*anyopaque) void,
    };

    pub fn findSpec(
        self: *const MetaPathFinder,
        fullname: []const u8,
        path: ?[]const u8,
        target: ?*Module,
    ) ?*ModuleSpec {
        return self.vtable.find_spec(self.context, fullname, path, target);
    }

    pub fn findModule(
        self: *const MetaPathFinder,
        fullname: []const u8,
        path: ?[]const u8,
    ) ?*const Loader {
        return self.vtable.find_module(self.context, fullname, path);
    }

    pub fn invalidateCaches(self: *const MetaPathFinder) void {
        self.vtable.invalidate_caches(self.context);
    }
};

/// PathEntryFinder - Finder for a specific path entry
pub const PathEntryFinder = struct {
    vtable: *const VTable,
    context: *anyopaque,
    path: []const u8,

    pub const VTable = struct {
        /// Find a spec within this path entry
        find_spec: *const fn (*anyopaque, []const u8, ?*Module) ?*ModuleSpec,

        /// Legacy find_loader
        find_loader: *const fn (*anyopaque, []const u8) FindLoaderResult,

        /// Invalidate cached data for this path
        invalidate_caches: *const fn (*anyopaque) void,
    };

    pub const FindLoaderResult = struct {
        loader: ?*const Loader,
        portions: []const []const u8,
    };

    pub fn findSpec(
        self: *const PathEntryFinder,
        fullname: []const u8,
        target: ?*Module,
    ) ?*ModuleSpec {
        return self.vtable.find_spec(self.context, fullname, target);
    }

    pub fn findLoader(self: *const PathEntryFinder, fullname: []const u8) FindLoaderResult {
        return self.vtable.find_loader(self.context, fullname);
    }

    pub fn invalidateCaches(self: *const PathEntryFinder) void {
        self.vtable.invalidate_caches(self.context);
    }
};

/// BuiltinImporter - Finder/Loader for built-in modules
pub const BuiltinImporter = struct {
    builtin_names: std.StringHashMapUnmanaged(void),
    allocator: Allocator,

    pub fn init(allocator: Allocator) BuiltinImporter {
        return .{
            .builtin_names = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BuiltinImporter) void {
        self.builtin_names.deinit(self.allocator);
    }

    pub fn registerBuiltin(self: *BuiltinImporter, name: []const u8) !void {
        try self.builtin_names.put(self.allocator, name, {});
    }

    pub fn isBuiltin(self: *const BuiltinImporter, name: []const u8) bool {
        return self.builtin_names.contains(name);
    }

    pub fn findSpec(self: *const BuiltinImporter, fullname: []const u8) ?ModuleSpec {
        if (!self.isBuiltin(fullname)) return null;

        var spec = ModuleSpec.init(fullname);
        spec.origin = "built-in";
        return spec;
    }

    pub fn getBuiltinNames(self: *const BuiltinImporter, allocator: Allocator) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = self.builtin_names.keyIterator();
        while (iter.next()) |key| {
            try result.append(key.*);
        }
        return result.toOwnedSlice();
    }
};

/// FrozenImporter - Finder/Loader for frozen modules
pub const FrozenImporter = struct {
    frozen_modules: std.StringHashMapUnmanaged(FrozenModule),
    allocator: Allocator,

    pub const FrozenModule = struct {
        name: []const u8,
        code: []const u8,
        is_package: bool,
        size: usize,
    };

    pub fn init(allocator: Allocator) FrozenImporter {
        return .{
            .frozen_modules = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FrozenImporter) void {
        self.frozen_modules.deinit(self.allocator);
    }

    pub fn registerFrozen(self: *FrozenImporter, module: FrozenModule) !void {
        try self.frozen_modules.put(self.allocator, module.name, module);
    }

    pub fn isFrozen(self: *const FrozenImporter, name: []const u8) bool {
        return self.frozen_modules.contains(name);
    }

    pub fn findSpec(self: *const FrozenImporter, fullname: []const u8) ?ModuleSpec {
        const frozen = self.frozen_modules.get(fullname) orelse return null;

        var spec = ModuleSpec.init(fullname);
        spec.origin = "frozen";
        if (frozen.is_package) {
            spec.submodule_search_locations = &.{};
        }
        return spec;
    }

    pub fn getFrozenData(self: *const FrozenImporter, name: []const u8) ?[]const u8 {
        const frozen = self.frozen_modules.get(name) orelse return null;
        return frozen.code;
    }
};

/// PathFinder - The main path-based finder (sys.meta_path[2])
pub const PathFinder = struct {
    path: std.ArrayListUnmanaged([]const u8),
    path_hooks: std.ArrayListUnmanaged(PathHook),
    path_importer_cache: std.StringHashMapUnmanaged(?*PathEntryFinder),
    allocator: Allocator,

    pub const PathHook = *const fn ([]const u8) ?*PathEntryFinder;

    pub fn init(allocator: Allocator) PathFinder {
        return .{
            .path = .{},
            .path_hooks = .{},
            .path_importer_cache = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PathFinder) void {
        self.path.deinit(self.allocator);
        self.path_hooks.deinit(self.allocator);
        self.path_importer_cache.deinit(self.allocator);
    }

    pub fn addPath(self: *PathFinder, path_entry: []const u8) !void {
        try self.path.append(self.allocator, path_entry);
    }

    pub fn addPathHook(self: *PathFinder, hook: PathHook) !void {
        try self.path_hooks.append(self.allocator, hook);
    }

    /// Get or create a finder for a path entry
    pub fn getPathEntryFinder(self: *PathFinder, path_entry: []const u8) ?*PathEntryFinder {
        // Check cache first
        if (self.path_importer_cache.get(path_entry)) |cached| {
            return cached;
        }

        // Try path hooks
        for (self.path_hooks.items) |hook| {
            if (hook(path_entry)) |finder| {
                self.path_importer_cache.put(self.allocator, path_entry, finder) catch {};
                return finder;
            }
        }

        // Cache the negative result
        self.path_importer_cache.put(self.allocator, path_entry, null) catch {};
        return null;
    }

    /// Find a module spec
    pub fn findSpec(
        self: *PathFinder,
        fullname: []const u8,
        path: ?[]const []const u8,
        _: ?*Module,
    ) ?ModuleSpec {
        const search_path = path orelse self.path.items;

        for (search_path) |path_entry| {
            if (self.getPathEntryFinder(path_entry)) |finder| {
                if (finder.findSpec(fullname, null)) |spec| {
                    return spec.*;
                }
            }
        }

        return null;
    }

    pub fn invalidateCaches(self: *PathFinder) void {
        self.path_importer_cache.clearRetainingCapacity();
    }
};

/// FileFinder - Path entry finder for filesystem directories
pub const FileFinder = struct {
    path: []const u8,
    loaders: []const LoaderDetail,
    contents_cache: std.StringHashMapUnmanaged(void),
    mtime: i64,
    allocator: Allocator,

    pub const LoaderDetail = struct {
        loader_class: *const Loader,
        suffixes: []const []const u8,
    };

    pub fn init(allocator: Allocator, path: []const u8, loaders: []const LoaderDetail) FileFinder {
        return .{
            .path = path,
            .loaders = loaders,
            .contents_cache = .{},
            .mtime = -1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileFinder) void {
        self.contents_cache.deinit(self.allocator);
    }

    /// Get the tail name (last component of dotted name)
    fn getTailName(fullname: []const u8) []const u8 {
        if (std.mem.lastIndexOfScalar(u8, fullname, '.')) |idx| {
            return fullname[idx + 1 ..];
        }
        return fullname;
    }

    /// Check if a module exists at this path
    pub fn findSpec(self: *FileFinder, fullname: []const u8) ?ModuleSpec {
        const tail_name = getTailName(fullname);

        // Check for package first
        var buf: [512]u8 = undefined;
        const pkg_init = std.fmt.bufPrint(&buf, "{s}/{s}/__init__.py", .{ self.path, tail_name }) catch return null;
        _ = pkg_init;

        // Would check file existence here
        // For testing, return a basic spec
        var spec = ModuleSpec.init(fullname);
        spec.has_location = true;
        return spec;
    }

    /// Check if directory contents have changed
    pub fn contentsChanged(self: *const FileFinder) bool {
        // Would check mtime here
        _ = self;
        return false;
    }

    pub fn invalidateCaches(self: *FileFinder) void {
        self.contents_cache.clearRetainingCapacity();
        self.mtime = -1;
    }
};

/// ZipImporter - Finder for modules in zip files
pub const ZipImporter = struct {
    archive_path: []const u8,
    prefix: []const u8,
    files: std.StringHashMapUnmanaged(ZipEntry),
    allocator: Allocator,

    pub const ZipEntry = struct {
        offset: u64,
        compressed_size: u32,
        uncompressed_size: u32,
        is_dir: bool,
    };

    pub fn init(allocator: Allocator, archive_path: []const u8) ZipImporter {
        return .{
            .archive_path = archive_path,
            .prefix = "",
            .files = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ZipImporter) void {
        self.files.deinit(self.allocator);
    }

    pub fn findSpec(self: *const ZipImporter, fullname: []const u8) ?ModuleSpec {
        // Convert module name to zip path
        var buf: [256]u8 = undefined;
        var path_buf = std.ArrayList(u8).init(self.allocator);
        defer path_buf.deinit();

        // Replace dots with slashes
        var iter = std.mem.splitScalar(u8, fullname, '.');
        var first = true;
        while (iter.next()) |part| {
            if (!first) path_buf.append('/') catch return null;
            path_buf.appendSlice(part) catch return null;
            first = false;
        }

        // Check for package
        const pkg_path = std.fmt.bufPrint(&buf, "{s}/__init__.py", .{path_buf.items}) catch return null;
        if (self.files.contains(pkg_path)) {
            var spec = ModuleSpec.init(fullname);
            spec.origin = self.archive_path;
            spec.submodule_search_locations = &.{};
            return spec;
        }

        // Check for module
        path_buf.appendSlice(".py") catch return null;
        if (self.files.contains(path_buf.items)) {
            var spec = ModuleSpec.init(fullname);
            spec.origin = self.archive_path;
            return spec;
        }

        return null;
    }

    pub fn isPackage(self: *const ZipImporter, fullname: []const u8) bool {
        const spec = self.findSpec(fullname) orelse return false;
        return spec.isPackage();
    }
};

/// FinderRegistry - Registry of all finders
pub const FinderRegistry = struct {
    meta_path: std.ArrayListUnmanaged(*MetaPathFinder),
    path_hooks: std.ArrayListUnmanaged(PathFinder.PathHook),
    allocator: Allocator,

    pub fn init(allocator: Allocator) FinderRegistry {
        return .{
            .meta_path = .{},
            .path_hooks = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FinderRegistry) void {
        self.meta_path.deinit(self.allocator);
        self.path_hooks.deinit(self.allocator);
    }

    pub fn addMetaPathFinder(self: *FinderRegistry, finder: *MetaPathFinder) !void {
        try self.meta_path.append(self.allocator, finder);
    }

    pub fn insertMetaPathFinder(self: *FinderRegistry, index: usize, finder: *MetaPathFinder) !void {
        try self.meta_path.insert(self.allocator, index, finder);
    }

    pub fn addPathHook(self: *FinderRegistry, hook: PathFinder.PathHook) !void {
        try self.path_hooks.append(self.allocator, hook);
    }

    pub fn findSpec(self: *FinderRegistry, fullname: []const u8, path: ?[]const u8) ?*ModuleSpec {
        for (self.meta_path.items) |finder| {
            if (finder.findSpec(fullname, path, null)) |spec| {
                return spec;
            }
        }
        return null;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "module_spec_basic" {
    var spec = ModuleSpec.init("mymodule");

    try std.testing.expectEqualStrings("mymodule", spec.name);
    try std.testing.expect(!spec.isPackage());
    try std.testing.expect(!spec.has_location);

    spec = spec.withOrigin("/path/to/mymodule.py");
    try std.testing.expect(spec.has_location);
}

test "builtin_importer" {
    var importer = BuiltinImporter.init(std.testing.allocator);
    defer importer.deinit();

    try importer.registerBuiltin("sys");
    try importer.registerBuiltin("builtins");
    try importer.registerBuiltin("_thread");

    try std.testing.expect(importer.isBuiltin("sys"));
    try std.testing.expect(importer.isBuiltin("builtins"));
    try std.testing.expect(!importer.isBuiltin("os"));

    const spec = importer.findSpec("sys");
    try std.testing.expect(spec != null);
    try std.testing.expectEqualStrings("sys", spec.?.name);
    try std.testing.expectEqualStrings("built-in", spec.?.origin.?);
}

test "builtin_importer_list" {
    var importer = BuiltinImporter.init(std.testing.allocator);
    defer importer.deinit();

    try importer.registerBuiltin("sys");
    try importer.registerBuiltin("os");

    const names = try importer.getBuiltinNames(std.testing.allocator);
    defer std.testing.allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);
}

test "frozen_importer" {
    var importer = FrozenImporter.init(std.testing.allocator);
    defer importer.deinit();

    try importer.registerFrozen(.{
        .name = "_frozen_importlib",
        .code = "frozen bytecode",
        .is_package = false,
        .size = 15,
    });

    try std.testing.expect(importer.isFrozen("_frozen_importlib"));
    try std.testing.expect(!importer.isFrozen("os"));

    const spec = importer.findSpec("_frozen_importlib");
    try std.testing.expect(spec != null);
    try std.testing.expectEqualStrings("frozen", spec.?.origin.?);

    const data = importer.getFrozenData("_frozen_importlib");
    try std.testing.expect(data != null);
    try std.testing.expectEqualStrings("frozen bytecode", data.?);
}

test "path_finder_basic" {
    var finder = PathFinder.init(std.testing.allocator);
    defer finder.deinit();

    try finder.addPath("/usr/lib/python3");
    try finder.addPath("/home/user/.local/lib/python3");

    try std.testing.expectEqual(@as(usize, 2), finder.path.items.len);
}

test "path_finder_cache" {
    var finder = PathFinder.init(std.testing.allocator);
    defer finder.deinit();

    // Should return null for unknown path
    try std.testing.expect(finder.getPathEntryFinder("/nonexistent") == null);

    // Cache should be populated
    try std.testing.expect(finder.path_importer_cache.count() > 0);

    finder.invalidateCaches();
    try std.testing.expect(finder.path_importer_cache.count() == 0);
}

test "file_finder_tail_name" {
    const tail1 = FileFinder.getTailName("os.path.join");
    try std.testing.expectEqualStrings("join", tail1);

    const tail2 = FileFinder.getTailName("os");
    try std.testing.expectEqualStrings("os", tail2);
}

test "file_finder_basic" {
    var finder = FileFinder.init(std.testing.allocator, "/usr/lib/python3", &.{});
    defer finder.deinit();

    try std.testing.expectEqualStrings("/usr/lib/python3", finder.path);
    try std.testing.expect(!finder.contentsChanged());
}

test "zip_importer_basic" {
    var importer = ZipImporter.init(std.testing.allocator, "/path/to/archive.zip");
    defer importer.deinit();

    try std.testing.expectEqualStrings("/path/to/archive.zip", importer.archive_path);
}

test "finder_registry" {
    var registry = FinderRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.meta_path.items.len);
}

test "frozen_module_package" {
    var importer = FrozenImporter.init(std.testing.allocator);
    defer importer.deinit();

    try importer.registerFrozen(.{
        .name = "mypackage",
        .code = "package init",
        .is_package = true,
        .size = 12,
    });

    const spec = importer.findSpec("mypackage");
    try std.testing.expect(spec != null);
    try std.testing.expect(spec.?.isPackage());
}
