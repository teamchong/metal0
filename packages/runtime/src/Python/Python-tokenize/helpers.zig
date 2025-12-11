/// Helper Functions
/// Character classification and utility functions for tokenization

const std = @import("std");

pub fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

pub fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn isStringPrefix(c: u8) bool {
    return c == 'r' or c == 'R' or c == 'b' or c == 'B' or c == 'f' or c == 'F' or c == 'u' or c == 'U';
}
