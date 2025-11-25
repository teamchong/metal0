/// Comptime stdlib bridge - generates handlers from specs
/// Reduces boilerplate: 215 hand-written handlers → ~50 lines of specs
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Spec for a simple runtime call (Pattern 1: direct passthrough)
pub const SimpleCallSpec = struct {
    runtime_path: []const u8, // e.g. "runtime.re.search"
    arg_count: u8,
    needs_allocator: bool = true,
};

/// Generate handler for simple call pattern
/// Input: re.search(pattern, text)
/// Output: try runtime.re.search(allocator, {arg0}, {arg1})
pub fn genSimpleCall(comptime spec: SimpleCallSpec) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct {
        pub fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len != spec.arg_count) {
                std.debug.print("{s} expects {d} args, got {d}\n", .{ spec.runtime_path, spec.arg_count, args.len });
                return;
            }

            try self.emit("try " ++ spec.runtime_path ++ "(");
            if (spec.needs_allocator) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (spec.arg_count > 0) {
                    try self.emit(", ");
                }
            }

            inline for (0..spec.arg_count) |i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(args[i]);
            }

            try self.emit(")");
        }
    }.handler;
}

/// Spec for no-arg functions that return a value
pub const NoArgCallSpec = struct {
    runtime_path: []const u8,
    needs_allocator: bool = true,
};

pub fn genNoArgCall(comptime spec: NoArgCallSpec) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct {
        pub fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len != 0) {
                std.debug.print("{s} takes no arguments\n", .{spec.runtime_path});
                return;
            }

            try self.emit("try " ++ spec.runtime_path ++ "(");
            if (spec.needs_allocator) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
            }
            try self.emit(")");
        }
    }.handler;
}

/// Spec for variable-arg functions (1 to N args)
pub const VarArgCallSpec = struct {
    runtime_path: []const u8,
    min_args: u8,
    max_args: u8,
    needs_allocator: bool = true,
};

pub fn genVarArgCall(comptime spec: VarArgCallSpec) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct {
        pub fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len < spec.min_args or args.len > spec.max_args) {
                std.debug.print("{s} expects {d}-{d} args, got {d}\n", .{ spec.runtime_path, spec.min_args, spec.max_args, args.len });
                return;
            }

            try self.emit("try " ++ spec.runtime_path ++ "(");
            if (spec.needs_allocator) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (args.len > 0) {
                    try self.emit(", ");
                }
            }

            for (args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(arg);
            }

            try self.emit(")");
        }
    }.handler;
}

/// Spec for functions without try (no error return)
pub const NoTryCallSpec = struct {
    runtime_path: []const u8,
    arg_count: u8,
    needs_allocator: bool = false,
};

pub fn genNoTryCall(comptime spec: NoTryCallSpec) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct {
        pub fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len != spec.arg_count) {
                std.debug.print("{s} expects {d} args, got {d}\n", .{ spec.runtime_path, spec.arg_count, args.len });
                return;
            }

            try self.emit(spec.runtime_path ++ "(");
            if (spec.needs_allocator) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (spec.arg_count > 0) {
                    try self.emit(", ");
                }
            }

            inline for (0..spec.arg_count) |i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(args[i]);
            }

            try self.emit(")");
        }
    }.handler;
}

/// Spec for calls that access a field on the result (e.g., http.get(url).body)
pub const FieldAccessCallSpec = struct {
    runtime_path: []const u8,
    arg_count: u8,
    field: []const u8, // e.g. "body"
    needs_allocator: bool = true,
    needs_try: bool = false,
};

pub fn genFieldAccessCall(comptime spec: FieldAccessCallSpec) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct {
        pub fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len != spec.arg_count) {
                std.debug.print("{s} expects {d} args, got {d}\n", .{ spec.runtime_path, spec.arg_count, args.len });
                return;
            }

            if (spec.needs_try) {
                try self.emit("try ");
            }
            try self.emit(spec.runtime_path ++ "(");
            if (spec.needs_allocator) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (spec.arg_count > 0) {
                    try self.emit(", ");
                }
            }

            inline for (0..spec.arg_count) |i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(args[i]);
            }

            try self.emit(")." ++ spec.field);
        }
    }.handler;
}
