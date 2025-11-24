/// Method call dispatchers (string, list, dict methods)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const methods = @import("../methods.zig");
const pandas_mod = @import("../pandas.zig");

/// Try to dispatch method call (obj.method())
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, call: ast.Node.Call) CodegenError!bool {
    if (call.func.* != .attribute) return false;

    const method_name = call.func.attribute.attr;

    // String methods
    if (std.mem.eql(u8, method_name, "split")) {
        try methods.genSplit(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "upper")) {
        try methods.genUpper(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "lower")) {
        try methods.genLower(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "strip")) {
        try methods.genStrip(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "replace")) {
        try methods.genReplace(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "join")) {
        try methods.genJoin(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "startswith")) {
        try methods.genStartswith(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "endswith")) {
        try methods.genEndswith(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "find")) {
        try methods.genFind(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "count")) {
        try methods.genCount(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isdigit")) {
        try methods.genIsdigit(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isalpha")) {
        try methods.genIsalpha(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isalnum")) {
        try methods.genIsalnum(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isspace")) {
        try methods.genIsspace(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "islower")) {
        try methods.genIslower(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isupper")) {
        try methods.genIsupper(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "lstrip")) {
        try methods.genLstrip(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "rstrip")) {
        try methods.genRstrip(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "capitalize")) {
        try methods.genCapitalize(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "title")) {
        try methods.genTitle(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "swapcase")) {
        try methods.genSwapcase(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "index")) {
        try methods.genStrIndex(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "rfind")) {
        try methods.genRfind(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "rindex")) {
        try methods.genRindex(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "ljust")) {
        try methods.genLjust(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "rjust")) {
        try methods.genRjust(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "center")) {
        try methods.genCenter(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "zfill")) {
        try methods.genZfill(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isascii")) {
        try methods.genIsascii(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "istitle")) {
        try methods.genIstitle(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "isprintable")) {
        try methods.genIsprintable(self, call.func.attribute.value.*, call.args);
        return true;
    }

    // List methods
    if (std.mem.eql(u8, method_name, "append")) {
        try methods.genAppend(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "pop")) {
        try methods.genPop(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "extend")) {
        try methods.genExtend(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "insert")) {
        try methods.genInsert(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "remove")) {
        try methods.genRemove(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "index")) {
        try methods.genIndex(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "count")) {
        // Check if it's a list or string - lists use list.genCount, strings use string.genCount
        const obj = call.func.attribute.value.*;
        const is_list = blk: {
            if (obj == .name) {
                const var_name = obj.name.id;
                if (self.getSymbolType(var_name)) |var_type| {
                    break :blk switch (var_type) {
                        .list => true,
                        else => false,
                    };
                }
            }
            break :blk false;
        };

        if (is_list) {
            const genListCount = @import("../methods/list.zig").genCount;
            try genListCount(self, call.func.attribute.value.*, call.args);
        } else {
            // Default to string.genCount
            try methods.genCount(self, call.func.attribute.value.*, call.args);
        }
        return true;
    }
    if (std.mem.eql(u8, method_name, "reverse")) {
        try methods.genReverse(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "sort")) {
        try methods.genSort(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "clear")) {
        try methods.genClear(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "copy")) {
        try methods.genCopy(self, call.func.attribute.value.*, call.args);
        return true;
    }

    // Dict methods
    if (std.mem.eql(u8, method_name, "get") and call.args.len > 0) {
        // Only handle dict.get(key) - class methods with no args fall through
        try methods.genGet(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "keys")) {
        try methods.genKeys(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "values")) {
        try methods.genValues(self, call.func.attribute.value.*, call.args);
        return true;
    }
    if (std.mem.eql(u8, method_name, "items")) {
        try methods.genItems(self, call.func.attribute.value.*, call.args);
        return true;
    }

    // Queue methods (asyncio.Queue)
    if (std.mem.eql(u8, method_name, "put_nowait")) {
        try self.output.appendSlice(self.allocator, "try ");
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, call.func.attribute.value.*);
        try self.output.appendSlice(self.allocator, ".put_nowait(");
        if (call.args.len > 0) {
            try parent.genExpr(self, call.args[0]);
        }
        try self.output.appendSlice(self.allocator, ")");
        return true;
    }
    if (std.mem.eql(u8, method_name, "get_nowait")) {
        try self.output.appendSlice(self.allocator, "try ");
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, call.func.attribute.value.*);
        try self.output.appendSlice(self.allocator, ".get_nowait()");
        return true;
    }
    if (std.mem.eql(u8, method_name, "empty")) {
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, call.func.attribute.value.*);
        try self.output.appendSlice(self.allocator, ".empty()");
        return true;
    }
    if (std.mem.eql(u8, method_name, "full")) {
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, call.func.attribute.value.*);
        try self.output.appendSlice(self.allocator, ".full()");
        return true;
    }
    if (std.mem.eql(u8, method_name, "qsize")) {
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, call.func.attribute.value.*);
        try self.output.appendSlice(self.allocator, ".qsize()");
        return true;
    }

    // Pandas Column methods (DataFrame column operations)
    // Check if the object is a DataFrame column by looking for subscript on DataFrame
    const is_column_method = blk: {
        const obj = call.func.attribute.value.*;
        break :blk obj == .subscript; // df['col'].method()
    };

    if (is_column_method) {
        if (std.mem.eql(u8, method_name, "sum")) {
            try pandas_mod.genColumnSum(self, call.func.attribute.value.*);
            return true;
        }
        if (std.mem.eql(u8, method_name, "mean")) {
            try pandas_mod.genColumnMean(self, call.func.attribute.value.*);
            return true;
        }
        if (std.mem.eql(u8, method_name, "describe")) {
            try pandas_mod.genColumnDescribe(self, call.func.attribute.value.*);
            return true;
        }
        if (std.mem.eql(u8, method_name, "min")) {
            try pandas_mod.genColumnMin(self, call.func.attribute.value.*);
            return true;
        }
        if (std.mem.eql(u8, method_name, "max")) {
            try pandas_mod.genColumnMax(self, call.func.attribute.value.*);
            return true;
        }
        if (std.mem.eql(u8, method_name, "std")) {
            try pandas_mod.genColumnStd(self, call.func.attribute.value.*);
            return true;
        }
    }

    return false;
}
