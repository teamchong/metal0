//! CPython source: Lib/rlcompleter.py
//!
//! Provides word completion for interactive Python interpreter.
//! Works with readline library for tab completion.
//!
//! Mirrors: CPython Lib/rlcompleter.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Completer class
// ============================================================================

pub const Completer = struct {
    allocator: std.mem.Allocator,

    /// Namespace for completion lookups
    namespace: hashmap_helper.StringHashMap([]const u8),

    /// Use __main__ namespace if true
    use_main_ns: bool = false,

    /// Cache for last completion
    matches: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Completer {
        return .{
            .allocator = allocator,
            .namespace = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .matches = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn initWithNamespace(
        allocator: std.mem.Allocator,
        namespace: hashmap_helper.StringHashMap([]const u8),
    ) Completer {
        return .{
            .allocator = allocator,
            .namespace = namespace,
            .matches = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Completer) void {
        self.namespace.deinit();
        self.matches.deinit();
    }

    /// Main completion method - returns next match for text
    pub fn complete(self: *Completer, text: []const u8, state: usize) ?[]const u8 {
        // If this is the first call (state == 0), compute all matches
        if (state == 0) {
            self.computeMatches(text);
        }

        // Return the state-th match
        if (state < self.matches.items.len) {
            return self.matches.items[state];
        }
        return null;
    }

    /// Compute all matches for the given text
    fn computeMatches(self: *Completer, text: []const u8) void {
        self.matches.clearRetainingCapacity();

        // Check if text contains a dot (attribute completion)
        if (std.mem.indexOf(u8, text, ".")) |_| {
            self.attrMatches(text);
        } else {
            self.globalMatches(text);
        }
    }

    /// Find global matches for simple names
    fn globalMatches(self: *Completer, text: []const u8) void {
        // Add matching keywords
        for (PYTHON_KEYWORDS) |keyword| {
            if (std.mem.startsWith(u8, keyword, text)) {
                self.matches.append(keyword) catch continue;
            }
        }

        // Add matching builtins
        for (BUILTIN_NAMES) |name| {
            if (std.mem.startsWith(u8, name, text)) {
                self.matches.append(name) catch continue;
            }
        }

        // Add matches from namespace
        var it = self.namespace.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, text)) {
                self.matches.append(entry.key_ptr.*) catch continue;
            }
        }
    }

    /// Find attribute matches for dotted names
    fn attrMatches(self: *Completer, text: []const u8) void {
        // Find the object and attribute prefix
        const last_dot = std.mem.lastIndexOf(u8, text, ".") orelse return;
        const obj_text = text[0..last_dot];
        const attr_prefix = text[last_dot + 1 ..];

        _ = obj_text;

        // For now, just match common object methods
        for (OBJECT_METHODS) |method| {
            if (std.mem.startsWith(u8, method, attr_prefix)) {
                var full_match = self.allocator.alloc(u8, text.len) catch continue;
                @memcpy(full_match[0..last_dot], text[0..last_dot]);
                full_match[last_dot] = '.';
                @memcpy(full_match[last_dot + 1 ..], method);
                self.matches.append(full_match) catch continue;
            }
        }
    }
};

// ============================================================================
// Python keywords for completion
// ============================================================================

pub const PYTHON_KEYWORDS = [_][]const u8{
    "False",
    "None",
    "True",
    "and",
    "as",
    "assert",
    "async",
    "await",
    "break",
    "class",
    "continue",
    "def",
    "del",
    "elif",
    "else",
    "except",
    "finally",
    "for",
    "from",
    "global",
    "if",
    "import",
    "in",
    "is",
    "lambda",
    "nonlocal",
    "not",
    "or",
    "pass",
    "raise",
    "return",
    "try",
    "while",
    "with",
    "yield",
};

// ============================================================================
// Python builtin names for completion
// ============================================================================

pub const BUILTIN_NAMES = [_][]const u8{
    "abs",
    "all",
    "any",
    "ascii",
    "bin",
    "bool",
    "breakpoint",
    "bytearray",
    "bytes",
    "callable",
    "chr",
    "classmethod",
    "compile",
    "complex",
    "delattr",
    "dict",
    "dir",
    "divmod",
    "enumerate",
    "eval",
    "exec",
    "filter",
    "float",
    "format",
    "frozenset",
    "getattr",
    "globals",
    "hasattr",
    "hash",
    "help",
    "hex",
    "id",
    "input",
    "int",
    "isinstance",
    "issubclass",
    "iter",
    "len",
    "list",
    "locals",
    "map",
    "max",
    "memoryview",
    "min",
    "next",
    "object",
    "oct",
    "open",
    "ord",
    "pow",
    "print",
    "property",
    "range",
    "repr",
    "reversed",
    "round",
    "set",
    "setattr",
    "slice",
    "sorted",
    "staticmethod",
    "str",
    "sum",
    "super",
    "tuple",
    "type",
    "vars",
    "zip",
};

// ============================================================================
// Common object methods for attribute completion
// ============================================================================

pub const OBJECT_METHODS = [_][]const u8{
    "__class__",
    "__delattr__",
    "__dict__",
    "__dir__",
    "__doc__",
    "__eq__",
    "__format__",
    "__ge__",
    "__getattribute__",
    "__gt__",
    "__hash__",
    "__init__",
    "__init_subclass__",
    "__le__",
    "__lt__",
    "__ne__",
    "__new__",
    "__reduce__",
    "__reduce_ex__",
    "__repr__",
    "__setattr__",
    "__sizeof__",
    "__str__",
    "__subclasshook__",
};

// ============================================================================
// Module-level completer instance
// ============================================================================

var global_completer: ?Completer = null;

/// Get or create the global completer
pub fn getCompleter(allocator: std.mem.Allocator) *Completer {
    if (global_completer == null) {
        global_completer = Completer.init(allocator);
    }
    return &global_completer.?;
}

/// Reset the global completer
pub fn resetCompleter() void {
    if (global_completer) |*c| {
        c.deinit();
    }
    global_completer = null;
}

// ============================================================================
// Tests
// ============================================================================

test "Completer init" {
    const allocator = std.testing.allocator;
    var completer = Completer.init(allocator);
    defer completer.deinit();

    try std.testing.expect(!completer.use_main_ns);
}

test "Completer complete keywords" {
    const allocator = std.testing.allocator;
    var completer = Completer.init(allocator);
    defer completer.deinit();

    // Get first match for "def"
    const match = completer.complete("def", 0);
    try std.testing.expect(match != null);
    try std.testing.expectEqualStrings("def", match.?);
}

test "Completer complete builtins" {
    const allocator = std.testing.allocator;
    var completer = Completer.init(allocator);
    defer completer.deinit();

    // Get first match for "pri"
    const match = completer.complete("pri", 0);
    try std.testing.expect(match != null);
    try std.testing.expectEqualStrings("print", match.?);
}

test "Completer complete no match" {
    const allocator = std.testing.allocator;
    var completer = Completer.init(allocator);
    defer completer.deinit();

    // Try to match something that doesn't exist
    const match = completer.complete("xyz123abc", 0);
    try std.testing.expect(match == null);
}

test "PYTHON_KEYWORDS contains def" {
    var found = false;
    for (PYTHON_KEYWORDS) |kw| {
        if (std.mem.eql(u8, kw, "def")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "BUILTIN_NAMES contains print" {
    var found = false;
    for (BUILTIN_NAMES) |name| {
        if (std.mem.eql(u8, name, "print")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "getCompleter" {
    const allocator = std.testing.allocator;
    const c = getCompleter(allocator);
    try std.testing.expect(c != null);
    resetCompleter();
}
