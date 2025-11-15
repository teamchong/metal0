const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("../../codegen.zig").CodegenError;
const ExprResult = @import("../../codegen.zig").ExprResult;
const ZigCodeGenerator = @import("../../codegen.zig").ZigCodeGenerator;
const expressions = @import("../expressions.zig");
const statements = @import("../statements.zig");

pub fn visitAttribute(self: *ZigCodeGenerator, attr: ast.Node.Attribute) CodegenError!ExprResult {
    // Check if base is an imported module (e.g., np in np.array)
    if (attr.value.* == .name) {
        const var_name = attr.value.name.id;
        if (self.imported_modules.contains(var_name)) {
            // This is a module attribute access (e.g., np.array)
            var buf = std.ArrayList(u8){};
            try buf.writer(self.temp_allocator).print(
                "try python.getattr(allocator, {s}, \"{s}\")",
                .{ var_name, attr.attr }
            );
            return ExprResult{
                .code = try buf.toOwnedSlice(self.temp_allocator),
                .needs_try = false,
                .needs_decref = false, // Python manages refcounting
            };
        }
    }

    // Regular attribute access (for PyObjects or user classes)
    const value_result = try expressions.visitExpr(self, attr.value.*);
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("{s}.{s}", .{ value_result.code, attr.attr });
    return ExprResult{
        .code = try buf.toOwnedSlice(self.temp_allocator),
        .needs_try = false,
    };
}

