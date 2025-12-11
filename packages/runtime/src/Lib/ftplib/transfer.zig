//! FTP file transfer operations
//!
//! Contains file transfer functionality:
//! - Binary transfer (retrbinary, storbinary)
//! - Text transfer (retrlines, storlines)
//! - Transfer callbacks

const std = @import("std");
const client = @import("client.zig");

pub const FTP = client.FTP;
pub const FtpResponse = client.FtpResponse;

// ============================================================================
// File Transfer Operations
// ============================================================================

/// Retrieve a file in binary mode
pub fn retrbinary(
    ftp: *FTP,
    cmd: []const u8,
    callback: *const fn ([]const u8) void,
    blocksize: ?usize,
    rest: ?u64,
) !FtpResponse {
    // Set transfer position if specified
    if (rest) |r| {
        _ = try ftp.sendCmd("REST", std.fmt.allocPrint(ftp.allocator, "{d}", .{r}) catch "0");
    }

    // Send RETR command
    const resp = try ftp.sendCmd("RETR", cmd);
    if (resp.code < 100 or resp.code >= 300) {
        return resp;
    }

    // Open data connection and receive data
    const block = blocksize orelse 8192;
    var buf: [8192]u8 = undefined;
    const read_buf = buf[0..@min(block, buf.len)];

    if (ftp.sock) |sock| {
        while (true) {
            const n = std.posix.recv(sock, read_buf, 0) catch break;
            if (n == 0) break;
            callback(read_buf[0..n]);
        }
    }

    return resp;
}

/// Retrieve file as lines
pub fn retrlines(
    ftp: *FTP,
    cmd: []const u8,
    callback: ?*const fn ([]const u8) void,
) !FtpResponse {
    // Send RETR command
    const resp = try ftp.sendCmd("RETR", cmd);
    if (resp.code < 100 or resp.code >= 300) {
        return resp;
    }

    // Read lines from data connection
    if (ftp.sock) |sock| {
        var line_buf = std.ArrayList(u8).init(ftp.allocator);
        defer line_buf.deinit();
        var buf: [1]u8 = undefined;

        while (true) {
            const n = std.posix.recv(sock, &buf, 0) catch break;
            if (n == 0) break;

            if (buf[0] == '\n') {
                if (callback) |cb| {
                    cb(line_buf.items);
                }
                line_buf.clearRetainingCapacity();
            } else if (buf[0] != '\r') {
                line_buf.append(buf[0]) catch break;
            }
        }

        // Handle last line without newline
        if (line_buf.items.len > 0) {
            if (callback) |cb| {
                cb(line_buf.items);
            }
        }
    }

    return resp;
}

/// Store a file (binary)
pub fn storbinary(
    ftp: *FTP,
    cmd: []const u8,
    fp: anytype,
    blocksize: ?usize,
    callback: ?*const fn ([]const u8) void,
    rest: ?u64,
) !FtpResponse {
    // Set transfer position if specified
    if (rest) |r| {
        _ = try ftp.sendCmd("REST", std.fmt.allocPrint(ftp.allocator, "{d}", .{r}) catch "0");
    }

    // Send STOR command
    const resp = try ftp.sendCmd("STOR", cmd);
    if (resp.code < 100 or resp.code >= 300) {
        return resp;
    }

    // Send data from file
    const block = blocksize orelse 8192;
    var buf: [8192]u8 = undefined;
    const write_buf = buf[0..@min(block, buf.len)];

    if (ftp.sock) |sock| {
        while (true) {
            const n = fp.read(write_buf) catch break;
            if (n == 0) break;

            _ = std.posix.send(sock, write_buf[0..n], 0) catch break;

            if (callback) |cb| {
                cb(write_buf[0..n]);
            }
        }
    }

    return resp;
}

/// Store a file (lines)
pub fn storlines(
    ftp: *FTP,
    cmd: []const u8,
    fp: anytype,
    callback: ?*const fn ([]const u8) void,
) !FtpResponse {
    // Send STOR command
    const resp = try ftp.sendCmd("STOR", cmd);
    if (resp.code < 100 or resp.code >= 300) {
        return resp;
    }

    // Send lines from file
    var line_buf: [4096]u8 = undefined;

    if (ftp.sock) |sock| {
        while (true) {
            const line = fp.readUntilDelimiter(&line_buf, '\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            // Send line with CRLF
            _ = std.posix.send(sock, line, 0) catch break;
            _ = std.posix.send(sock, "\r\n", 0) catch break;

            if (callback) |cb| {
                cb(line);
            }
        }
    }

    return resp;
}
