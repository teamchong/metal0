//! Core dataclass types and sentinels
//!
//! Provides fundamental types used throughout the dataclasses module:
//! - MISSING sentinel for detecting uninitialized values
//! - KW_ONLY marker for keyword-only fields
//! - DataclassOptions configuration

const std = @import("std");

/// Sentinel value to detect missing values
pub const MISSING = struct {
    pub fn isMissing(value: anytype) bool {
        return @TypeOf(value) == @TypeOf(MISSING);
    }
};

/// Sentinel to indicate a field should use default_factory
pub const KW_ONLY = struct {};

/// Options for dataclass decorator
pub const DataclassOptions = struct {
    init: bool = true,
    repr: bool = true,
    eq: bool = true,
    order: bool = false,
    unsafe_hash: bool = false,
    frozen: bool = false,
    match_args: bool = true,
    kw_only: bool = false,
    slots: bool = false,
    weakref_slot: bool = false,
};
