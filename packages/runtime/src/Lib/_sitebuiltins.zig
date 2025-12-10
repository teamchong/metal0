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

    /// Thread-local buffer for file contents
    const FileBuffer = struct {
        threadlocal var buf: [65536]u8 = undefined;
        threadlocal var len: usize = 0;
    };

    /// Get full text by searching files in directories
    pub fn getText(self: *const Self) []const u8 {
        // If data is already set, return it
        if (self.data) |d| return d;

        // Search through directories and files
        for (self.dirs) |dir| {
            for (self.files) |filename| {
                // Build path: dir/filename
                var path_buf: [512]u8 = undefined;
                const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, filename }) catch continue;

                // Try to open and read the file
                const file = std.fs.cwd().openFile(path, .{}) catch continue;
                defer file.close();

                const bytes_read = file.readAll(&FileBuffer.buf) catch continue;
                FileBuffer.len = bytes_read;

                if (bytes_read > 0) {
                    return FileBuffer.buf[0..FileBuffer.len];
                }
            }
        }

        // Also try just the filenames without directory prefix
        for (self.files) |filename| {
            const file = std.fs.cwd().openFile(filename, .{}) catch continue;
            defer file.close();

            const bytes_read = file.readAll(&FileBuffer.buf) catch continue;
            FileBuffer.len = bytes_read;

            if (bytes_read > 0) {
                return FileBuffer.buf[0..FileBuffer.len];
            }
        }

        // Fallback to initial text
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

    /// Built-in topic documentation
    const topics = struct {
        const keywords = [_]struct { name: []const u8, doc: []const u8 }{
            .{ .name = "False", .doc = "The false boolean value." },
            .{ .name = "True", .doc = "The true boolean value." },
            .{ .name = "None", .doc = "The null object; represents absence of value." },
            .{ .name = "and", .doc = "Boolean AND operator. Returns first falsy operand or last operand." },
            .{ .name = "or", .doc = "Boolean OR operator. Returns first truthy operand or last operand." },
            .{ .name = "not", .doc = "Boolean NOT operator. Returns True if operand is falsy." },
            .{ .name = "if", .doc = "Conditional statement. Syntax: if condition: body [elif condition: body] [else: body]" },
            .{ .name = "else", .doc = "Alternative branch of if/try/for/while statements." },
            .{ .name = "elif", .doc = "Alternative condition in if statement." },
            .{ .name = "for", .doc = "Iteration statement. Syntax: for item in iterable: body [else: body]" },
            .{ .name = "while", .doc = "Loop statement. Syntax: while condition: body [else: body]" },
            .{ .name = "break", .doc = "Exit the nearest enclosing loop." },
            .{ .name = "continue", .doc = "Skip to the next iteration of the nearest enclosing loop." },
            .{ .name = "def", .doc = "Define a function. Syntax: def name(args): body" },
            .{ .name = "return", .doc = "Return from a function, optionally with a value." },
            .{ .name = "class", .doc = "Define a class. Syntax: class Name(bases): body" },
            .{ .name = "import", .doc = "Import a module. Syntax: import module [as alias]" },
            .{ .name = "from", .doc = "Import specific items from a module. Syntax: from module import item [as alias]" },
            .{ .name = "try", .doc = "Exception handling. Syntax: try: body except [Type]: handler [finally: cleanup]" },
            .{ .name = "except", .doc = "Catch exceptions in a try block." },
            .{ .name = "finally", .doc = "Cleanup code that always runs after try/except." },
            .{ .name = "raise", .doc = "Raise an exception." },
            .{ .name = "with", .doc = "Context manager statement. Syntax: with expr [as var]: body" },
            .{ .name = "as", .doc = "Alias in import/except/with statements." },
            .{ .name = "pass", .doc = "Null statement; placeholder that does nothing." },
            .{ .name = "lambda", .doc = "Anonymous function expression. Syntax: lambda args: expression" },
            .{ .name = "yield", .doc = "Generator expression. Produces values one at a time." },
            .{ .name = "global", .doc = "Declare a variable as global within function scope." },
            .{ .name = "nonlocal", .doc = "Declare a variable as belonging to enclosing scope." },
            .{ .name = "assert", .doc = "Debugging assertion. Raises AssertionError if condition is false." },
            .{ .name = "del", .doc = "Delete a variable or item." },
            .{ .name = "in", .doc = "Membership test operator. Also used in for loops." },
            .{ .name = "is", .doc = "Identity test operator. Tests if two objects are the same object." },
        };

        fn lookup(name: []const u8) ?[]const u8 {
            for (keywords) |kw| {
                if (std.mem.eql(u8, kw.name, name)) {
                    return kw.doc;
                }
            }
            return null;
        }
    };

    /// Call help with optional topic
    pub fn call(self: *const Self, topic: ?[]const u8) void {
        _ = self;
        const stdout = std.io.getStdOut().writer();

        if (topic) |t| {
            // Try to find documentation for the topic
            if (topics.lookup(t)) |doc| {
                stdout.print("Help on keyword '{s}':\n\n{s}\n", .{ t, doc }) catch {};
            } else {
                // Try to find module documentation
                stdout.print("Help on '{s}':\n\nNo documentation available for '{s}'.\n", .{ t, t }) catch {};
                stdout.print("Try 'help()' for interactive help or visit https://docs.python.org/3/\n", .{}) catch {};
            }
        } else {
            stdout.print(
                \\Welcome to Python's help utility!
                \\
                \\If this is your first time using Python, you should definitely check out
                \\the tutorial on the internet at https://docs.python.org/3/tutorial/.
                \\
                \\Enter the name of any module, keyword, or topic to get help on writing
                \\Python programs and using Python modules.
                \\
                \\Keywords: False, True, None, and, or, not, if, else, elif, for, while,
                \\          break, continue, def, return, class, import, from, try, except,
                \\          finally, raise, with, as, pass, lambda, yield, global, nonlocal,
                \\          assert, del, in, is
                \\
            , .{}) catch {};
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
