//! FTP command implementations
//!
//! Contains FTP protocol commands:
//! - Directory operations (cwd, pwd, cdup, mkd, rmd)
//! - File operations (delete, rename, size)
//! - Transfer mode (setType, setAscii, setBinary)
//! - Directory listing (dir, nlst, mlsd)
//! - Connection management (noop, quit)

const std = @import("std");
const client = @import("client.zig");

pub const FTP = client.FTP;
pub const FtpResponse = client.FtpResponse;
pub const FtpError = client.FtpError;

// ============================================================================
// FTP Commands
// ============================================================================

/// Change to parent directory
pub fn cdup(ftp: *FTP) !FtpResponse {
    return ftp.sendCmd("CDUP", null);
}

/// Print working directory
pub fn pwd(ftp: *FTP) ![]const u8 {
    const resp = try ftp.sendCmd("PWD", null);
    // Parse directory from response
    return resp.message;
}

/// Change working directory
pub fn cwd(ftp: *FTP, dirname: []const u8) !FtpResponse {
    if (std.mem.eql(u8, dirname, "..")) {
        return cdup(ftp);
    }
    return ftp.sendCmd("CWD", dirname);
}

/// Get file size
pub fn size(ftp: *FTP, filename: []const u8) !?u64 {
    const resp = try ftp.sendCmd("SIZE", filename);
    if (resp.code == 213) {
        return std.fmt.parseInt(u64, resp.message, 10) catch null;
    }
    return null;
}

/// Make a directory
pub fn mkd(ftp: *FTP, dirname: []const u8) ![]const u8 {
    const resp = try ftp.sendCmd("MKD", dirname);
    return resp.message;
}

/// Remove a directory
pub fn rmd(ftp: *FTP, dirname: []const u8) !FtpResponse {
    return ftp.sendCmd("RMD", dirname);
}

/// Delete a file
pub fn delete(ftp: *FTP, filename: []const u8) !FtpResponse {
    const resp = try ftp.sendCmd("DELE", filename);
    if (resp.code >= 500) {
        return FtpError.PermError;
    }
    return resp;
}

/// Rename a file
pub fn rename(ftp: *FTP, fromname: []const u8, toname: []const u8) !FtpResponse {
    const resp = try ftp.sendCmd("RNFR", fromname);
    if (resp.code != 350) {
        return FtpError.ReplyError;
    }
    return ftp.sendCmd("RNTO", toname);
}

/// Set transfer type (ASCII or binary)
pub fn setType(ftp: *FTP, typecode: []const u8) !FtpResponse {
    return ftp.sendCmd("TYPE", typecode);
}

/// Set ASCII transfer mode
pub fn setAscii(ftp: *FTP) !FtpResponse {
    return setType(ftp, "A");
}

/// Set binary transfer mode
pub fn setBinary(ftp: *FTP) !FtpResponse {
    return setType(ftp, "I");
}

/// List directory contents
pub fn dir(ftp: *FTP, dirname: ?[]const u8) ![]const u8 {
    return try nlst(ftp, dirname);
}

/// Name list of directory
pub fn nlst(ftp: *FTP, dirname: ?[]const u8) ![]const u8 {
    const resp = try ftp.sendCmd("NLST", dirname);
    return resp.message;
}

/// Long directory listing
pub fn mlsd(ftp: *FTP, path: ?[]const u8) ![]const u8 {
    const resp = try ftp.sendCmd("MLSD", path);
    return resp.message;
}

/// Send NOOP to keep connection alive
pub fn noop(ftp: *FTP) !FtpResponse {
    return ftp.sendCmd("NOOP", null);
}

/// Quit and close connection
pub fn quit(ftp: *FTP) !FtpResponse {
    const resp = try ftp.sendCmd("QUIT", null);
    ftp.close();
    return resp;
}
