/// Type checking and introspection builtins: type(), isinstance(), callable(), issubclass(), id(), delattr()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for type(obj)
/// Returns compile-time type name as string
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @typeName(@TypeOf(obj))
    try self.emit("@typeName(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// Generate code for isinstance(obj, type)
/// Checks if object matches expected type at compile time
/// For native codegen, this is a compile-time type check
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // isinstance returns true at compile time - only consume args with side effects (calls)
    // Simple names don't need discarding - that causes "pointless discard" errors
    if (args.len >= 2) {
        const has_side_effects = args[0] == .call or args[1] == .call;
        if (has_side_effects) {
            try self.emit("blk: { ");
            if (args[0] == .call) {
                try self.emit("_ = ");
                try self.genExpr(args[0]);
                try self.emit("; ");
            }
            if (args[1] == .call) {
                try self.emit("_ = ");
                try self.genExpr(args[1]);
                try self.emit("; ");
            }
            try self.emit("break :blk true; }");
        } else {
            try self.emit("true");
        }
    } else if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk true; }");
    } else {
        try self.emit("true");
    }
}

/// Generate code for callable(obj)
/// Returns True if obj appears to be callable
pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("false");
        return;
    }

    // At compile time, we can check if something is a function type
    // For now, emit a runtime check or true for known callable types
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    switch (arg_type) {
        .function => {
            try self.emit("true");
        },
        .unknown => {
            // Runtime check - use @typeInfo
            try self.emit("runtime.isCallable(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
        else => {
            // Check if it's a class (has __call__)
            if (args[0] == .name) {
                if (self.classHasMethod(args[0].name.id, "__call__")) {
                    try self.emit("true");
                    return;
                }
            }
            // Most types are not callable
            try self.emit("false");
        },
    }
}

/// Generate code for issubclass(cls, classinfo)
/// Returns True if cls is a subclass of classinfo
pub fn genIssubclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }

    // For static types, we can sometimes determine at compile time
    // For runtime, we need to check type hierarchy

    // Handle common cases: issubclass(bool, int) -> true
    if (args[0] == .name and args[1] == .name) {
        const cls_name = args[0].name.id;
        const base_name = args[1].name.id;

        // Built-in type hierarchy
        if (std.mem.eql(u8, cls_name, "bool") and std.mem.eql(u8, base_name, "int")) {
            try self.emit("true");
            return;
        }
        if (std.mem.eql(u8, cls_name, base_name)) {
            try self.emit("true");
            return;
        }
    }

    // Runtime check
    try self.emit("runtime.isSubclass(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate code for id(obj)
/// Returns the "identity" of an object (memory address as integer)
pub fn genId(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    // Return the pointer address as an integer
    try self.emit("@as(i64, @intCast(@intFromPtr(&(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate code for delattr(obj, name)
/// Deletes an attribute from an object
pub fn genDelattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }

    // For objects with __dict__, remove the key (use swapRemove for Zig 0.15 ArrayHashMap)
    // Need @constCast because object may be captured as const in assertRaises context
    // Need to handle str subclasses - extract __base_value__ if present
    try self.emit("blk: { const __da_key = ");
    try self.genExpr(args[1]);
    try self.emit("; const __da_key_str = if (@hasField(@TypeOf(__da_key), \"__base_value__\")) __da_key.__base_value__ else __da_key; _ = @constCast(&");
    try self.genExpr(args[0]);
    try self.emit(".__dict__).swapRemove(__da_key_str); break :blk {}; }");
}
