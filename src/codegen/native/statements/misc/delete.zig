/// Del statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Generate del statement
/// Handles: del dict[key] -> dict.remove(key)
///          del list[idx] -> list orderedRemove
///          del var -> no-op (variable scope, memory hint)
pub fn genDel(self: *NativeCodegen, del_node: ast.Node.Del) CodegenError!void {
    const b = try self.getBuilder();

    for (del_node.targets) |target| {
        try b.writeIndent();
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

                        // Capture expressions
                        const container_val = try self.captureExpr(sub.value.*);
                        const idx_val = try self.captureExpr(idx.*);

                        try b.write("_ = ");
                        try b.emitValue(container_val, .{});

                        if (is_list) {
                            // For lists, use orderedRemove which preserves order
                            // Need to normalize negative indices: if idx < 0, use len + idx
                            const id = self.nextNameId();
                            try b.writeFmt(".orderedRemove(__del_blk_{d}: {{ const __idx_{d} = ", .{ id, id });
                            try b.emitValue(idx_val, .{});
                            try b.writeFmt("; const __len_{d} = ", .{id});
                            try b.emitValue(container_val, .{});
                            try b.writeFmt(".items.len; break :__del_blk_{d} if (__idx_{d} < 0) @as(usize, @intCast(@as(i64, @intCast(__len_{d})) + __idx_{d})) else @as(usize, @intCast(__idx_{d})); }});\n", .{ id, id, id, id, id });
                        } else {
                            // For dicts, use fetchSwapRemove (returns removed value or null)
                            try b.write(".fetchSwapRemove(");
                            try b.emitValue(idx_val, .{});
                            try b.write(");\n");
                        }
                    },
                    .slice => |slice| {
                        // del list[a:b] - delete elements from a to b
                        // Use replaceRange with empty slice to remove elements
                        try b.write("{\n");
                        b.indent();

                        // Capture list expression
                        const list_val = try self.captureExpr(sub.value.*);

                        // Get list reference - handle ArrayList aliases
                        try b.writeIndent();
                        try b.write("const __list = ");
                        if (sub.value.* == .name) {
                            const var_name = sub.value.name.id;
                            if (self.isArrayListAlias(var_name)) {
                                // Alias is already a pointer, just use it directly
                                try b.emitValue(list_val, .{});
                            } else {
                                // Regular ArrayList, take address
                                try b.write("&");
                                try b.emitValue(list_val, .{});
                            }
                        } else {
                            try b.write("&");
                            try b.emitValue(list_val, .{});
                        }
                        try b.write(";\n");

                        // Calculate start index
                        try b.writeIndent();
                        if (slice.lower) |lower| {
                            const lower_val = try self.captureExpr(lower.*);
                            try b.write("const __start: usize = @intCast(");
                            try b.emitValue(lower_val, .{});
                            try b.write(");\n");
                        } else {
                            try b.write("const __start: usize = 0;\n");
                        }

                        // Calculate end index
                        try b.writeIndent();
                        if (slice.upper) |upper| {
                            const upper_val = try self.captureExpr(upper.*);
                            try b.write("const __end: usize = @intCast(");
                            try b.emitValue(upper_val, .{});
                            try b.write(");\n");
                        } else {
                            try b.write("const __end: usize = __list.items.len;\n");
                        }

                        // Replace slice with empty slice to delete elements
                        // replaceRange(allocator, start, length, replacement)
                        try b.writeIndent();
                        try b.write("const __empty: [0]@TypeOf(__list.items[0]) = .{};\n");
                        try b.writeIndent();
                        try b.write("__list.replaceRange(__global_allocator, __start, __end - __start, &__empty) catch unreachable;\n");

                        b.dedent();
                        try b.writeIndent();
                        try b.write("}\n");
                    },
                }
            },
            .attribute => |attr| {
                // del obj.attr - no-op in compiled code (would need dynamic attr deletion)
                const attr_val = try self.captureExpr(attr.value.*);
                try b.write("// del ");
                try b.emitValue(attr_val, .{});
                try b.write(".");
                try b.write(attr.attr);
                try b.write(" (no-op in AOT)\n");
            },
            .name => {
                // del var - just a memory hint in Python, no-op in compiled code
                try b.write("// del ");
                try b.write(target.name.id);
                try b.write(" (no-op in AOT)\n");
            },
            else => {
                // Unsupported target type
                try b.write("// del statement (no-op in AOT)\n");
            },
        }
    }

    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
