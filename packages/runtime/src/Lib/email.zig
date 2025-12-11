//! Python 'email' module - Email handling package
//!
//! Provides email message parsing, generation, and MIME handling.
//!
//! Mirrors: CPython Lib/email/
//!
//! This is the main entry point that re-exports all email submodules.

const std = @import("std");

// Re-export all submodules
pub const message = @import("email/message.zig");
pub const parser = @import("email/parser.zig");
pub const mime = @import("email/mime.zig");
pub const header = @import("email/header.zig");
pub const utils = @import("email/utils.zig");
pub const policy = @import("email/policy.zig");
pub const encoders = @import("email/encoders.zig");
pub const generator = @import("email/generator.zig");

// Re-export commonly used types at the top level
pub const Message = message.Message;
pub const MessageIterator = message.MessageIterator;
pub const createTextMessage = message.createTextMessage;

// Parser types
pub const Parser = parser.Parser;
pub const BytesParser = parser.BytesParser;
pub const HeaderParser = parser.HeaderParser;
pub const FeedParser = parser.FeedParser;
pub const parseMessage = parser.parseMessage;

// MIME types
pub const MIMEText = mime.MIMEText;
pub const MIMEMultipart = mime.MIMEMultipart;
pub const MIMEBase = mime.MIMEBase;
pub const MIMEApplication = mime.MIMEApplication;
pub const MIMEImage = mime.MIMEImage;
pub const MIMEAudio = mime.MIMEAudio;

// Header functions
pub const decodeHeader = header.decodeHeader;
pub const makeHeader = header.makeHeader;
pub const decode_header = header.decode_header;
pub const make_header = header.make_header;
pub const Header = header.Header;

// Utility functions
pub const parseaddr = utils.parseaddr;
pub const formataddr = utils.formataddr;
pub const getaddresses = utils.getaddresses;
pub const formatdate = utils.formatdate;
pub const parsedate = utils.parsedate;
pub const parsedate_to_datetime = utils.parsedate_to_datetime;
pub const makeMessageId = utils.makeMessageId;
pub const make_msgid = utils.make_msgid;
pub const quoteString = utils.quoteString;

// Policy types
pub const Policy = policy.Policy;
pub const EmailPolicy = policy.EmailPolicy;

// Encoder functions
pub const encodeBase64 = encoders.encodeBase64;
pub const encodeQuopri = encoders.encodeQuopri;
pub const encode7bit = encoders.encode7bit;
pub const encode8bit = encoders.encode8bit;
pub const encode_base64 = encoders.encode_base64;
pub const encode_quopri = encoders.encode_quopri;
pub const encode_7bit = encoders.encode_7bit;
pub const encode_8bit = encoders.encode_8bit;

// Generator types
pub const Generator = generator.Generator;
pub const BytesGenerator = generator.BytesGenerator;

// ============================================================================
// Tests (moved from original file)
// ============================================================================

test "Message basic" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Subject", "Test");
    try msg.set("From", "sender@example.com");

    try std.testing.expectEqualStrings("Test", msg.get("Subject").?);
    try std.testing.expectEqualStrings("sender@example.com", msg.get("From").?);
}

test "Message headers case insensitive" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Content-Type", "text/plain");
    try std.testing.expectEqualStrings("text/plain", msg.get("content-type").?);
    try std.testing.expectEqualStrings("text/plain", msg.get("CONTENT-TYPE").?);
}

test "Message content type" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Content-Type", "text/html; charset=\"utf-8\"");

    try std.testing.expectEqualStrings("text/html", msg.getContentType());
    try std.testing.expectEqualStrings("text", msg.getContentMainType());
    try std.testing.expectEqualStrings("html", msg.getContentSubtype());
    try std.testing.expectEqualStrings("utf-8", msg.getCharset().?);
}

test "parseaddr" {
    const result1 = parseaddr("John Doe <john@example.com>");
    try std.testing.expectEqualStrings("John Doe", result1.name);
    try std.testing.expectEqualStrings("john@example.com", result1.email);

    const result2 = parseaddr("simple@example.com");
    try std.testing.expectEqualStrings("", result2.name);
    try std.testing.expectEqualStrings("simple@example.com", result2.email);
}

test "formataddr" {
    const allocator = std.testing.allocator;

    const result1 = try formataddr(allocator, "John Doe", "john@example.com");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("John Doe <john@example.com>", result1);

    const result2 = try formataddr(allocator, "", "simple@example.com");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("simple@example.com", result2);
}

test "parser basic" {
    const allocator = std.testing.allocator;

    const email_text =
        \\Subject: Test Email
        \\From: sender@example.com
        \\To: recipient@example.com
        \\
        \\This is the body.
    ;

    const msg = try parseMessage(allocator, email_text);
    defer {
        msg.deinit();
        allocator.destroy(msg);
    }

    try std.testing.expectEqualStrings("Test Email", msg.get("Subject").?);
    try std.testing.expectEqualStrings("sender@example.com", msg.get("From").?);
    try std.testing.expectEqualStrings("This is the body.", msg.getPayload().?);
}

test "MIMEText" {
    const allocator = std.testing.allocator;

    var mime_text = try MIMEText.init(allocator, "Hello, world!", "plain", "utf-8");
    defer mime_text.deinit();

    try std.testing.expectEqualStrings("text/plain", mime_text.message.getContentMainType() ++ "/" ++ mime_text.message.getContentSubtype());
}

test "encode base64" {
    const allocator = std.testing.allocator;

    const encoded = try encodeBase64(allocator, "Hello");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("SGVsbG8=", encoded);
}

test "quote string" {
    const allocator = std.testing.allocator;

    const quoted = try quoteString(allocator, "test \"value\"");
    defer allocator.free(quoted);

    try std.testing.expectEqualStrings("\"test \\\"value\\\"\"", quoted);
}
