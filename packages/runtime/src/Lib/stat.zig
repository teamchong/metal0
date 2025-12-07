//! Python 'stat' module - Interpret stat() results
//!
//! Provides constants and functions for interpreting os.stat() results.
//!
//! Mirrors: CPython Lib/stat.py

const std = @import("std");

// ============================================================================
// File Mode Bits (st_mode)
// ============================================================================

/// Bit mask for file type
pub const S_IFMT: u32 = 0o170000;

/// Socket
pub const S_IFSOCK: u32 = 0o140000;
/// Symbolic link
pub const S_IFLNK: u32 = 0o120000;
/// Regular file
pub const S_IFREG: u32 = 0o100000;
/// Block device
pub const S_IFBLK: u32 = 0o060000;
/// Directory
pub const S_IFDIR: u32 = 0o040000;
/// Character device
pub const S_IFCHR: u32 = 0o020000;
/// FIFO (named pipe)
pub const S_IFIFO: u32 = 0o010000;

// ============================================================================
// Permission Bits
// ============================================================================

/// Set user ID on execution
pub const S_ISUID: u32 = 0o4000;
/// Set group ID on execution
pub const S_ISGID: u32 = 0o2000;
/// Sticky bit
pub const S_ISVTX: u32 = 0o1000;

/// Owner read permission
pub const S_IRUSR: u32 = 0o0400;
/// Owner write permission
pub const S_IWUSR: u32 = 0o0200;
/// Owner execute permission
pub const S_IXUSR: u32 = 0o0100;
/// Owner permissions mask
pub const S_IRWXU: u32 = 0o0700;

/// Group read permission
pub const S_IRGRP: u32 = 0o0040;
/// Group write permission
pub const S_IWGRP: u32 = 0o0020;
/// Group execute permission
pub const S_IXGRP: u32 = 0o0010;
/// Group permissions mask
pub const S_IRWXG: u32 = 0o0070;

/// Others read permission
pub const S_IROTH: u32 = 0o0004;
/// Others write permission
pub const S_IWOTH: u32 = 0o0002;
/// Others execute permission
pub const S_IXOTH: u32 = 0o0001;
/// Others permissions mask
pub const S_IRWXO: u32 = 0o0007;

// ============================================================================
// File Type Tests
// ============================================================================

/// Return the file type portion of the mode
pub fn S_IFMODE(mode: u32) u32 {
    return mode & S_IFMT;
}

/// Is it a directory?
pub fn S_ISDIR(mode: u32) bool {
    return S_IFMODE(mode) == S_IFDIR;
}

/// Is it a regular file?
pub fn S_ISREG(mode: u32) bool {
    return S_IFMODE(mode) == S_IFREG;
}

/// Is it a symbolic link?
pub fn S_ISLNK(mode: u32) bool {
    return S_IFMODE(mode) == S_IFLNK;
}

/// Is it a character device?
pub fn S_ISCHR(mode: u32) bool {
    return S_IFMODE(mode) == S_IFCHR;
}

/// Is it a block device?
pub fn S_ISBLK(mode: u32) bool {
    return S_IFMODE(mode) == S_IFBLK;
}

/// Is it a FIFO (named pipe)?
pub fn S_ISFIFO(mode: u32) bool {
    return S_IFMODE(mode) == S_IFIFO;
}

/// Is it a socket?
pub fn S_ISSOCK(mode: u32) bool {
    return S_IFMODE(mode) == S_IFSOCK;
}

// ============================================================================
// Stat Result Field Indices
// ============================================================================

/// Index of st_mode in stat tuple
pub const ST_MODE: usize = 0;
/// Index of st_ino in stat tuple
pub const ST_INO: usize = 1;
/// Index of st_dev in stat tuple
pub const ST_DEV: usize = 2;
/// Index of st_nlink in stat tuple
pub const ST_NLINK: usize = 3;
/// Index of st_uid in stat tuple
pub const ST_UID: usize = 4;
/// Index of st_gid in stat tuple
pub const ST_GID: usize = 5;
/// Index of st_size in stat tuple
pub const ST_SIZE: usize = 6;
/// Index of st_atime in stat tuple
pub const ST_ATIME: usize = 7;
/// Index of st_mtime in stat tuple
pub const ST_MTIME: usize = 8;
/// Index of st_ctime in stat tuple
pub const ST_CTIME: usize = 9;

// ============================================================================
// File Attribute Constants (Windows)
// ============================================================================

