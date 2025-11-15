// Class-related code generation
// This file re-exports all class functionality from submodules

const attributes = @import("classes/attributes.zig");
const classes = @import("classes/classes.zig");
const instantiation = @import("classes/instantiation.zig");
const methods = @import("classes/methods.zig");
const c_ffi = @import("classes/c_ffi.zig");

// Re-export public functions
pub const visitAttribute = attributes.visitAttribute;
pub const visitClassDef = classes.visitClassDef;
pub const visitClassInstantiation = instantiation.visitClassInstantiation;
pub const visitMethodCall = methods.visitMethodCall;
