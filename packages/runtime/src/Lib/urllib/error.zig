//! Python 'urllib.error' module - Exception classes
//!
//! Provides URL-related exception types.
//!
//! Mirrors: CPython Lib/urllib/error.py

const std = @import("std");

/// URL-related errors
pub const Error = error{
    URLError,
    HTTPError,
    ContentTooShort,
    NotImplemented,
};
