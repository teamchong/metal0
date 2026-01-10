//! ensurepip.__main__ - CLI for bootstrapping pip
//! Reference: cpython/Lib/ensurepip/__main__.py
//!
//! Command-line interface for installing pip into a Python environment.
//! Usage: python -m ensurepip [options]

const std = @import("std");
const ensurepip = @import("../ensurepip.zig");

/// Command-line options
pub const Options = struct {
    version: bool = false,
    verbose: u8 = 0,
    upgrade: bool = false,
    user: bool = false,
    root: ?[]const u8 = null,
    altinstall: bool = false,
    default_pip: bool = false,
};

/// Parse command-line arguments
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    _ = allocator;
    var opts = Options{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--version")) {
            opts.version = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose += 1;
        } else if (std.mem.eql(u8, arg, "-U") or std.mem.eql(u8, arg, "--upgrade")) {
            opts.upgrade = true;
        } else if (std.mem.eql(u8, arg, "--user")) {
            opts.user = true;
        } else if (std.mem.eql(u8, arg, "--root")) {
            if (i + 1 < args.len) {
                i += 1;
                opts.root = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--altinstall")) {
            opts.altinstall = true;
        } else if (std.mem.eql(u8, arg, "--default-pip")) {
            opts.default_pip = true;
        }
    }

    return opts;
}

/// Main entry point
pub fn main(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const opts = try parseArgs(allocator, args);

    if (opts.version) {
        const writer = std.io.getStdOut().writer();
        try writer.print("pip {s}\n", .{ensurepip.version()});
        return;
    }

    // Validate options
    if (opts.altinstall and opts.default_pip) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("ERROR: Cannot use both --altinstall and --default-pip\n");
        return error.InvalidArguments;
    }

    // Bootstrap pip
    try ensurepip.bootstrap(.{
        .root = opts.root,
        .upgrade = opts.upgrade,
        .user = opts.user,
        .verbosity = opts.verbose,
        .altinstall = opts.altinstall,
        .default_pip = opts.default_pip,
    });
}

/// Print usage help
pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\usage: python -m ensurepip [-h] [--version] [-v] [-U] [--user]
        \\                           [--root ROOT] [--altinstall] [--default-pip]
        \\
        \\Bootstrap pip into the current Python environment.
        \\
        \\optional arguments:
        \\  -h, --help      show this help message and exit
        \\  --version       show pip version and exit
        \\  -v, --verbose   give more output (can use up to 3 times)
        \\  -U, --upgrade   upgrade pip if already installed
        \\  --user          install to user site-packages
        \\  --root ROOT     install relative to this root directory
        \\  --altinstall    make an alternate install (pip3.X instead of pip)
        \\  --default-pip   make a default pip install (pip and pip3)
        \\
    );
}

// ============================================================================
// Tests
// ============================================================================

test "parseArgs basic" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "--version", "-v" };
    const opts = try parseArgs(allocator, &args);
    try std.testing.expect(opts.version);
    try std.testing.expectEqual(@as(u8, 1), opts.verbose);
}

test "parseArgs upgrade" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "-U", "--user" };
    const opts = try parseArgs(allocator, &args);
    try std.testing.expect(opts.upgrade);
    try std.testing.expect(opts.user);
}
