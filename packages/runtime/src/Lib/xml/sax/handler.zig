//! xml.sax.handler - SAX handler classes
//! Reference: cpython/Lib/xml/sax/handler.py
//!
//! This module provides base handler classes for SAX2.
//!
//! CPython __all__: ['ContentHandler', 'DTDHandler', 'EntityResolver',
//!                   'ErrorHandler', 'feature_namespaces', 'feature_namespace_prefixes',
//!                   'feature_string_interning', 'feature_validation',
//!                   'feature_external_ges', 'feature_external_pes',
//!                   'all_features', 'property_lexical_handler', 'property_declaration_handler',
//!                   'property_dom_node', 'property_xml_string', 'all_properties']

const std = @import("std");
const sax = @import("../sax.zig");

// Re-export handler classes from parent (DRY)
pub const ContentHandler = sax.ContentHandler;
pub const ErrorHandler = sax.ErrorHandler;
pub const EntityResolver = sax.EntityResolver;
pub const DTDHandler = sax.DTDHandler;
pub const Locator = sax.Locator;
pub const InputSource = sax.InputSource;

// ============================================================================
// Feature URIs
// ============================================================================

/// Namespace feature
pub const feature_namespaces = "http://xml.org/sax/features/namespaces";

/// Namespace prefixes feature
pub const feature_namespace_prefixes = "http://xml.org/sax/features/namespace-prefixes";

/// String interning feature
pub const feature_string_interning = "http://xml.org/sax/features/string-interning";

/// Validation feature
pub const feature_validation = "http://xml.org/sax/features/validation";

/// External general entities feature
pub const feature_external_ges = "http://xml.org/sax/features/external-general-entities";

/// External parameter entities feature
pub const feature_external_pes = "http://xml.org/sax/features/external-parameter-entities";

/// All features
pub const all_features = [_][]const u8{
    feature_namespaces,
    feature_namespace_prefixes,
    feature_string_interning,
    feature_validation,
    feature_external_ges,
    feature_external_pes,
};

// ============================================================================
// Property URIs
// ============================================================================

/// Lexical handler property
pub const property_lexical_handler = "http://xml.org/sax/properties/lexical-handler";

/// Declaration handler property
pub const property_declaration_handler = "http://xml.org/sax/properties/declaration-handler";

/// DOM node property
pub const property_dom_node = "http://xml.org/sax/properties/dom-node";

/// XML string property
pub const property_xml_string = "http://xml.org/sax/properties/xml-string";

/// All properties
pub const all_properties = [_][]const u8{
    property_lexical_handler,
    property_declaration_handler,
    property_dom_node,
    property_xml_string,
};

// ============================================================================
// LexicalHandler
// ============================================================================

/// Lexical handler interface
/// CPython: Not in standard SAX2, but in extension
pub const LexicalHandler = struct {
    const Self = @This();

    comment: ?*const fn (*Self, []const u8) void = null,
    startDTD: ?*const fn (*Self, []const u8, ?[]const u8, ?[]const u8) void = null,
    endDTD: ?*const fn (*Self) void = null,
    startEntity: ?*const fn (*Self, []const u8) void = null,
    endEntity: ?*const fn (*Self, []const u8) void = null,
    startCDATA: ?*const fn (*Self) void = null,
    endCDATA: ?*const fn (*Self) void = null,
};

/// Declaration handler interface
pub const DeclHandler = struct {
    const Self = @This();

    elementDecl: ?*const fn (*Self, []const u8, []const u8) void = null,
    attributeDecl: ?*const fn (*Self, []const u8, []const u8, []const u8, ?[]const u8, ?[]const u8) void = null,
    internalEntityDecl: ?*const fn (*Self, []const u8, []const u8) void = null,
    externalEntityDecl: ?*const fn (*Self, []const u8, ?[]const u8, []const u8) void = null,
};

// ============================================================================
// Tests
// ============================================================================

test "feature URIs" {
    try std.testing.expect(std.mem.startsWith(u8, feature_namespaces, "http://xml.org/sax/"));
    try std.testing.expectEqual(@as(usize, 6), all_features.len);
}

test "property URIs" {
    try std.testing.expect(std.mem.startsWith(u8, property_lexical_handler, "http://xml.org/sax/"));
    try std.testing.expectEqual(@as(usize, 4), all_properties.len);
}
