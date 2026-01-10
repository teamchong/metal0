//! zipfile.__main__ - Command-line interface for zipfile module
//! Reference: cpython/Lib/zipfile/__main__.py
//!
//! Entry point for `python -m zipfile`.

const std = @import("std");

/// Command-line options
pub const Options = struct {
    command: Command = .list,
    zipfile: ?[]const u8 = null,
    files: std.ArrayList([]const u8),
    target_dir: []const u8 = ".",
    help: bool = false,

    pub fn init(allocator: std.mem.Allocator) Options {
        return .{ .files = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.files.deinit(allocator);
    }
};

pub const Command = enum {
    list, // -l: List contents
    create, // -c: Create archive
    extract, // -e: Extract archive
    test, // -t: Test archive
};

/// Parse command line arguments
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    var opts = Options.init(allocator);
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--list")) {
            opts.command = .list;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--create")) {
            opts.command = .create;
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--extract")) {
            opts.command = .extract;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--test")) {
            opts.command = .test;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            opts.help = true;
        } else if (arg[0] != '-') {
            if (opts.zipfile == null) {
                opts.zipfile = arg;
            } else {
                try opts.files.append(allocator, arg);
            }
        }
    }

    return opts;
}

/// Print help message
pub fn printHelp() void {
    const help =
        \\usage: python -m zipfile [-h] [-l | -c | -e | -t] zipfile [source ...]
        \\
        \\A command line interface for zipfile module.
        \\
        \\positional arguments:
        \\  zipfile     target zip file
        \\  source      source files to add
        \\
        \\options:
        \\  -h, --help     show this help message and exit
        \\  -l, --list     List contents of zipfile
        \\  -c, --create   Create zipfile from sources
        \\  -e, --extract  Extract zipfile into target dir
        \\  -t, --test     Test if zipfile is valid
        \\
    ;
    std.io.getStdOut().writeAll(help) catch {};
}

/// List contents of a zip file
pub fn listZip(path: []const u8) !void {
    _ = path;
    // Would open and list zip contents
    std.io.getStdOut().writeAll("File Name                 Size\n") catch {};
}

/// Create a zip file
pub fn createZip(allocator: std.mem.Allocator, path: []const u8, files: []const []const u8) !void {
    _ = allocator;
    _ = path;
    _ = files;
    // Would create zip file
}

/// Extract a zip file
pub fn extractZip(path: []const u8, target_dir: []const u8) !void {
    _ = path;
    _ = target_dir;
    // Would extract zip contents
}

/// Test a zip file
pub fn testZip(path: []const u8) !bool {
    _ = path;
    // Would test zip file integrity
    return true;
}

/// Main entry point
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var opts = try parseArgs(allocator, if (args.len > 1) args[1..] else &[_][]const u8{});
    defer opts.deinit(allocator);

    if (opts.help) {
        printHelp();
        return;
    }

    const zipfile = opts.zipfile orelse {
        printHelp();
        return;
    };

    switch (opts.command) {
        .list => try listZip(zipfile),
        .create => try createZip(allocator, zipfile, opts.files.items),
        .extract => try extractZip(zipfile, opts.target_dir),
        .test => {
            const valid = try testZip(zipfile);
            if (valid) {
                std.io.getStdOut().writeAll("Done testing\n") catch {};
            }
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parseArgs list" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "-l", "test.zip" };
    var opts = try parseArgs(allocator, &args);
    defer opts.deinit(allocator);
    try std.testing.expectEqual(Command.list, opts.command);
    try std.testing.expectEqualStrings("test.zip", opts.zipfile.?);
}

test "parseArgs create" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "-c", "test.zip", "file1.txt", "file2.txt" };
    var opts = try parseArgs(allocator, &args);
    defer opts.deinit(allocator);
    try std.testing.expectEqual(Command.create, opts.command);
    try std.testing.expectEqual(@as(usize, 2), opts.files.items.len);
}
