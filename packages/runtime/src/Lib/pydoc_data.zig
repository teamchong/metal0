//! Python 'pydoc_data' module - Data for pydoc
//!
//! Contains data used by the pydoc module.
//!
//! Mirrors: CPython Lib/pydoc_data/

const std = @import("std");

// ============================================================================
// Topics - Help topics for pydoc
// ============================================================================

pub const topics = struct {
    /// Help topic data
    pub const data = std.StaticStringMap([]const u8).initComptime(.{
        .{ "BOOLEAN", "Boolean Operations\n================\n\nBoolean operations: and, or, not\n" },
        .{ "COMPARISON", "Comparison Operations\n===================\n\nComparison operations: <, <=, >, >=, ==, !=\n" },
        .{ "NUMBERS", "Numeric Types\n============\n\nint, float, complex\n" },
        .{ "STRINGS", "String Type\n==========\n\nStrings are immutable sequences of characters.\n" },
        .{ "LISTS", "List Type\n=========\n\nLists are mutable sequences.\n" },
        .{ "TUPLES", "Tuple Type\n=========\n\nTuples are immutable sequences.\n" },
        .{ "DICTS", "Dictionary Type\n==============\n\nDictionaries are mappings of keys to values.\n" },
        .{ "SETS", "Set Types\n=========\n\nSets are unordered collections of unique elements.\n" },
        .{ "FUNCTIONS", "Functions\n=========\n\nFunctions are defined using the def statement.\n" },
        .{ "CLASSES", "Classes\n=======\n\nClasses are defined using the class statement.\n" },
        .{ "MODULES", "Modules\n=======\n\nModules are files containing Python code.\n" },
        .{ "PACKAGES", "Packages\n========\n\nPackages are directories containing modules.\n" },
        .{ "EXCEPTIONS", "Exceptions\n==========\n\nExceptions are raised using the raise statement.\n" },
        .{ "FORMATTING", "String Formatting\n================\n\nPython supports multiple string formatting methods.\n" },
        .{ "OPERATORS", "Operators\n=========\n\nArithmetic, comparison, bitwise, and logical operators.\n" },
        .{ "EXPRESSIONS", "Expressions\n==========\n\nExpressions are combinations of values, variables, and operators.\n" },
        .{ "STATEMENTS", "Statements\n==========\n\nStatements are instructions that Python can execute.\n" },
        .{ "ASSIGNMENT", "Assignment\n==========\n\nAssignment binds names to values.\n" },
        .{ "DELETION", "Deletion\n========\n\nThe del statement removes references to objects.\n" },
        .{ "PRINTING", "Printing\n========\n\nThe print() function outputs text.\n" },
        .{ "IMPORTING", "Importing\n=========\n\nThe import statement loads modules.\n" },
        .{ "CONDITIONALS", "Conditionals\n============\n\nif, elif, else statements.\n" },
        .{ "LOOPING", "Looping\n=======\n\nfor and while loops.\n" },
        .{ "TRUTHVALUE", "Truth Value Testing\n==================\n\nAny object can be tested for truth value.\n" },
        .{ "ATTRIBUTES", "Attributes\n==========\n\nObjects have attributes accessed with dot notation.\n" },
        .{ "SUBSCRIPTS", "Subscripts\n==========\n\nSequences support indexing and slicing.\n" },
        .{ "SLICINGS", "Slicings\n========\n\nSlicing extracts portions of sequences.\n" },
        .{ "CALLS", "Calls\n=====\n\nFunctions are called with parentheses.\n" },
        .{ "POWER", "Power Operator\n=============\n\nThe ** operator raises to a power.\n" },
        .{ "UNARY", "Unary Operators\n==============\n\nUnary +, -, ~, not operators.\n" },
        .{ "BINARY", "Binary Operators\n===============\n\nBinary arithmetic and bitwise operators.\n" },
        .{ "SHIFTING", "Shift Operators\n==============\n\n<< and >> shift operations.\n" },
        .{ "BITWISE", "Bitwise Operators\n================\n\n&, |, ^ bitwise operations.\n" },
        .{ "CONTEXTMANAGERS", "Context Managers\n===============\n\nThe with statement.\n" },
        .{ "SPECIALATTRS", "Special Attributes\n=================\n\n__dict__, __class__, etc.\n" },
        .{ "SPECIALMETHODS", "Special Methods\n==============\n\n__init__, __str__, __repr__, etc.\n" },
    });

    /// Get help topic text
    pub fn get(topic: []const u8) ?[]const u8 {
        return data.get(topic);
    }

    /// Get all topic names
    pub fn keys(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = data.iterator();
        while (iter.next()) |entry| {
            try result.append(entry.key);
        }
        return result;
    }
};

