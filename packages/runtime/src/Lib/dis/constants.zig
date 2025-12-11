//! Constants for bytecode disassembly.
//!
//! This module defines constants used in Python bytecode format.

/// Opcodes >= this value have an argument
pub const HAVE_ARGUMENT = 90;

/// Shift amount for extended argument
pub const EXTENDED_ARG_SHIFT = 8;
