//! pydoc_data.topics - Help topic data for pydoc
//! Reference: cpython/Lib/pydoc_data/topics.py
//!
//! Contains topic-to-content mappings for Python's built-in help system.
//! Topics correspond to sections in the Python language reference.

const std = @import("std");

/// Topic content - maps topic names to their help text
pub const topics = std.StaticStringMap([]const u8).initComptime(.{
    .{ "ASSERTION", "assert statement - test debugging assertions" },
    .{ "ASSIGNMENT", "assignment statements - binding names to values" },
    .{ "ATTRIBUTEMETHODS", "attribute access methods - __getattr__, __setattr__, __delattr__" },
    .{ "AUGMENTEDASSIGNMENT", "augmented assignment - +=, -=, *=, etc." },
    .{ "BASICMETHODS", "basic object methods - __init__, __del__, __repr__, etc." },
    .{ "BINARY", "binary arithmetic operations - +, -, *, /, //, %, **, etc." },
    .{ "BITWISE", "bitwise operations - &, |, ^, ~, <<, >>" },
    .{ "BOOLEAN", "boolean operations - and, or, not" },
    .{ "BREAK", "break statement - exit from loop" },
    .{ "CALLABLEMETHODS", "callable object methods - __call__" },
    .{ "CALLS", "function and method calls" },
    .{ "CLASSES", "class definitions and usage" },
    .{ "CODEOBJECTS", "code objects - compiled code" },
    .{ "COMPARISON", "comparison operations - <, <=, >, >=, ==, !=" },
    .{ "COMPLEX", "complex number type and operations" },
    .{ "CONDITIONAL", "conditional expressions - ternary operator" },
    .{ "CONTEXTMANAGERS", "context managers - with statement" },
    .{ "CONTINUE", "continue statement - skip to next iteration" },
    .{ "CONVERSIONS", "type conversions - int(), float(), str(), etc." },
    .{ "DEBUGGING", "debugging techniques and tools" },
    .{ "DELETION", "del statement - delete references" },
    .{ "DICTIONARYLITERALS", "dictionary display - {key: value}" },
    .{ "DICTIONARIES", "dictionary type and operations" },
    .{ "DYNAMICFEATURES", "dynamic features - exec, eval, compile" },
    .{ "ELLIPSIS", "... - ellipsis literal" },
    .{ "EXCEPTIONS", "exception handling - try, except, finally" },
    .{ "EXECUTION", "program execution model" },
    .{ "EXPRESSIONS", "expression syntax and evaluation" },
    .{ "FLOAT", "floating-point number type" },
    .{ "FOR", "for statement - iteration" },
    .{ "FORMATTING", "string formatting - format(), f-strings" },
    .{ "FRAMEOBJECTS", "frame objects - execution frames" },
    .{ "FUNCTIONS", "function definitions and usage" },
    .{ "GLOBAL", "global statement - access global variables" },
    .{ "IDENTIFIERS", "identifier naming rules" },
    .{ "IF", "if statement - conditional execution" },
    .{ "IMPORT", "import statement - module loading" },
    .{ "INTEGER", "integer type and operations" },
    .{ "LAMBDA", "lambda expressions - anonymous functions" },
    .{ "LISTLITERALS", "list display - [item, ...]" },
    .{ "LISTS", "list type and operations" },
    .{ "LITERALS", "literal values - numbers, strings, etc." },
    .{ "LOOPING", "looping techniques" },
    .{ "MAPPINGMETHODS", "mapping protocol methods" },
    .{ "MAPPINGS", "mapping types - dict, etc." },
    .{ "MATCH", "match statement - pattern matching" },
    .{ "METHODS", "method definitions and binding" },
    .{ "MODULES", "module system and imports" },
    .{ "NAMESPACES", "namespace and scope rules" },
    .{ "NONE", "None - null value" },
    .{ "NONLOCAL", "nonlocal statement - access enclosing scope" },
    .{ "NUMBERMETHODS", "numeric protocol methods" },
    .{ "NUMBERS", "numeric types - int, float, complex" },
    .{ "OBJECTS", "object model and data model" },
    .{ "OPERATORS", "operator precedence and usage" },
    .{ "PACKAGES", "package structure and imports" },
    .{ "PASS", "pass statement - null operation" },
    .{ "POWER", "exponentiation - **" },
    .{ "RAISE", "raise statement - signal exception" },
    .{ "RETURN", "return statement - exit function" },
    .{ "SCOPING", "scope and name resolution" },
    .{ "SEQUENCEMETHODS", "sequence protocol methods" },
    .{ "SEQUENCES", "sequence types - list, tuple, str, etc." },
    .{ "SETLITERALS", "set display - {item, ...}" },
    .{ "SETS", "set type and operations" },
    .{ "SHIFTING", "bit shifting - <<, >>" },
    .{ "SLICINGS", "slice notation - [start:stop:step]" },
    .{ "SPECIALATTRIBUTES", "special attributes - __name__, __doc__, etc." },
    .{ "SPECIALIDENTIFIERS", "special identifiers - _, __xxx__, etc." },
    .{ "SPECIALMETHODS", "special method names - dunder methods" },
    .{ "STRINGMETHODS", "string methods" },
    .{ "STRINGS", "string type and operations" },
    .{ "SUBSCRIPTS", "subscript notation - obj[key]" },
    .{ "TRACEBACKOBJECTS", "traceback objects - exception info" },
    .{ "TRY", "try statement - exception handling" },
    .{ "TUPLES", "tuple type and operations" },
    .{ "TUPLELITERALS", "tuple display - (item, ...)" },
    .{ "TYPEOBJECTS", "type objects - classes" },
    .{ "TYPES", "built-in types" },
    .{ "UNARY", "unary operations - +, -, ~, not" },
    .{ "UNICODE", "Unicode and string encoding" },
    .{ "WHILE", "while statement - loop" },
    .{ "WITH", "with statement - context managers" },
    .{ "YIELD", "yield expression - generators" },
});

/// Get help text for a topic
pub fn getTopic(name: []const u8) ?[]const u8 {
    return topics.get(name);
}

/// Get list of all topic names
pub fn getTopicNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(allocator);
    for (topics.keys()) |key| {
        try result.append(allocator, key);
    }
    return result;
}

/// Check if a topic exists
pub fn hasTopic(name: []const u8) bool {
    return topics.has(name);
}

// ============================================================================
// Tests
// ============================================================================

test "getTopic" {
    const result = getTopic("IF");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "conditional") != null);
}

test "hasTopic" {
    try std.testing.expect(hasTopic("FOR"));
    try std.testing.expect(hasTopic("WHILE"));
    try std.testing.expect(!hasTopic("NONEXISTENT"));
}
