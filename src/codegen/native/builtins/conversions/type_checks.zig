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
/// For anytype parameters, generates runtime type check
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("true");
        return;
    }

    // Get the type name being checked against
    const type_name = if (args[1] == .name) args[1].name.id else null;

    // Get the inferred type of the first argument
    const obj_type = self.inferExprScoped(args[0]) catch .unknown;

    // Check if argument has unknown type at inference time
    // This happens for anytype parameters or other dynamic types
    // In this case, generate a runtime type check using @TypeOf
    const is_unknown_type = obj_type == .unknown and args[0] == .name;

    // Perform type check based on type name
    if (type_name) |tname| {
        if (std.mem.eql(u8, tname, "bool")) {
            if (is_unknown_type) {
                // Runtime check: @TypeOf(x) == bool
                try self.emit("(@TypeOf(");
                try self.genExpr(args[0]);
                try self.emit(") == bool)");
                return;
            }
            // isinstance(x, bool) - only true for actual bools
            // In Python: isinstance(True, bool) = True, isinstance(1, bool) = False
            // Reference argument to avoid unused parameter warning
            try self.emit("blk: { _ = @TypeOf(");
            try self.genExpr(args[0]);
            if (obj_type == .bool) {
                try self.emit("); break :blk true; }");
            } else {
                try self.emit("); break :blk false; }");
            }
            return;
        } else if (std.mem.eql(u8, tname, "int")) {
            // Always use runtime check for int to handle anytype params correctly
            // isinstance(x, int) checks if @TypeOf(x) is an integer type or bool
            // Use @typeInfo for comprehensive int checking (handles i64, comptime_int, etc.)
            try self.emit("blk: { const T = @TypeOf(");
            try self.genExpr(args[0]);
            try self.emit("); break :blk @typeInfo(T) == .int or @typeInfo(T) == .comptime_int or T == bool; }");
            return;
        } else if (std.mem.eql(u8, tname, "float")) {
            if (is_unknown_type) {
                try self.emit("(@TypeOf(");
                try self.genExpr(args[0]);
                try self.emit(") == f64)");
                return;
            }
            try self.emit("blk: { _ = @TypeOf(");
            try self.genExpr(args[0]);
            if (obj_type == .float) {
                try self.emit("); break :blk true; }");
            } else {
                try self.emit("); break :blk false; }");
            }
            return;
        } else if (std.mem.eql(u8, tname, "str")) {
            if (is_unknown_type) {
                try self.emit("(@TypeOf(");
                try self.genExpr(args[0]);
                try self.emit(") == []const u8)");
                return;
            }
            try self.emit("blk: { _ = @TypeOf(");
            try self.genExpr(args[0]);
            if (obj_type == .string) {
                try self.emit("); break :blk true; }");
            } else {
                try self.emit("); break :blk false; }");
            }
            return;
        } else if (std.mem.eql(u8, tname, "list")) {
            try self.emit("blk: { _ = @TypeOf(");
            try self.genExpr(args[0]);
            if (obj_type == .list) {
                try self.emit("); break :blk true; }");
            } else {
                try self.emit("); break :blk false; }");
            }
            return;
        } else if (std.mem.eql(u8, tname, "dict")) {
            try self.emit("blk: { _ = @TypeOf(");
            try self.genExpr(args[0]);
            if (obj_type == .dict) {
                try self.emit("); break :blk true; }");
            } else {
                try self.emit("); break :blk false; }");
            }
            return;
        }
    }

    // Default: reference argument and return true for compile-time compatibility
    try self.emit("blk: { _ = @TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("); break :blk true; }");
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
