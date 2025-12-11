/// bltinmodule - Built-in Functions Module
/// Mirrors cpython/Python/bltinmodule.c
///
/// This module provides Python's built-in functions that are always available:
/// - Type conversion: int(), float(), str(), bool(), list(), dict(), etc.
/// - Math: abs(), pow(), round(), min(), max(), sum(), divmod()
/// - Iteration: iter(), next(), len(), range(), enumerate(), zip(), map(), filter()
/// - I/O: print(), input(), open()
/// - Object introspection: type(), isinstance(), issubclass(), hasattr(), getattr(), setattr()
/// - Execution: eval(), exec(), compile()
/// - Other: sorted(), reversed(), all(), any(), hash(), id(), repr(), ascii()
///
/// Most implementations delegate to runtime/builtins.zig for actual logic.

const std = @import("std");
const errors = @import("errors.zig");

// Re-export submodules
pub const conversions = @import("bltinmodule/conversions.zig");
pub const math = @import("bltinmodule/math.zig");
pub const sequences = @import("bltinmodule/sequences.zig");
pub const introspection = @import("bltinmodule/introspection.zig");
pub const io = @import("bltinmodule/io.zig");
pub const format = @import("bltinmodule/format.zig");
pub const objects = @import("bltinmodule/objects.zig");

// Re-export type conversion functions
pub const int_builtin = conversions.int_builtin;
pub const int_with_base = conversions.int_with_base;
pub const float_builtin = conversions.float_builtin;
pub const str_builtin = conversions.str_builtin;
pub const bool_builtin = conversions.bool_builtin;
pub const bin_builtin = conversions.bin_builtin;
pub const hex_builtin = conversions.hex_builtin;
pub const oct_builtin = conversions.oct_builtin;
pub const ord_builtin = conversions.ord_builtin;
pub const chr_builtin = conversions.chr_builtin;

// Re-export math functions
pub const abs_builtin = math.abs_builtin;
pub const pow_builtin = math.pow_builtin;
pub const round_builtin = math.round_builtin;
pub const divmod_builtin = math.divmod_builtin;
pub const min_builtin = math.min_builtin;
pub const max_builtin = math.max_builtin;
pub const sum_builtin = math.sum_builtin;

// Re-export sequence functions
pub const len_builtin = sequences.len_builtin;
pub const all_builtin = sequences.all_builtin;
pub const any_builtin = sequences.any_builtin;
pub const sorted_builtin = sequences.sorted_builtin;

// Re-export introspection functions
pub const type_builtin = introspection.type_builtin;
pub const hash_builtin = introspection.hash_builtin;
pub const id_builtin = introspection.id_builtin;
pub const repr_builtin = introspection.repr_builtin;
pub const ascii_builtin = introspection.ascii_builtin;
pub const callable_builtin = introspection.callable_builtin;

// Re-export I/O functions
pub const print_builtin = io.print_builtin;
pub const input_builtin = io.input_builtin;

// Re-export format function
pub const format_builtin = format.format_builtin;

// Re-export object protocol functions
pub const getattr_builtin = objects.getattr_builtin;
pub const setattr_builtin = objects.setattr_builtin;
pub const delattr_builtin = objects.delattr_builtin;
pub const hasattr_builtin = objects.hasattr_builtin;
pub const locals_builtin = objects.locals_builtin;
pub const globals_builtin = objects.globals_builtin;
pub const vars_builtin = objects.vars_builtin;
pub const __build_class__ = objects.__build_class__;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the builtins module
pub fn init() void {
    // Builtins are statically available, no initialization needed
}

// ============================================================================
// Tests
// ============================================================================

test {
    _ = conversions;
    _ = math;
    _ = sequences;
    _ = introspection;
    _ = io;
    _ = format;
    _ = objects;
}
