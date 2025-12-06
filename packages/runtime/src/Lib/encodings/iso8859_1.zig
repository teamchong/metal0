//! Python 'iso8859-1' Codec (Latin-1)
//!
//! ISO-8859-1 is identical to Latin-1. This module is an alias.
//!
//! Mirrors: CPython Lib/encodings/iso8859_1.py

const latin_1 = @import("latin_1.zig");

pub const name = "iso8859-1";
pub const aliases = [_][]const u8{ "iso-8859-1", "iso_8859_1", "8859", "latin1" };

// Re-export everything from latin_1
pub const ErrorHandler = latin_1.ErrorHandler;
pub const DecodeResult = latin_1.DecodeResult;
pub const EncodeResult = latin_1.EncodeResult;
pub const decode = latin_1.decode;
pub const encode = latin_1.encode;
