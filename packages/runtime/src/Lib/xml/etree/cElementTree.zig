//! xml.etree.cElementTree - C accelerator for ElementTree
//! Reference: cpython/Lib/xml/etree/cElementTree.py
//!
//! This module is provided for backwards compatibility.
//! In Python 3.3+, it's just an alias for ElementTree.
//! In Zig/AOT, we simply re-export ElementTree.

const std = @import("std");

// Re-export everything from ElementTree (DRY)
pub usingnamespace @import("ElementTree.zig");
