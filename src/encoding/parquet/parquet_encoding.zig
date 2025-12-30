//! Parquet encoding module.
//!
//! Re-exports all Parquet encoding types.

pub const plain = @import("plain.zig");
pub const rle = @import("rle.zig");
pub const dictionary = @import("dictionary.zig");
pub const page = @import("page.zig");
pub const snappy = @import("snappy.zig");

pub const PlainDecoder = plain.PlainDecoder;
pub const PlainError = plain.PlainError;

pub const RleDecoder = rle.RleDecoder;
pub const RleError = rle.RleError;
pub const decodeLevels = rle.decodeLevels;

pub const Int32Dictionary = dictionary.Int32Dictionary;
pub const Int64Dictionary = dictionary.Int64Dictionary;
pub const FloatDictionary = dictionary.FloatDictionary;
pub const DoubleDictionary = dictionary.DoubleDictionary;
pub const ByteArrayDictionary = dictionary.ByteArrayDictionary;
pub const DictionaryError = dictionary.DictionaryError;
pub const decodeIndices = dictionary.decodeIndices;

pub const PageReader = page.PageReader;
pub const PageError = page.PageError;
pub const DecodedPage = page.DecodedPage;

pub const decompress = snappy.decompress;
pub const SnappyError = snappy.SnappyError;
