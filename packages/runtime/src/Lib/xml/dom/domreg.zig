//! xml.dom.domreg - DOM Implementation Registry
//! Reference: cpython/Lib/xml/dom/domreg.py
//!
//! This module manages DOM implementation registration and retrieval.

const std = @import("std");
const dom = @import("../dom.zig");

// Re-export from parent dom module (DRY)
pub const getDOMImplementation = dom.getDOMImplementation;
pub const registerDOMImplementation = dom.registerDOMImplementation;
pub const DOMImplementation = dom.DOMImplementation;

/// Well-known implementations
pub const well_known_implementations = [_]struct { name: []const u8, module: []const u8 }{
    .{ .name = "minidom", .module = "xml.dom.minidom" },
    .{ .name = "pulldom", .module = "xml.dom.pulldom" },
};
