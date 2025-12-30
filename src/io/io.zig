//! I/O abstraction layer for LanceQL.
//!
//! This module provides a VFS (Virtual File System) abstraction that allows
//! the same Lance parsing code to work with:
//! - Native file system (FileReader)
//! - In-memory buffers (MemoryReader)
//! - HTTP Range requests (HttpReader)

const std = @import("std");

pub const reader = @import("reader.zig");
pub const file_reader = @import("file_reader.zig");
pub const memory_reader = @import("memory_reader.zig");
pub const http_reader = @import("http_reader.zig");

// Re-export main types
pub const Reader = reader.Reader;
pub const ReadError = reader.ReadError;
pub const FileReader = file_reader.FileReader;
pub const MemoryReader = memory_reader.MemoryReader;
pub const HttpReader = http_reader.HttpReader;

test {
    std.testing.refAllDecls(@This());
}
