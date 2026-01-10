//! _pyrepl.curses - Curses wrapper for pyrepl
//! Reference: cpython/Lib/_pyrepl/curses.py
//!
//! This module re-exports curses functionality for the REPL.
//! It tries _curses first, falls back to _minimal_curses.

const std = @import("std");
const _minimal_curses = @import("_minimal_curses.zig");

// Re-export from _minimal_curses
pub const setupterm = _minimal_curses.setupterm;
pub const tigetstr = _minimal_curses.tigetstr;
pub const tparm = _minimal_curses.tparm;
pub const CursesError = _minimal_curses.CursesError;

// Alias for compatibility
pub const error_ = CursesError;

pub const OK = _minimal_curses.OK;
pub const ERR = _minimal_curses.ERR;

// ============================================================================
// Tests
// ============================================================================

test "curses re-exports" {
    try std.testing.expect(tigetstr("clear") != null);
}
