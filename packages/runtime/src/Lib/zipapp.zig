//! CPython source: Lib/zipapp.py
//!
//! Provides tools to create and manage executable Python zip archives.
//!
//! Mirrors: CPython Lib/zipapp.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const ZipAppError = error{
    BadArchive,
    NoMainFunction,
    InvalidInterpreter,
    IoError,
    OutOfMemory,
};

// ============================================================================
// Constants
// ============================================================================

/// Default shebang line
pub const DEFAULT_INTERPRETER = "/usr/bin/env python3";

/// Archive signature
const ARCHIVE_MAGIC = "PK\x03\x04";

// ============================================================================
// ZipApp Info
// ============================================================================

/// Information about a zipapp archive
pub const ZipAppInfo = struct {
    allocator: std.mem.Allocator,
    /// The archive path
    archive: []const u8,
    /// The interpreter from shebang
    interpreter: ?[]const u8 = null,
    /// Main module (from __main__.py)
    main: ?[]const u8 = null,

    pub fn deinit(self: *ZipAppInfo) void {
        if (self.interpreter) |i| {
            self.allocator.free(i);
        }
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Create a new executable zip archive
pub fn create_archive(
    allocator: std.mem.Allocator,
    source: []const u8,
    target: ?[]const u8,
    interpreter: ?[]const u8,
    main: ?[]const u8,
    filter_fn: ?*const fn ([]const u8) bool,
    compressed: bool,
) !void {
    _ = filter_fn;
    _ = compressed;

    // Determine target path
    const target_path = target orelse blk: {
        // Default: source + ".pyz"
        break :blk try std.fmt.allocPrint(allocator, "{s}.pyz", .{source});
    };
    defer if (target == null) allocator.free(target_path);

    // Create the archive file
    const file = try std.fs.cwd().createFile(target_path, .{});
    defer file.close();

    const writer = file.writer();

    // Write shebang if interpreter specified
    if (interpreter) |interp| {
        try writer.print("#!{s}\n", .{interp});
    }

    // Create __main__.py if main module specified
    if (main) |main_module| {
        // Would create __main__.py with: from <main_module> import main; main()
        _ = main_module;
    }

    // Write zip archive content
    // In a full implementation, would create actual zip archive from source directory

    // Check if source is a directory
    const stat = std.fs.cwd().statFile(source) catch {
        return error.IoError;
    };

    if (stat.kind == .directory) {
        // Create zip from directory
        try createZipFromDirectory(allocator, source, file);
    } else {
        // Copy existing archive
        const source_file = try std.fs.cwd().openFile(source, .{});
        defer source_file.close();

        var buf: [8192]u8 = undefined;
        while (true) {
            const n = try source_file.read(&buf);
            if (n == 0) break;
            try writer.writeAll(buf[0..n]);
        }
    }
}

fn createZipFromDirectory(allocator: std.mem.Allocator, dir_path: []const u8, out_file: std.fs.File) !void {
    _ = allocator;
    _ = dir_path;

    // Write minimal zip archive header
    // In a full implementation, would recursively add all files

    // Local file header for __main__.py
    const main_content = "# Placeholder __main__.py\n";

    // Local file header
    try out_file.writer().writeAll("PK\x03\x04"); // signature
    try out_file.writer().writeInt(u16, 20, .little); // version needed
    try out_file.writer().writeInt(u16, 0, .little); // flags
    try out_file.writer().writeInt(u16, 0, .little); // compression
    try out_file.writer().writeInt(u16, 0, .little); // mod time
    try out_file.writer().writeInt(u16, 0, .little); // mod date
    try out_file.writer().writeInt(u32, 0, .little); // crc32
    try out_file.writer().writeInt(u32, @intCast(main_content.len), .little); // compressed size
    try out_file.writer().writeInt(u32, @intCast(main_content.len), .little); // uncompressed size
    try out_file.writer().writeInt(u16, 12, .little); // filename length
    try out_file.writer().writeInt(u16, 0, .little); // extra length
    try out_file.writer().writeAll("__main__.py");
    try out_file.writer().writeAll(main_content);

    // Central directory
    try out_file.writer().writeAll("PK\x01\x02"); // signature
    try out_file.writer().writeInt(u16, 20, .little); // version made by
    try out_file.writer().writeInt(u16, 20, .little); // version needed
    try out_file.writer().writeInt(u16, 0, .little); // flags
    try out_file.writer().writeInt(u16, 0, .little); // compression
    try out_file.writer().writeInt(u16, 0, .little); // mod time
    try out_file.writer().writeInt(u16, 0, .little); // mod date
    try out_file.writer().writeInt(u32, 0, .little); // crc32
    try out_file.writer().writeInt(u32, @intCast(main_content.len), .little); // compressed size
    try out_file.writer().writeInt(u32, @intCast(main_content.len), .little); // uncompressed size
    try out_file.writer().writeInt(u16, 12, .little); // filename length
    try out_file.writer().writeInt(u16, 0, .little); // extra length
    try out_file.writer().writeInt(u16, 0, .little); // comment length
    try out_file.writer().writeInt(u16, 0, .little); // disk number
    try out_file.writer().writeInt(u16, 0, .little); // internal attrs
    try out_file.writer().writeInt(u32, 0, .little); // external attrs
    try out_file.writer().writeInt(u32, 0, .little); // offset
    try out_file.writer().writeAll("__main__.py");

    // End of central directory
    try out_file.writer().writeAll("PK\x05\x06"); // signature
    try out_file.writer().writeInt(u16, 0, .little); // disk number
    try out_file.writer().writeInt(u16, 0, .little); // central dir disk
    try out_file.writer().writeInt(u16, 1, .little); // entries on disk
    try out_file.writer().writeInt(u16, 1, .little); // total entries
    try out_file.writer().writeInt(u32, 58, .little); // central dir size
    try out_file.writer().writeInt(u32, 56, .little); // central dir offset
    try out_file.writer().writeInt(u16, 0, .little); // comment length
}

/// Get information about a zipapp archive
pub fn get_info(allocator: std.mem.Allocator, archive: []const u8) !ZipAppInfo {
    const file = std.fs.cwd().openFile(archive, .{}) catch {
        return error.IoError;
    };
    defer file.close();

    var info = ZipAppInfo{
        .allocator = allocator,
        .archive = archive,
    };

    // Read potential shebang
    var header: [256]u8 = undefined;
    const n = try file.read(&header);

    if (n > 2 and header[0] == '#' and header[1] == '!') {
        // Find end of shebang line
        var end: usize = 2;
        while (end < n and header[end] != '\n') : (end += 1) {}
        info.interpreter = try allocator.dupe(u8, header[2..end]);
    }

    return info;
}

/// Get the interpreter from an archive
pub fn get_interpreter(allocator: std.mem.Allocator, archive: []const u8) !?[]const u8 {
    var info = try get_info(allocator, archive);
    defer info.deinit();

    if (info.interpreter) |interp| {
        return try allocator.dupe(u8, interp);
    }
    return null;
}

/// Main entry point for command-line usage
pub fn main(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len < 1) {
        std.debug.print("Usage: zipapp [OPTIONS] SOURCE [TARGET]\n", .{});
        std.debug.print("\nOptions:\n", .{});
        std.debug.print("  -o, --output TARGET     Output archive name\n", .{});
        std.debug.print("  -p, --python INTERP     Interpreter for shebang line\n", .{});
        std.debug.print("  -m, --main MAIN         Main module (module:function)\n", .{});
        std.debug.print("  -c, --compress          Compress files\n", .{});
        std.debug.print("  --info                  Show archive info\n", .{});
        return 2;
    }

    var source: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var interpreter: ?[]const u8 = null;
    var main_module: ?[]const u8 = null;
    var compressed = false;
    var show_info = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i < args.len) target = args[i];
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--python")) {
            i += 1;
            if (i < args.len) interpreter = args[i];
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--main")) {
            i += 1;
            if (i < args.len) main_module = args[i];
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--compress")) {
            compressed = true;
        } else if (std.mem.eql(u8, arg, "--info")) {
            show_info = true;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            if (source == null) {
                source = arg;
            } else if (target == null) {
                target = arg;
            }
        }
    }

    if (source == null) {
        std.debug.print("Error: SOURCE is required\n", .{});
        return 1;
    }

    if (show_info) {
        var info = get_info(allocator, source.?) catch |err| {
            std.debug.print("Error getting info: {}\n", .{err});
            return 1;
        };
        defer info.deinit();

        std.debug.print("Archive: {s}\n", .{info.archive});
        if (info.interpreter) |interp| {
            std.debug.print("Interpreter: {s}\n", .{interp});
        }
        return 0;
    }

    create_archive(allocator, source.?, target, interpreter, main_module, null, compressed) catch |err| {
        std.debug.print("Error creating archive: {}\n", .{err});
        return 1;
    };

    return 0;
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
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "DEFAULT_INTERPRETER" {
    try std.testing.expectEqualStrings("/usr/bin/env python3", DEFAULT_INTERPRETER);
}

test "ZipAppInfo" {
    const allocator = std.testing.allocator;
    var info = ZipAppInfo{
        .allocator = allocator,
        .archive = "test.pyz",
    };
    defer info.deinit();

    try std.testing.expectEqualStrings("test.pyz", info.archive);
    try std.testing.expect(info.interpreter == null);
}