// ============================================================================
// Keywords - Python keywords
// ============================================================================

pub const keywords = struct {
    pub const data = &[_][]const u8{
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

    /// Check if string is a keyword
    pub fn isKeyword(s: []const u8) bool {
        for (data) |kw| {
            if (std.mem.eql(u8, s, kw)) return true;
        }
        return false;
    }
};

// ============================================================================
// Symbols - Python symbols/operators
// ============================================================================

pub const symbols = struct {
    pub const data = std.StaticStringMap([]const u8).initComptime(.{
        .{ "+", "Addition or unary positive" },
        .{ "-", "Subtraction or unary negative" },
        .{ "*", "Multiplication or unpacking" },
        .{ "**", "Exponentiation or keyword unpacking" },
        .{ "/", "Division" },
        .{ "//", "Floor division" },
        .{ "%", "Modulo" },
        .{ "@", "Matrix multiplication or decorator" },
        .{ "<", "Less than" },
        .{ ">", "Greater than" },
        .{ "<=", "Less than or equal" },
        .{ ">=", "Greater than or equal" },
        .{ "==", "Equality" },
        .{ "!=", "Inequality" },
        .{ "&", "Bitwise AND" },
        .{ "|", "Bitwise OR" },
        .{ "^", "Bitwise XOR" },
        .{ "~", "Bitwise NOT" },
        .{ "<<", "Left shift" },
        .{ ">>", "Right shift" },
        .{ "=", "Assignment" },
        .{ "+=", "Add and assign" },
        .{ "-=", "Subtract and assign" },
        .{ "*=", "Multiply and assign" },
        .{ "/=", "Divide and assign" },
        .{ "//=", "Floor divide and assign" },
        .{ "%=", "Modulo and assign" },
        .{ "**=", "Power and assign" },
        .{ "&=", "Bitwise AND and assign" },
        .{ "|=", "Bitwise OR and assign" },
        .{ "^=", "Bitwise XOR and assign" },
        .{ "<<=", "Left shift and assign" },
        .{ ">>=", "Right shift and assign" },
        .{ ":", "Colon (slice, dict, suite)" },
        .{ ",", "Comma (separator)" },
        .{ ".", "Dot (attribute access)" },
        .{ "(", "Open parenthesis" },
        .{ ")", "Close parenthesis" },
        .{ "[", "Open bracket" },
        .{ "]", "Close bracket" },
        .{ "{", "Open brace" },
        .{ "}", "Close brace" },
        .{ "->", "Return type annotation" },
        .{ ":=", "Walrus operator (assignment expression)" },
    });

    /// Get symbol description
    pub fn get(symbol: []const u8) ?[]const u8 {
        return data.get(symbol);
    }
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

test "topics.get" {
    const result = topics.get("BOOLEAN");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "Boolean") != null);
}

test "topics.get unknown" {
    const result = topics.get("UNKNOWN_TOPIC");
    try std.testing.expect(result == null);
}

test "keywords.isKeyword" {
    try std.testing.expect(keywords.isKeyword("if"));
    try std.testing.expect(keywords.isKeyword("class"));
    try std.testing.expect(keywords.isKeyword("def"));
    try std.testing.expect(!keywords.isKeyword("foo"));
    try std.testing.expect(!keywords.isKeyword(""));
}

test "symbols.get" {
    const result = symbols.get("+");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "Addition") != null);
}

test "symbols.get walrus" {
    const result = symbols.get(":=");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "Walrus") != null);
}
