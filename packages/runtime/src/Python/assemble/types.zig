/// Types - Assembler Output Types
/// Mirrors cpython/Python/assemble.c - output data structures

const std = @import("std");

/// Assembled bytecode output
pub const AssembledCode = struct {
    bytecode: []const u8,
    linetable: []const u8,
    exception_table: []const ExceptionEntry,
    constants: []const Constant,
    names: []const []const u8,
    stack_size: i32,
    num_locals: u32,
};

/// Exception table entry
pub const ExceptionEntry = struct {
    start: u32,
    end: u32,
    target: u32,
    depth: u16,
    lasti: bool,
};

/// Constant pool entry
pub const Constant = union(enum) {
    none: void,
    ellipsis: void,
    boolean: bool,
    integer: i64,
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,
    tuple: []const Constant,
    frozenset: []const Constant,
    code: *const anyopaque, // Code object reference

    pub fn eql(self: Constant, other: Constant) bool {
        return switch (self) {
            .none => other == .none,
            .ellipsis => other == .ellipsis,
            .boolean => |b| other == .boolean and other.boolean == b,
            .integer => |i| other == .integer and other.integer == i,
            .float => |f| other == .float and other.float == f,
            .string => |s| other == .string and std.mem.eql(u8, other.string, s),
            .bytes => |b| other == .bytes and std.mem.eql(u8, other.bytes, b),
            else => false,
        };
    }
};
