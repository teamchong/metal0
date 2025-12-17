/// Del statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");

/// Generate del statement
/// Handles: del dict[key] -> dict.remove(key)
///          del list[idx] -> list orderedRemove
///          del var -> no-op (variable scope, memory hint)
pub fn genDel(self: *NativeCodegen, del_node: ast.Node.Del) CodegenError!void {
    for (del_node.targets) |target| {
        try self.emitIndent();
        switch (target) {
            .subscript => |sub| {
                // del dict[key] or del list[idx]
                // Generate: _ = dict.fetchSwapRemove(key) or _ = list.orderedRemove(idx)
                switch (sub.slice) {
                    .index => |idx| {
                        // Check if it's a list (ArrayList) or dict
                        const container_type = try self.inferExprScoped(sub.value.*);
                        const is_list = container_traits.isList(container_type) or type_traits.isArray(container_type) or
                            (sub.value.* == .name and self.isArrayListVar(sub.value.name.id));

                        try self.emit("_ = ");
                        try self.genExpr(sub.value.*);

                        if (is_list) {
                            // For lists, use orderedRemove which preserves order
                            // Need to normalize negative indices: if idx < 0, use len + idx
                            const id = self.nextNameId();
                            try self.emitFmt(".orderedRemove(__del_blk_{d}: {{ const __idx_{d} = ", .{ id, id });
                            try self.genExpr(idx.*);
                            try self.emitFmt("; const __len_{d} = ", .{id});
                            try self.genExpr(sub.value.*);
                            try self.emitFmt(".items.len; break :__del_blk_{d} if (__idx_{d} < 0) @as(usize, @intCast(@as(i64, @intCast(__len_{d})) + __idx_{d})) else @as(usize, @intCast(__idx_{d})); }});\n", .{ id, id, id, id, id });
                        } else {
                            // For dicts, use fetchSwapRemove (returns removed value or null)
                            try self.emit(".fetchSwapRemove(");
                            try self.genExpr(idx.*);
                            try self.emit(");\n");
                        }
                    },
                    .slice => |slice| {
                        // del list[a:b] - delete elements from a to b
                        // Use replaceRange with empty slice to remove elements
                        try self.emit("{\n");
                        self.indent();

                        // Get list reference - handle ArrayList aliases
                        try self.emitIndent();
                        try self.emit("const __list = ");
                        if (sub.value.* == .name) {
                            const var_name = sub.value.name.id;
                            if (self.isArrayListAlias(var_name)) {
                                // Alias is already a pointer, just use it directly
                                try self.genExpr(sub.value.*);
                            } else {
                                // Regular ArrayList, take address
                                try self.emit("&");
                                try self.genExpr(sub.value.*);
                            }
                        } else {
                            try self.emit("&");
                            try self.genExpr(sub.value.*);
                        }
                        try self.emit(";\n");

                        // Calculate start index
                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emit("const __start: usize = @intCast(");
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __start: usize = 0;\n");
                        }

                        // Calculate end index
                        try self.emitIndent();
                        if (slice.upper) |upper| {
                            try self.emit("const __end: usize = @intCast(");
                            try self.genExpr(upper.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __end: usize = __list.items.len;\n");
                        }

                        // Replace slice with empty slice to delete elements
                        // replaceRange(allocator, start, length, replacement)
                        try self.emitIndent();
                        try self.emit("const __empty: [0]@TypeOf(__list.items[0]) = .{};\n");
                        try self.emitIndent();
                        try self.emit("__list.replaceRange(__global_allocator, __start, __end - __start, &__empty) catch unreachable;\n");

                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    },
                }
            },
            .attribute => |attr| {
                // del obj.attr - no-op in compiled code (would need dynamic attr deletion)
                try self.emit("// del ");
                try self.genExpr(attr.value.*);
                try self.emit(".");
                try self.emit(attr.attr);
                try self.emit(" (no-op in AOT)\n");
            },
            .name => {
                // del var - just a memory hint in Python, no-op in compiled code
                try self.emit("// del ");
                try self.emit(target.name.id);
                try self.emit(" (no-op in AOT)\n");
            },
            else => {
                // Unsupported target type
                try self.emit("// del statement (no-op in AOT)\n");
            },
        }
    }
}
