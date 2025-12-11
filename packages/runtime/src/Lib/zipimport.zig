//! CPython source: Lib/zipimport.py
//!
//! Provides support for importing Python modules from ZIP archives.
//!
//! Mirrors: CPython Lib/zipimport.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const ZipImportError = error{
    NotZipFile,
    BadZipFile,
    ModuleNotFound,
    IoError,
    OutOfMemory,
};

// ============================================================================
// zipimporter
// ============================================================================

/// Importer for ZIP archives
pub const zipimporter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Path to the zip archive
    archive: []const u8,
    /// Prefix within the archive
    prefix: []const u8,
    /// Cached file list
    files: hashmap_helper.StringHashMap(FileInfo),

    const FileInfo = struct {
        offset: u64,
        compressed_size: u64,
        uncompressed_size: u64,
        compression_method: u16,
    };

    /// Create a new zipimporter
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        // Validate it's a zip file
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return error.NotZipFile;
        };
        defer file.close();

        // Check for ZIP magic number
        var magic: [4]u8 = undefined;
        _ = file.read(&magic) catch return error.IoError;

        if (!std.mem.eql(u8, magic[0..2], "PK")) {
            return error.NotZipFile;
        }

        // Parse prefix if path contains archive path
        var archive = path;
        var prefix: []const u8 = "";

        if (std.mem.indexOf(u8, path, ".zip")) |idx| {
            if (idx + 4 < path.len and path[idx + 4] == '/') {
                archive = path[0 .. idx + 4];
                prefix = path[idx + 5 ..];
            }
        }

        return Self{
            .allocator = allocator,
            .archive = archive,
            .prefix = prefix,
            .files = hashmap_helper.StringHashMap(FileInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.files.deinit();
    }

    /// Find a module in the archive
    pub fn find_module(self: *Self, fullname: []const u8, path: ?[]const u8) !?*Self {
        _ = path;

        // Convert module name to path
        var module_path_buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&module_path_buf);
        const writer = fbs.writer();

        if (self.prefix.len > 0) {
            writer.writeAll(self.prefix) catch return null;
            writer.writeByte('/') catch return null;
        }

        // Replace dots with slashes
        for (fullname) |c| {
            if (c == '.') {
                writer.writeByte('/') catch return null;
            } else {
                writer.writeByte(c) catch return null;
            }
        }

        const base_path = fbs.getWritten();

        // Check for package (__init__.py)
        var init_path_buf: [600]u8 = undefined;
        const init_path = std.fmt.bufPrint(&init_path_buf, "{s}/__init__.py", .{base_path}) catch return null;

        if (self.files.contains(init_path)) {
            return self;
        }

        // Check for module (.py)
        var py_path_buf: [600]u8 = undefined;
        const py_path = std.fmt.bufPrint(&py_path_buf, "{s}.py", .{base_path}) catch return null;

        if (self.files.contains(py_path)) {
            return self;
        }

        return null;
    }

    /// Load a module from the archive
    pub fn load_module(self: *Self, fullname: []const u8) !ModuleSpec {
        _ = self;
        return ModuleSpec{
            .name = fullname,
            .loader = null,
            .origin = null,
            .submodule_search_locations = null,
            .is_package = false,
        };
    }

    /// Get the source code of a module
    pub fn get_source(self: *Self, fullname: []const u8) !?[]u8 {
        // Convert module name to file path
        var path_buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&path_buf);
        const writer = fbs.writer();

        if (self.prefix.len > 0) {
            writer.writeAll(self.prefix) catch return null;
            writer.writeByte('/') catch return null;
        }

        for (fullname) |c| {
            if (c == '.') {
                writer.writeByte('/') catch return null;
            } else {
                writer.writeByte(c) catch return null;
            }
        }
        writer.writeAll(".py") catch return null;

        const file_path = fbs.getWritten();
        return self.readFileFromArchive(file_path);
    }

    /// Read a file from the ZIP archive
    fn readFileFromArchive(self: *Self, inner_path: []const u8) !?[]u8 {
        // Open the archive
        const file = std.fs.cwd().openFile(self.archive, .{}) catch return null;
        defer file.close();

        // Use std.zip to read the archive
        var zip_iter = std.zip.Iterator(@TypeOf(file.seekableStream())).init(file.seekableStream());

        while (zip_iter.next() catch return null) |entry| {
            if (std.mem.eql(u8, entry.filename, inner_path)) {
                // Found the file, decompress it
                var decompressed = std.ArrayList(u8).init(self.allocator);
                errdefer decompressed.deinit();

                entry.decompress(decompressed.writer(), null) catch |err| {
                    // If stored (no compression), read directly
                    if (err == error.Unsupported) {
                        // Try reading uncompressed data
                        const data = try self.allocator.alloc(u8, @intCast(entry.uncompressed_size));
                        errdefer self.allocator.free(data);

                        file.seekableStream().seekTo(entry.header_offset) catch return null;
                        const n = file.read(data) catch return null;
                        if (n < data.len) {
                            self.allocator.free(data);
                            return null;
                        }
                        return data;
                    }
                    return null;
                };

                return decompressed.toOwnedSlice();
            }
        }

        return null;
    }

    /// Get compiled bytecode of a module
    pub fn get_code(self: *Self, fullname: []const u8) !?[]u8 {
        // Try to find .pyc file first
        var path_buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&path_buf);
        const writer = fbs.writer();

        if (self.prefix.len > 0) {
            writer.writeAll(self.prefix) catch return null;
            writer.writeByte('/') catch return null;
        }

        // Look for __pycache__/module.cpython-XX.pyc
        writer.writeAll("__pycache__/") catch return null;
        for (fullname) |c| {
            if (c == '.') {
                writer.writeByte('/') catch return null;
            } else {
                writer.writeByte(c) catch return null;
            }
        }
        writer.writeAll(".cpython-311.pyc") catch return null;

        const pyc_path = fbs.getWritten();
        return self.readFileFromArchive(pyc_path);
    }

    /// Get data from the archive (arbitrary file)
    pub fn get_data(self: *Self, path: []const u8) ![]u8 {
        if (self.readFileFromArchive(path)) |data| {
            return data;
        }
        return error.ModuleNotFound;
    }

    /// Get the filename for a module
    pub fn get_filename(self: *Self, fullname: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ self.archive, fullname });
    }

    /// Check if module is a package
    pub fn is_package(self: *Self, fullname: []const u8) !bool {
        var path_buf: [600]u8 = undefined;
        const init_path = std.fmt.bufPrint(&path_buf, "{s}/__init__.py", .{fullname}) catch return false;
        return self.files.contains(init_path);
    }
};

