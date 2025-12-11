//! Core types for difflib module
//!
//! Provides Match and Opcode types used throughout difflib

const std = @import("std");

// ============================================================================
// Match
// ============================================================================

/// Represents a matching block between two sequences
pub const Match = struct {
    a: usize, // Start index in sequence a
    b: usize, // Start index in sequence b
    size: usize, // Size of the match
};

// ============================================================================
// Opcode
// ============================================================================

/// Operation code describing a difference between sequences
pub const Opcode = struct {
    tag: Tag,
    i1: usize, // Start index in sequence a
    i2: usize, // End index in sequence a
    j1: usize, // Start index in sequence b
    j2: usize, // End index in sequence b

    pub const Tag = enum {
        replace, // Replace a[i1:i2] with b[j1:j2]
        delete, // Delete a[i1:i2]
        insert, // Insert b[j1:j2]
        equal, // a[i1:i2] == b[j1:j2]
    };
};
