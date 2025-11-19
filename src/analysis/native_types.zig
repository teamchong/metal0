const std = @import("std");

// Re-export from submodules
pub const StringKind = @import("native_types/core.zig").StringKind;
pub const NativeType = @import("native_types/core.zig").NativeType;
pub const InferError = @import("native_types/core.zig").InferError;
pub const ClassInfo = @import("native_types/core.zig").ClassInfo;
pub const TypeInferrer = @import("native_types/inferrer.zig").TypeInferrer;

// Re-export helper functions if used externally
pub const isConstantList = @import("native_types/core.zig").isConstantList;
pub const allSameType = @import("native_types/core.zig").allSameType;
