//! CPython source: Lib/bdb.py
//!
//! Provides a base class for building debuggers.
//!
//! Mirrors: CPython Lib/bdb.py
//!
//! This module is organized into focused submodules:
//! - types: Core types (BpType, StopReason, FrameInfo, CompareOp)
//! - breakpoint: Breakpoint class and condition evaluation
//! - bdb_class: Bdb main debugger class
//! - helpers: Utility functions (shouldTrace, canonic, effectiveSkip)

// Re-export all public types and functions
pub const types = @import("bdb/types.zig");
pub const breakpoint_mod = @import("bdb/breakpoint.zig");
pub const bdb_class = @import("bdb/bdb_class.zig");
pub const helpers = @import("bdb/helpers.zig");

// Re-export commonly used types at top level for convenience
pub const BpType = types.BpType;
pub const StopReason = types.StopReason;
pub const FrameInfo = types.FrameInfo;
pub const CompareOp = types.CompareOp;

pub const Breakpoint = breakpoint_mod.Breakpoint;
pub const checkfuncname = breakpoint_mod.checkfuncname;

pub const Bdb = bdb_class.Bdb;

pub const shouldTrace = helpers.shouldTrace;
pub const canonic = helpers.canonic;
pub const effectiveSkip = helpers.effectiveSkip;