/// Read-only file
pub const FILE_ATTRIBUTE_READONLY: u32 = 0x1;
/// Hidden file
pub const FILE_ATTRIBUTE_HIDDEN: u32 = 0x2;
/// System file
pub const FILE_ATTRIBUTE_SYSTEM: u32 = 0x4;
/// Directory
pub const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
/// Archive file
pub const FILE_ATTRIBUTE_ARCHIVE: u32 = 0x20;
/// Normal file
pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
/// Temporary file
pub const FILE_ATTRIBUTE_TEMPORARY: u32 = 0x100;
/// Sparse file
pub const FILE_ATTRIBUTE_SPARSE_FILE: u32 = 0x200;
/// Reparse point
pub const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
/// Compressed file
pub const FILE_ATTRIBUTE_COMPRESSED: u32 = 0x800;
/// Encrypted file
pub const FILE_ATTRIBUTE_ENCRYPTED: u32 = 0x4000;

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert a file mode to a string (like ls -l)
pub fn filemode(mode: u32) [10]u8 {
    var result: [10]u8 = undefined;

    // File type
    result[0] = switch (S_IFMODE(mode)) {
        S_IFDIR => 'd',
        S_IFLNK => 'l',
        S_IFBLK => 'b',
        S_IFCHR => 'c',
        S_IFIFO => 'p',
        S_IFSOCK => 's',
        else => '-',
    };

    // Owner permissions
    result[1] = if (mode & S_IRUSR != 0) 'r' else '-';
    result[2] = if (mode & S_IWUSR != 0) 'w' else '-';
    result[3] = if (mode & S_IXUSR != 0)
        (if (mode & S_ISUID != 0) 's' else 'x')
    else
        (if (mode & S_ISUID != 0) 'S' else '-');

    // Group permissions
    result[4] = if (mode & S_IRGRP != 0) 'r' else '-';
    result[5] = if (mode & S_IWGRP != 0) 'w' else '-';
    result[6] = if (mode & S_IXGRP != 0)
        (if (mode & S_ISGID != 0) 's' else 'x')
    else
        (if (mode & S_ISGID != 0) 'S' else '-');

    // Others permissions
    result[7] = if (mode & S_IROTH != 0) 'r' else '-';
    result[8] = if (mode & S_IWOTH != 0) 'w' else '-';
    result[9] = if (mode & S_IXOTH != 0)
        (if (mode & S_ISVTX != 0) 't' else 'x')
    else
        (if (mode & S_ISVTX != 0) 'T' else '-');

    return result;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the stat module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "S_IFMT constants" {
    try std.testing.expectEqual(@as(u32, 0o170000), S_IFMT);
    try std.testing.expectEqual(@as(u32, 0o040000), S_IFDIR);
    try std.testing.expectEqual(@as(u32, 0o100000), S_IFREG);
    try std.testing.expectEqual(@as(u32, 0o120000), S_IFLNK);
}

test "permission constants" {
    try std.testing.expectEqual(@as(u32, 0o0700), S_IRWXU);
    try std.testing.expectEqual(@as(u32, 0o0070), S_IRWXG);
    try std.testing.expectEqual(@as(u32, 0o0007), S_IRWXO);
}

test "S_ISDIR" {
    try std.testing.expect(S_ISDIR(0o040755));
    try std.testing.expect(!S_ISDIR(0o100644));
}

test "S_ISREG" {
    try std.testing.expect(S_ISREG(0o100644));
    try std.testing.expect(!S_ISREG(0o040755));
}

test "S_ISLNK" {
    try std.testing.expect(S_ISLNK(0o120777));
    try std.testing.expect(!S_ISLNK(0o100644));
}

test "S_ISFIFO" {
    try std.testing.expect(S_ISFIFO(0o010644));
    try std.testing.expect(!S_ISFIFO(0o100644));
}

test "S_ISSOCK" {
    try std.testing.expect(S_ISSOCK(0o140755));
    try std.testing.expect(!S_ISSOCK(0o100644));
}

test "filemode regular file" {
    const mode = filemode(0o100644);
    try std.testing.expectEqualStrings("-rw-r--r--", &mode);
}

test "filemode directory" {
    const mode = filemode(0o040755);
    try std.testing.expectEqualStrings("drwxr-xr-x", &mode);
}

test "filemode symbolic link" {
    const mode = filemode(0o120777);
    try std.testing.expectEqualStrings("lrwxrwxrwx", &mode);
}

test "filemode with setuid" {
    const mode = filemode(0o104755);
    try std.testing.expectEqualStrings("-rwsr-xr-x", &mode);
}

test "filemode with sticky bit" {
    const mode = filemode(0o041777);
    try std.testing.expectEqualStrings("drwxrwxrwt", &mode);
}

test "stat result indices" {
    try std.testing.expectEqual(@as(usize, 0), ST_MODE);
    try std.testing.expectEqual(@as(usize, 6), ST_SIZE);
    try std.testing.expectEqual(@as(usize, 8), ST_MTIME);
}
