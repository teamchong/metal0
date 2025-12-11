/// marshal/types - Type codes, constants, and value types
/// Mirrors cpython/Python/marshal.c type definitions

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Marshal format version
pub const VERSION: u8 = 5;

/// Maximum marshal stack depth to prevent overflow
pub const MAX_MARSHAL_STACK_DEPTH: u32 = 2000;

// ============================================================================
// Type Codes
// ============================================================================

/// Marshal type codes
pub const Type = enum(u8) {
    // Core types
    null_ = '0',
    none = 'N',
    false_ = 'F',
    true_ = 'T',
    stopiter = 'S',
    ellipsis = '.',

    // Numbers
    binary_float = 'g',
    binary_complex = 'y',
    long_ = 'l',
    int_ = 'i',
    int64 = 'I', // Legacy

    // Strings
    string = 's', // Bytes
    unicode = 'u',
    interned = 't',
    ascii = 'a',
    ascii_interned = 'A',
    short_ascii = 'z',
    short_ascii_interned = 'Z',

    // Containers
    tuple = '(',
    small_tuple = ')',
    list = '[',
    dict = '{',
    set = '<',
    frozenset = '>',

    // Code and special
    code = 'c',
    slice = ':',
    unknown = '?',

    // References (version 3+)
    ref = 'r',

    // Legacy types
    complex = 'x', // Version 0
    float_ = 'f', // Version 0

    /// Check if type has FLAG_REF set
    pub fn hasRef(byte: u8) bool {
        return (byte & FLAG_REF) != 0;
    }

    /// Get type without FLAG_REF
    pub fn withoutRef(byte: u8) u8 {
        return byte & ~FLAG_REF;
    }
};

/// Reference flag (added in version 3)
pub const FLAG_REF: u8 = 0x80;

// ============================================================================
// Error Codes
// ============================================================================

pub const WriteError = error{
    Ok,
    Unmarshallable,
    NestedTooDeep,
    NoMemory,
    CodeNotAllowed,
};

pub const ReadError = error{
    Eof,
    InvalidType,
    InvalidData,
    NestedTooDeep,
    InvalidReference,
    NoMemory,
};

// ============================================================================
// Marshalled Value (Type-Erased)
// ============================================================================

/// Represents a marshalled value
pub const Value = union(enum) {
    none,
    false_,
    true_,
    stopiter,
    ellipsis,
    int_: i64,
    float_: f64,
    complex_: struct { real: f64, imag: f64 },
    bytes: []const u8,
    string: []const u8,
    tuple: []Value,
    list: []Value,
    dict: []struct { key: Value, value: Value },
    set: []Value,
    frozenset: []Value,
    code: *const CodeValue,
    ref: u32,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tuple => |t| allocator.free(t),
            .list => |l| allocator.free(l),
            .dict => |d| allocator.free(d),
            .set => |s| allocator.free(s),
            .frozenset => |f| allocator.free(f),
            else => {},
        }
    }
};

/// Code object value
pub const CodeValue = struct {
    argcount: i32,
    posonlyargcount: i32,
    kwonlyargcount: i32,
    nlocals: i32,
    stacksize: i32,
    flags: i32,
    code: []const u8,
    consts: []Value,
    names: [][]const u8,
    varnames: [][]const u8,
    freevars: [][]const u8,
    cellvars: [][]const u8,
    filename: []const u8,
    name: []const u8,
    qualname: []const u8,
    firstlineno: i32,
    linetable: []const u8,
    exceptiontable: []const u8,
};