// ============================================================================
// ModuleSpec
// ============================================================================

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*anyopaque,
    origin: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    is_package: bool,
};

// ============================================================================
// Module-level cache
// ============================================================================

/// Cache of zipimporter instances by path
var _zip_directory_cache: ?hashmap_helper.StringHashMap(*zipimporter) = null;

/// Get or create a zipimporter for a path
pub fn get_importer(allocator: std.mem.Allocator, path: []const u8) !*zipimporter {
    if (_zip_directory_cache == null) {
        _zip_directory_cache = hashmap_helper.StringHashMap(*zipimporter).init(allocator);
    }

    if (_zip_directory_cache.?.get(path)) |importer| {
        return importer;
    }

    const importer = try allocator.create(zipimporter);
    importer.* = try zipimporter.init(allocator, path);
    try _zip_directory_cache.?.put(path, importer);
    return importer;
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
    if (_zip_directory_cache) |*cache| {
        cache.deinit();
        _zip_directory_cache = null;
    }
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "ModuleSpec" {
    const spec = ModuleSpec{
        .name = "test_module",
        .loader = null,
        .origin = "test.zip/test_module.py",
        .submodule_search_locations = null,
        .is_package = false,
    };

    try std.testing.expectEqualStrings("test_module", spec.name);
    try std.testing.expect(!spec.is_package);
}

test "zipimporter get_filename" {
    const allocator = std.testing.allocator;

    // Create a mock zipimporter
    var importer = zipimporter{
        .allocator = allocator,
        .archive = "test.zip",
        .prefix = "",
        .files = hashmap_helper.StringHashMap(zipimporter.FileInfo).init(allocator),
    };
    defer importer.deinit();

    const filename = try importer.get_filename("mymodule");
    defer allocator.free(filename);

    try std.testing.expect(std.mem.indexOf(u8, filename, "test.zip") != null);
    try std.testing.expect(std.mem.endsWith(u8, filename, "mymodule.py"));
}
