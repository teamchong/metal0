/// _sitebuiltins - Site-Specific Built-in Implementations
/// Mirrors cpython/Lib/_sitebuiltins.py
///
/// Special objects installed by the site module.
/// Provides quit(), exit(), copyright, credits, license objects.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Quitter - quit() and exit()
// ============================================================================

/// Quitter object for quit() and exit()
pub const Quitter = struct {
    const Self = @This();

    /// Name of the quitter ("quit" or "exit")
    name: []const u8,
    /// End-of-file character description
    eof: []const u8,

    /// Create a new Quitter
    pub fn init(name: []const u8, eof: []const u8) Self {
        return Self{
            .name = name,
            .eof = eof,
        };
    }

    /// String representation (for interactive mode hint)
    pub fn repr(self: *const Self) []const u8 {
        _ = self;
        return "Use quit() or Ctrl-D (i.e. EOF) to exit";
    }

    /// Call to exit
    pub fn call(self: *const Self, code: ?i32) noreturn {
        _ = self;
        std.process.exit(@intCast(code orelse 0));
    }

    /// Get the formatted repr string
    pub fn getRepr(self: *const Self, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Use {s}() or {s} to exit", .{ self.name, self.eof });
    }
};

/// Default quit object
pub const quit = Quitter.init("quit", "Ctrl-D (i.e. EOF)");

/// Default exit object
pub const exit = Quitter.init("exit", "Ctrl-D (i.e. EOF)");

// ============================================================================
// Printer - copyright, credits, license
// ============================================================================

/// Printer object for copyright, credits, license
pub const Printer = struct {
    const Self = @This();

    /// Name of the printer
    name: []const u8,
    /// Initial text (shown on repr)
    initial: []const u8,
    /// Full text (shown on call)
    data: ?[]const u8,
    /// File containing full text
    files: []const []const u8,
    /// Directories to search for files
    dirs: []const []const u8,

    /// Create a new Printer
    pub fn init(
        name: []const u8,
        initial: []const u8,
        data: ?[]const u8,
        files: []const []const u8,
        dirs: []const []const u8,
    ) Self {
        return Self{
            .name = name,
            .initial = initial,
            .data = data,
            .files = files,
            .dirs = dirs,
        };
    }

    /// String representation
    pub fn repr(self: *const Self) []const u8 {
        return self.initial;
    }

    /// Get full text
    pub fn getText(self: *const Self) []const u8 {
        if (self.data) |d| return d;
        // Would search files/dirs in real implementation
        return self.initial;
    }

    /// Call to print full text
    pub fn call(self: *const Self) void {
        const text = self.getText();
        std.debug.print("{s}\n", .{text});
    }
};

// ============================================================================
// Default Printers
// ============================================================================

/// Copyright notice
pub const copyright_text =
    \\Copyright (c) 2001-2024 Python Software Foundation.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 2000 BeOpen.com.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 1995-2001 Corporation for National Research Initiatives.
    \\All Rights Reserved.
    \\
    \\Copyright (c) 1991-1995 Stichting Mathematisch Centrum, Amsterdam.
    \\All Rights Reserved.
;

/// Credits text
pub const credits_text =
    \\Thanks to CWI, CNRI, BeOpen.com, Zope Corporation and a cast of thousands
    \\for supporting Python development.  See www.python.org for more information.
;

/// License initial text
pub const license_initial =
    \\Type license() to see the full license text
;

/// Full license text (abbreviated)
pub const license_text =
    \\A. HISTORY OF THE SOFTWARE
    \\==========================
    \\
    \\Python was created in the early 1990s by Guido van Rossum at Stichting
    \\Mathematisch Centrum (CWI, see http://www.cwi.nl) in the Netherlands
    \\as a successor of a language called ABC.  Guido remains Python's
    \\principal author, although it includes many contributions from others.
    \\
    \\[... Full license text available at python.org ...]
    \\
    \\PSF LICENSE AGREEMENT FOR PYTHON 3.x
    \\====================================
    \\
    \\1. This LICENSE AGREEMENT is between the Python Software Foundation
    \\("PSF"), and the Individual or Organization ("Licensee") accessing and
    \\otherwise using Python 3.x software in source or binary form and its
    \\associated documentation.
    \\
    \\[... See https://docs.python.org/3/license.html for full text ...]
;

/// Copyright printer
pub const copyright = Printer.init(
    "copyright",
    copyright_text,
    null,
    &[_][]const u8{},
    &[_][]const u8{},
);

/// Credits printer
pub const credits = Printer.init(
    "credits",
    credits_text,
    null,
    &[_][]const u8{},
    &[_][]const u8{},
);

/// License printer
pub const license = Printer.init(
    "license",
    license_initial,
    license_text,
    &[_][]const u8{ "LICENSE.txt", "LICENSE" },
    &[_][]const u8{ "/usr/share/doc/python3", "/usr/local/share/doc/python3" },
);

// ============================================================================
// Helper Object
// ============================================================================

/// Helper object for help()
pub const Helper = struct {
    const Self = @This();

    /// String representation
    pub fn repr(self: *const Self) []const u8 {
        _ = self;
        return "Type help() for interactive help, or help(object) for help about object.";
    }

    /// Call help
    pub fn call(self: *const Self, topic: ?[]const u8) void {
        _ = self;
        if (topic) |t| {
            std.debug.print("Help on {s}:\n", .{t});
            // Would invoke pydoc in real implementation
        } else {
            std.debug.print(
                \\Welcome to Python's help utility!
                \\
                \\If this is your first time using Python, you should definitely check out
                \\the tutorial on the internet at https://docs.python.org/3/tutorial/.
                \\
                \\Enter the name of any module, keyword, or topic to get help on writing
                \\Python programs and using Python modules.
                \\
            , .{});
        }
    }
};

/// Default helper
pub const help = Helper{};

// ============================================================================
// SetQuit
// ============================================================================

/// Create platform-appropriate quit/exit objects
pub fn setQuit() struct { q: Quitter, e: Quitter } {
    const eof = if (@import("builtin").os.tag == .windows)
        "Ctrl-Z plus Return"
    else
        "Ctrl-D (i.e. EOF)";

    return .{
        .q = Quitter.init("quit", eof),
        .e = Quitter.init("exit", eof),
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _sitebuiltins module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "quitter repr" {
    const allocator = std.testing.allocator;
    const repr_str = try quit.getRepr(allocator);
    defer allocator.free(repr_str);
    try std.testing.expect(std.mem.indexOf(u8, repr_str, "quit()") != null);
}

test "printer repr" {
    const repr_str = copyright.repr();
    try std.testing.expect(std.mem.indexOf(u8, repr_str, "Python Software Foundation") != null);
}

test "printer get text" {
    const text = license.getText();
    try std.testing.expect(std.mem.indexOf(u8, text, "PSF LICENSE") != null);
}

test "credits text" {
    const text = credits.repr();
    try std.testing.expect(std.mem.indexOf(u8, text, "CWI") != null);
}

test "helper repr" {
    const repr_str = help.repr();
    try std.testing.expect(std.mem.indexOf(u8, repr_str, "help()") != null);
}

test "set quit platform" {
    const qe = setQuit();
    try std.testing.expect(qe.q.name.len > 0);
    try std.testing.expect(qe.e.name.len > 0);
}
